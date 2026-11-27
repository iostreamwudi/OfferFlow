import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ApplicationProfileView: View {
    @ObservedObject var store: ApplicationProfileStore
    @State private var versions = CandidateMaterials.versions
    @State private var selectedVersion = ""
    @State private var selectedSection = "resume"
    @State private var resumeText = ""
    @State private var filename = ""
    @State private var isParsing = false
    @State private var isReading = false
    @State private var message = ""
    @State private var proposal: ApplicationResumeProposal?
    @State private var selectedSuggestions = Set<String>()
    @State private var showReview = false
    @State private var replaceExisting = false
    @State private var parsingTask: Task<Void, Never>?
    @State private var parsingGeneration = UUID()
    @State private var pendingRemoval: (section: String, id: String)?
    @State private var showRemoval = false
    private let columns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    init(store: ApplicationProfileStore, initialSection: String = "resume") {
        self.store = store; _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        FlowSurface {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                categoryNavigation
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !message.isEmpty {
                            Label(message, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(muted)
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(canvas, in: RoundedRectangle(cornerRadius: 10))
                        }
                        if selectedSection == "resume" { resumePanel }
                        else if selectedSection == "attachments" { attachmentsPanel }
                        else if let section = ApplicationProfileCatalog.section(selectedSection) { sectionEditor(section) }
                    }.padding(28).frame(maxWidth: 1080, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                }.background(.white)
            }
        }.foregroundStyle(ink).background(.white).tint(accent)
        .sheet(isPresented: $showReview) { reviewPanel }
        .alert("删除这条经历？", isPresented: $showRemoval) {
            Button("取消", role: .cancel) { pendingRemoval = nil }
            Button("删除", role: .destructive) {
                if let item = pendingRemoval { store.removeEntry(item.section, id: item.id) }
                pendingRemoval = nil
            }
        } message: { Text("该条经历会从本机网申档案移除。") }
        .onAppear { loadExistingResume() }
        .onDisappear { parsingGeneration = UUID(); parsingTask?.cancel(); store.save() }
    
        }
    }
    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("个人资料").font(.system(size: 24, weight: .bold))
                Text("一份完整网申档案，重复填写交给助手")
                    .font(.system(size: 12)).foregroundStyle(muted)
            }
            Spacer(minLength: 10)
            Label(store.status, systemImage: store.hasSaveError ? "exclamationmark.circle" : "checkmark.circle")
                .font(.system(size: 11)).foregroundStyle(store.hasSaveError ? Color.orange : muted)
            Button("保存资料", systemImage: "checkmark") { store.save() }
                .buttonStyle(.flowPrimary)
        }.padding(.horizontal, 28).padding(.vertical, 22)
    }
    private var categoryNavigation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                categoryButton("resume", title: "简历解析", icon: "doc.viewfinder", detail: store.profile.resumeFilename.isEmpty ? "导入真实简历" : "已导入")
                Divider().padding(.vertical, 9)
                ForEach(ApplicationProfileCatalog.sections) { section in
                    let completion = store.profile.completion(section)
                    categoryButton(section.id, title: section.title, icon: section.icon, detail: completion.filled == 0 ? "待填写" : "\(completion.filled) 项")
                }
                Divider().padding(.vertical, 9)
                categoryButton("attachments", title: "附件材料", icon: "paperclip", detail: "\(store.profile.attachments.count) 份")
            }.padding(12)
        }.frame(width: 186).background(canvas)
    }
    private func categoryButton(_ id: String, title: String, icon: String, detail: String) -> some View {
        Button { selectedSection = id; message = "" } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).frame(width: 17)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: selectedSection == id ? .semibold : .regular))
                    Text(detail).font(.system(size: 10)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
            }.foregroundStyle(selectedSection == id ? accent : ink).padding(.horizontal, 11).padding(.vertical, 10)
                .background(selectedSection == id ? accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("资料分类：\(title)")
    }
    private var resumePanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("从简历开始，补齐你的网申档案").font(.system(size: 21, weight: .semibold))
            Text("提取基本资料、教育、工作与项目等经历，核对后导入。没有写在简历里的信息会留空，已有资料可保留，也可核对后更新。")
                .font(.system(size: 13)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 14) {
                Image(systemName: "doc.badge.arrow.up").font(.system(size: 35, weight: .light)).foregroundStyle(accent)
                Text(filename.isEmpty ? "导入简历或使用已保存的简历" : filename).font(.system(size: 15, weight: .medium))
                Text("PDF / DOC / DOCX / RTF / TXT / Markdown · 最大 10 MB")
                    .font(.system(size: 11)).foregroundStyle(muted)
                HStack(spacing: 10) {
                    Button("选择简历文件") { importResume() }.buttonStyle(.flowPrimary)
                    Button("使用已保存简历") { loadExistingResume() }
                }.disabled(isParsing || isReading)
                if isReading { ProgressView("正在读取文件…").controlSize(.small) }
            }.frame(maxWidth: .infinity).padding(28).background(accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5])))
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("简历文字").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(resumeText.count) 字").font(.system(size: 11)).foregroundStyle(muted)
                }
                TextEditor(text: $resumeText).font(.system(size: 12)).lineSpacing(4)
                    .padding(9).frame(minHeight: 180, maxHeight: 260)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1)))
                    .accessibilityLabel("待解析简历原文").disabled(isReading || isParsing)
                Text("也可以直接粘贴文字。点击解析后，以上内容会发送至你在「AI 设置」中配置的模型；解析结果先由你核对。")
                    .font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isParsing { ProgressView().controlSize(.small); Text("正在提取并核验简历事实…").font(.system(size: 12)).foregroundStyle(muted) }
                Spacer()
                if isParsing { Button("取消解析") { parsingGeneration = UUID(); parsingTask?.cancel(); isParsing = false } }
                Button(isParsing ? "解析中" : "开始解析", systemImage: "sparkles") { parseResume() }
                    .buttonStyle(.flowPrimary).disabled(isParsing || isReading || resumeText.trimmingCharacters(in: .whitespacesAndNewlines).count < 30)
            }
            HStack {
                Button("保存为默认简历") {
                    do { try CandidateMaterials.save(.init(filename: filename.isEmpty ? "粘贴的简历" : filename, name: store.profile.values["basic.name"] ?? "", text: resumeText)); versions = CandidateMaterials.versions; message = "默认简历已更新；结构化资料用于已核对的经历，解析并核对后可更新。" } catch { message = error.localizedDescription }
                }.disabled(resumeText.trimmingCharacters(in: .whitespacesAndNewlines).count < 30)
                Button("AI 设置") { FlowIntent(route: "settings").post() }
            }
            if !versions.isEmpty {
                FlowSelect(title: "历史简历", selection: $selectedVersion, options: [("", "选择历史版本，可预览后设为默认")] + versions.map { ($0.id, $0.material.filename + " · " + $0.date.formatted(date: .abbreviated, time: .shortened)) })
                    .onChange(of: selectedVersion) { _, id in if let version = versions.first(where: { $0.id == id }) { resumeText = version.material.text; filename = version.material.filename } }
            }
            Text("BOSS 和陪练默认使用最新已核对的个人经历；档案尚未有经历时使用默认简历。") .font(.caption).foregroundStyle(.secondary)
            Text("网申档案包含 \(ApplicationProfileCatalog.sections.count) 类资料、\(ApplicationProfileCatalog.sections.reduce(0) { $0 + $1.fields.count }) 种字段，可添加多段经历与自定义问答。仅填写你愿意提供且真实的信息。")
                .font(.system(size: 11)).foregroundStyle(muted).padding(.top, 8)
        }
    }
    private func sectionEditor(_ section: ApplicationProfileSection) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if section.id == "custom" {
                Text("可手动添加个人问答。常用网申字段在基本信息、教育经历等对应分类中维护。")
                    .font(.system(size: 12)).foregroundStyle(muted)
            }
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(section.title).font(.system(size: 21, weight: .semibold))
                    let completion = store.profile.completion(section)
                    Text("已填写 \(completion.filled) / \(completion.total) 项 · 根据目标网站要求补充")
                        .font(.system(size: 11)).foregroundStyle(muted)
                }
                Spacer()
                if section.repeated { Button("添加一条", systemImage: "plus") { store.addEntry(section.id) } }
            }
            if section.id == "basic" { personalPhotoPanel }
            if section.repeated {
                let entries = store.profile.entries[section.id, default: []]
                if entries.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: section.icon).font(.system(size: 27)).foregroundStyle(muted)
                        Text("尚未添加\(section.title)").font(.system(size: 14, weight: .medium))
                        Button("添加\(section.title)") { store.addEntry(section.id) }.buttonStyle(.flowPrimary)
                    }.frame(maxWidth: .infinity).padding(40).background(canvas, in: RoundedRectangle(cornerRadius: 12))
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("\(section.title) \(index + 1)").font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Button { _ = store.moveEntry(section.id, id: entry.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                .buttonStyle(.borderless).disabled(index == 0)
                                .help("上移这条经历").accessibilityLabel("上移\(section.title)第\(index + 1)条")
                            Button { _ = store.moveEntry(section.id, id: entry.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                .buttonStyle(.borderless).disabled(index == entries.count - 1)
                                .help("下移这条经历").accessibilityLabel("下移\(section.title)第\(index + 1)条")
                            Button("删除", systemImage: "trash") { pendingRemoval = (section.id, entry.id); showRemoval = true }
                                .buttonStyle(.borderless).foregroundStyle(muted)
                                .accessibilityLabel("删除\(section.title)第\(index + 1)条")
                        }
                        if section.id == "custom", let source = entry.values["sourceURL"] {
                            let region = ApplicationProfileCatalog.section(entry.values["sourceSection"] ?? "")
                            Text("来自 \(URL(string: source)?.host ?? "网申页面") · \(region?.title ?? "其他信息")")
                                .font(.system(size: 11)).foregroundStyle(muted)
                            if region?.repeated != true && entry.values["sourceSection"]?.isEmpty == false {
                                Toggle("这是通用个人信息，可用于其他网申", isOn: Binding(
                                    get: { store.profile.entries["custom"]?.first { $0.id == entry.id }?.values["reuseScope"] == "general" },
                                    set: { enabled in
                                        guard let index = store.profile.entries["custom"]?.firstIndex(where: { $0.id == entry.id }) else { return }
                                        store.profile.entries["custom"]![index].values["reuseScope"] = enabled ? "general" : "source"
                                    }))
                                    .font(.system(size: 12))
                            } else {
                                Text("经历相关的答案仅用于原网申的对应记录。")
                                    .font(.system(size: 11)).foregroundStyle(muted)
                            }
                        }
                        fieldGrid(section, entryID: entry.id)
                    }.padding(22).background(canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                }
            } else { fieldGrid(section, entryID: nil) }
        }
    }
    private func fieldGrid(_ section: ApplicationProfileSection, entryID: String?) -> some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(section.fields.filter { !$0.multiline }) { field in fieldEditor(section, field: field, entryID: entryID) }
            }
            ForEach(section.fields.filter(\.multiline)) { field in fieldEditor(section, field: field, entryID: entryID) }
        }
    }
    private func fieldEditor(_ section: ApplicationProfileSection, field: ApplicationProfileField, entryID: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.label).font(.system(size: 12, weight: .medium))
            if field.multiline {
                TextEditor(text: valueBinding(section.id, key: field.key, entryID: entryID))
                    .font(.system(size: 12)).padding(8).frame(height: 105).background(.white)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.12)))
                    .accessibilityLabel("\(section.title)·\(field.label)")
            } else {
                TextField(placeholder(field), text: valueBinding(section.id, key: field.key, entryID: entryID))
                    .textFieldStyle(.plain).font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 11)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.12)))
                    .accessibilityLabel("\(section.title)·\(field.label)")
            }
        }
    }
    private func placeholder(_ field: ApplicationProfileField) -> String {
        if field.key == "nativePlace" { return "例如：湖北省襄阳市襄城区" }
        if field.key.hasSuffix("Date") || field.key == "date" { return "YYYY-MM-DD 或 YYYY-MM" }
        return "填写\(field.label)"
    }
    private func valueBinding(_ section: String, key: String, entryID: String?) -> Binding<String> {
        Binding(get: {
            if let entryID { return store.profile.entries[section]?.first { $0.id == entryID }?.values[key] ?? "" }
            return store.profile.values["\(section).\(key)", default: ""]
        }, set: { value in
            if let entryID, let index = store.profile.entries[section]?.firstIndex(where: { $0.id == entryID }) {
                store.profile.entries[section]?[index].values[key] = value
            } else if entryID == nil { store.profile.values["\(section).\(key)"] = value }
        })
    }
    private var personalPhoto: ApplicationProfileAttachment? {
        store.profile.attachments.first { $0.kind == "个人照片" } ?? store.profile.attachments.first { $0.kind == "证件照" }
    }
    private var personalPhotoPanel: some View {
        HStack(alignment: .center, spacing: 20) {
            Group {
                if let photo = personalPhoto, let image = NSImage(contentsOfFile: photo.path) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else { Image(systemName: "person.crop.rectangle").font(.system(size: 36)).foregroundStyle(muted) }
            }.frame(width: 100, height: 120).background(canvas, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 9) {
                Text("个人照片").font(.system(size: 14, weight: .semibold))
                Text(personalPhoto?.name ?? "选择一张个人照片或证件照")
                    .font(.system(size: 12)).foregroundStyle(muted)
                HStack {
                    Button(personalPhoto == nil ? "选择照片" : "更换照片", systemImage: "photo") { choosePersonalPhoto() }
                    if let photo = personalPhoto {
                        Button("预览") { NSWorkspace.shared.open(URL(fileURLWithPath: photo.path)) }
                        Button("移除") { store.profile.attachments.removeAll { $0.id == photo.id }; _ = store.save() }
                    }
                }
                Text("支持 JPG、PNG、HEIC 等图片，仅在本机管理，不会随一键填写自动上传。")
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer()
        }.padding(18).background(canvas.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
    private func choosePersonalPhoto() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10 * 1024 * 1024, NSImage(contentsOf: url) != nil else { throw ProfileError.message("请选择可读取的图片，单张不超过 10MB。") }
            let image = try ApplicationProfileStorage().importAttachment(from: url, kind: "个人照片")
            if let current = personalPhoto, let index = store.profile.attachments.firstIndex(where: { $0.id == current.id }) { store.profile.attachments[index] = image }
            else { store.profile.attachments.append(image) }
            if store.save() { message = "个人照片已保存到本机。" } else { message = store.status }
        } catch { message = "照片导入失败：" + error.localizedDescription }
    }
    private var attachmentsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("附件材料").font(.system(size: 21, weight: .semibold))
                Spacer()
                Button("添加文件", systemImage: "plus") { addAttachments() }
            }
            Text("一键填写只上传已配置的简历。其他材料可以留在本机管理，不会自动上传，也不会计入待处理清单。")
                .font(.system(size: 12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            personalPhotoPanel
            if store.profile.attachments.isEmpty {
                Text("尚未添加附件").font(.system(size: 13)).foregroundStyle(muted).padding(.vertical, 25)
            }
            ForEach(store.profile.attachments) { attachment in
                HStack(spacing: 12) {
                    Image(systemName: "doc").font(.system(size: 21)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(attachment.name).font(.system(size: 13, weight: .medium))
                        Text(attachment.path).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
                    }
                    Spacer()
                    FlowSelect(title: "材料用途", selection: Binding(get: { ["简历", "个人照片", "证件照", "身份证正面", "身份证反面", "成绩单", "学历证", "学位证", "作品集"].contains(attachment.kind) ? attachment.kind : (attachment.name == store.profile.resumeFilename ? "简历" : "其他") }, set: { kind in
                        if let index = store.profile.attachments.firstIndex(where: { $0.id == attachment.id }) { store.profile.attachments[index].kind = kind }
                    }), options: ["简历", "个人照片", "证件照", "身份证正面", "身份证反面", "成绩单", "学历证", "学位证", "作品集", "其他"].map { ($0, $0) }).frame(width: 150)
                    if attachment.kind == "简历" {
                        Button(store.profile.defaultResumeAttachmentID == attachment.id ? "默认上传" : "设为上传简历") { store.profile.defaultResumeAttachmentID = attachment.id; store.profile.resumeFilename = attachment.name; store.save() }.disabled(store.profile.defaultResumeAttachmentID == attachment.id)
                    }
                    Button("定位") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: attachment.path)]) }
                    Button("移除") { if store.profile.defaultResumeAttachmentID == attachment.id { store.profile.defaultResumeAttachmentID = nil }; store.profile.attachments.removeAll { $0.id == attachment.id } }
                }.padding(14).background(canvas, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }
    private var reviewPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("核对简历解析结果").font(.system(size: 22, weight: .bold))
                    Text("默认补充空白字段。也可用已核验的新简历更新已有资料。")
                        .font(.system(size: 12)).foregroundStyle(muted)
                }
                Spacer()
                Button("取消") { showReview = false }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            if let proposal {
                HStack {
                    Text("\(proposal.suggestions.count) 项已核验 · 已选择 \(selectedSuggestions.count) 项").font(.system(size: 12))
                    if proposal.rejectedCount > 0 { Text("\(proposal.rejectedCount) 项缺少可靠原文，未导入").font(.system(size: 11)).foregroundStyle(.orange) }
                    Spacer()
                    Button("全选") { selectedSuggestions = Set(proposal.suggestions.map(\.id)) }
                    Button("取消全选") { selectedSuggestions = [] }
                }.padding(.horizontal, 24).padding(.vertical, 13)
                Toggle("用所选信息更新已匹配的已有字段", isOn: $replaceExisting).padding(.horizontal, 24).padding(.bottom, 8)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(proposal.suggestions) { suggestion in
                            HStack(alignment: .top, spacing: 10) {
                                Toggle("导入\(suggestion.label)", isOn: Binding(get: { selectedSuggestions.contains(suggestion.id) }, set: { if $0 { selectedSuggestions.insert(suggestion.id) } else { selectedSuggestions.remove(suggestion.id) } })).labelsHidden()
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("\(ApplicationProfileCatalog.section(suggestion.section)?.title ?? suggestion.section) · \(suggestion.label)\(ApplicationProfileCatalog.section(suggestion.section)?.repeated == true ? " · 第\(suggestion.entryIndex + 1)条" : "")")
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                                    Text(suggestion.value).font(.system(size: 13)).textSelection(.enabled)
                                    Text("原文：\(suggestion.quote)").font(.system(size: 11)).foregroundStyle(muted).lineLimit(4)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(15).background(canvas, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 20)
                }
                Divider()
                HStack {
                    Text("缺失信息可随后在各分类中补齐。").font(.system(size: 11)).foregroundStyle(muted)
                    Spacer()
                    Button("确认导入 \(selectedSuggestions.count) 项") {
                        let merged = proposal.merging(into: store.profile, selected: selectedSuggestions, replaceExisting: replaceExisting)
                        store.profile = merged.profile
                        if store.save() {
                            message = "已写入 \(merged.added) 项资料，保留 \(merged.preserved) 项已有内容。请继续核对各类经历和缺失信息。"
                            showReview = false; selectedSection = "basic"
                        }
                    }.buttonStyle(.flowPrimary).disabled(selectedSuggestions.isEmpty)
                }.padding(22)
            }
        }.buttonStyle(.flowSecondary).textFieldStyle(.flow).frame(width: 830, height: 690).tint(accent)
    }
    private func importResume() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["pdf", "doc", "docx", "rtf", "txt", "md"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isReading = true; message = ""
        Task {
            do {
                let text = try await Task.detached(priority: .userInitiated) { try ApplicationResumeParser.extractText(from: url) }.value
                resumeText = text; filename = url.lastPathComponent
                try CandidateMaterials.save(.init(filename: filename, name: store.profile.values["basic.name"] ?? "", text: text)); versions = CandidateMaterials.versions
                message = "已设为默认简历，可直接用于 AI。继续解析并核对，可更新网申档案。"
                let attachment = try ApplicationProfileStorage().importAttachment(from: url, kind: "简历")
                store.profile.attachments.append(attachment); store.profile.defaultResumeAttachmentID = attachment.id; store.profile.resumeFilename = attachment.name
                store.save()
            } catch { message = error.localizedDescription }
            isReading = false
        }
    }
    private func loadExistingResume() {
        guard let resume = LocalAIStorage.read("resume.json", as: ResumeMaterial.self), !resume.text.isEmpty else {
            message = "尚未保存简历，请选择文件或粘贴简历文字。"; return
        }
        resumeText = resume.text; filename = resume.filename; message = "已载入保存的简历，请检查文字后开始解析。"
    }
    private func parseResume() {
        parsingTask?.cancel()
        let generation = UUID(); parsingGeneration = generation
        isParsing = true; message = ""
        let text = resumeText, name = filename.isEmpty ? "粘贴的简历" : filename
        parsingTask = Task {
            do {
                let value = try await ApplicationResumeParser.parse(text: text, filename: name)
                try Task.checkCancellation()
                guard generation == parsingGeneration else { return }
                proposal = value; selectedSuggestions = Set(value.suggestions.map(\.id)); showReview = true
            } catch is CancellationError { }
            catch { if !Task.isCancelled, generation == parsingGeneration { message = error.localizedDescription } }
            if generation == parsingGeneration { isParsing = false }
        }
    }
    private func addAttachments() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !store.profile.attachments.contains(where: { $0.path == url.path }) {
            do { store.profile.attachments.append(try ApplicationProfileStorage().importAttachment(from: url, kind: "其他")) }
            catch { message = "附件导入失败：" + error.localizedDescription }
        }
    }
}
