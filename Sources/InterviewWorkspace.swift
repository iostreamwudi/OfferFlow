import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct InterviewWorkspace: View {
    @EnvironmentObject private var journey: FlowJourney
    @ObservedObject var interviews: InterviewStore
    @ObservedObject var browser: InterviewBrowser
    @ObservedObject var profile: ApplicationProfileStore
    @EnvironmentObject var jobs: Store
    var openProfile: () -> Void
    @State private var detailTab = "practice"
    @State private var showingFilters = false
    @State private var showingBrowser = false
    @StateObject private var viewport = ApplicationViewport(automaticallyFitsWidth: true)
    @Environment(\.isEnabled) private var workspaceEnabled
    @State private var selectedID: String?
    @State private var selectedQuestion = ""
    @State private var projectID = ""
    @State private var webSearch = InterviewSearch()
    @State private var targetScope = false
    @State private var librarySearch = InterviewSearch()
    @State private var editingLabels = false
    @State private var companyLabel = ""
    @State private var roleLabel = ""
    @State private var roundLabel = "不限轮次"
    private var matchingNotes: [InterviewNote] { interviews.library.notes.filter { (!targetScope || $0.relevance(to: interviews.target) != nil) && librarySearch.matches($0) } }
    @State private var targetEditor = false
    @State private var editingTarget = InterviewTarget()
    @State private var importedJob = ""
    @State private var importEditor = false
    @State private var importTitle = ""
    @State private var importURL = ""
    @State private var importText = ""
    @State private var busy = false
    @State private var status = "原面经与个人练习分别保存，所有资料留在本机。"
    @State private var task: Task<Void, Never>?
    @State private var operation = UUID()
    @State private var answer = ""
    @State private var error: String?
    private var note: InterviewNote? { matchingNotes.first { $0.id == selectedID } ?? matchingNotes.first }
    private var projects: [InterviewProject] { InterviewProject.from(profile.profile) }
    private var project: InterviewProject? { projects.first { $0.id == projectID } ?? projects.first }
    private var question: InterviewQuestion? { note?.questions.first { $0.id == selectedQuestion } ?? note?.questions.first }
    private var practice: InterviewPractice? { note?.practices.last { $0.questionID == question?.id && $0.target.id == interviews.target.id && $0.projectID == (question?.answerMode == .direct ? "" : project?.id) } }
    private var answerKey: String { practice?.id ?? "" }

    var body: some View {
        FlowSurface {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                libraryPanel.frame(minWidth: 220, idealWidth: 250, maxWidth: 290)
                if showingBrowser {
                    browserPanel.frame(minWidth: 0, maxWidth: .infinity)
                } else if let note {
                    detailPanel(note).frame(minWidth: 460)
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: "text.book.closed").font(.system(size: 40)).foregroundStyle(accent)
                        Text(interviews.library.notes.isEmpty ? "资料库还没有面经" : librarySearch.isEmpty && targetScope ? "这个岗位还没有相关面经" : "没有符合筛选条件的面经").font(.title2.bold())
                        Text(interviews.library.notes.isEmpty ? "可从小红书、牛客网搜集，或导入已有面经。" : "资料库共保存了 \(interviews.library.notes.count) 篇面经。")
                            .foregroundStyle(.secondary)
                        Button("开始搜集面经", action: search).buttonStyle(.flowPrimary).tint(accent)
                        if !interviews.library.notes.isEmpty { Button("查看全部资料") { targetScope = false; librarySearch = InterviewSearch() } }
                        Button("导入已有面经") { importEditor = true }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if busy || browser.busy || showingBrowser || error != nil || interviews.error != nil || status != "原面经与个人练习分别保存，所有资料留在本机。" {
            Divider()
            HStack(alignment: .top) {
                if busy || browser.busy { ProgressView().controlSize(.small) }
                Text(error ?? interviews.error ?? (showingBrowser ? browser.error : nil) ?? (showingBrowser ? browser.status : status))
                    .font(.callout).foregroundStyle(error != nil || interviews.error != nil || browser.error != nil ? .orange : .secondary)
                    .textSelection(.enabled)
                Spacer()
                if busy || browser.busy { Button("停止") { cancel(); browser.cancel(); status = "操作已停止，已保存内容保留。" } }
            }.padding(12)
            }
        }
        .background(Color.white)
        .sheet(isPresented: $targetEditor) { targetSheet }
        .sheet(isPresented: $importEditor) { importSheet }
        .onChange(of: matchingNotes.map(\.id)) { _, ids in
            if !showingBrowser, !ids.contains(selectedID ?? "") { selectedID = ids.first }
        }
        .onChange(of: showingBrowser) { _, visible in
            if !visible, !matchingNotes.contains(where: { $0.id == selectedID }) { selectedID = matchingNotes.first?.id }
        }
        .onChange(of: selectedID) { _, _ in cancel(); selectedQuestion = ""; answer = "" }
        .onChange(of: selectedQuestion) { _, _ in cancel() }
        .onChange(of: projectID) { _, _ in cancel() }
        .onChange(of: answerKey) { _, _ in answer = practice?.answer ?? "" }
        .onDisappear { cancel(); browser.cancel() }
        .onChange(of: journey.revision) { _, _ in consumeIntent() }
        .onAppear { consumeIntent(); if selectedID == nil { selectedID = matchingNotes.first?.id }; if projectID.isEmpty { projectID = projects.first?.id ?? "" } }
    
        }
    }
    private var header: some View {
        HStack(spacing: 14) {
            Text("面经资料").font(.system(size: 20, weight: .semibold))
            FlowSelect(title: "准备目标", selection: Binding(get: { interviews.target.id }, set: { id in interviews.transaction { $0.targetID = id }; resetForTarget() }), options: interviews.library.targets.map { ($0.id, $0.label.isEmpty ? "未命名目标" : $0.label) }).frame(maxWidth: 270)
            Spacer(minLength: 8)
            FlowActionMenu(title: "面经资料操作", icon: "ellipsis", iconOnly: true, actions: [
                .init(title: "导入面经", icon: "square.and.arrow.down") { importEditor = true },
                .init(title: "个人经历", icon: "person.text.rectangle", run: openProfile),
                .init(title: "编辑准备目标", icon: "pencil") { editingTarget = interviews.target; targetEditor = true },
                .init(title: "新建准备目标", icon: "plus") { editingTarget = InterviewTarget(); targetEditor = true }
            ])
            if showingBrowser {
                Button("返回资料库", systemImage: "books.vertical") { showingBrowser = false }
            } else {
                HStack(spacing: 8) {
                    Text("搜集面经").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(InterviewSource.allCases) { source in
                        Button(source.name) {
                            browser.source = source
                            search()
                        }
                    }
                }.fixedSize()
            }
        }.padding(.horizontal, 22).padding(.vertical, 18)
    }
    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showingBrowser {
                FlowSegments(selection: Binding(get: { browser.source }, set: { source in
                    guard source != browser.source else { return }
                    browser.source = source
                    browser.search(webSearch.webQuery)
                }), options: InterviewSource.allCases.map { ($0, $0.name) })
                Text("搜索结果").font(.headline)
                Button("读取当前列表", action: browser.readList).disabled(browser.busy || browser.loading)
                Text("滚动网页后再次读取，会按笔记去重合并。").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(browser.cards) { card in
                            Button { browser.openCard(card) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(card.title).font(.headline).lineLimit(3)
                                    Text([card.author, card.date].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    Text(interviews.library.notes.contains { $0.id == InterviewRules.noteID(card.url) } ? "已在资料库 · 打开原文" : "打开笔记 →").font(.caption).foregroundStyle(accent)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            } else {
                FlowSegments(selection: Binding(get: { targetScope }, set: { targetScope = $0; librarySearch = InterviewSearch() }),
                             options: [(false, "全部资料"), (true, "当前岗位")])
                HStack(spacing: 8) {
                    TextField("搜索面经", text: $librarySearch.keyword).accessibilityLabel("搜索标题、作者或关键词")
                    Button { showingFilters.toggle() } label: {
                        Image(systemName: "line.3.horizontal.decrease").overlay(alignment: .topTrailing) {
                            if !librarySearch.company.isEmpty || !librarySearch.role.isEmpty { Circle().frame(width: 5, height: 5).offset(x: 5, y: -3) }
                        }
                    }.buttonStyle(.browserToolbar).accessibilityLabel("按公司和岗位筛选")
                        .popover(isPresented: $showingFilters) {
                            FlowSurface {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("筛选面经").font(.headline)
                                    TextField("公司", text: $librarySearch.company)
                                    TextField("岗位", text: $librarySearch.role)
                                    HStack { Button("重置") { librarySearch = InterviewSearch() }; Spacer(); Button("完成") { showingFilters = false }.buttonStyle(.flowPrimary) }
                                }.padding(18).frame(width: 290)
                            }
                        }
                }
                HStack {
                    Text("\(matchingNotes.count) 篇面经").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !librarySearch.isEmpty { Button("清除筛选") { librarySearch = InterviewSearch() }.buttonStyle(.plain).font(.caption) }
                }.padding(.horizontal, 4)
                if !librarySearch.company.isEmpty || !librarySearch.role.isEmpty {
                    Text([librarySearch.company, librarySearch.role].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(.horizontal, 4)
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(matchingNotes) { item in
                            Button { selectedID = item.id } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.title).font(.system(size: 13, weight: selectedID == item.id ? .semibold : .medium)).lineLimit(2)
                                    Text([item.questionSummary, targetScope ? item.relevance(to: interviews.target) ?? "" : item.author].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    if !item.questions.isEmpty && !item.extractionIsCurrent { Text("原文已更新").font(.caption).foregroundStyle(.orange) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(selectedID == item.id ? Color.black.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityAddTraits(selectedID == item.id ? .isSelected : [])
                        }
                    }
                }

            }
        }.padding(14).background(Color(white: 0.985))
    }
    private var browserPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Button { browser.webView.goBack() } label: { Image(systemName: "chevron.left") }
                Button { browser.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                Group {
                    TextField("公司", text: $webSearch.company)
                    TextField("岗位", text: $webSearch.role)
                    TextField("其他关键词", text: $webSearch.keyword)
                }.textFieldStyle(.flow).onSubmit { browser.search(webSearch.webQuery) }
                Button("搜索") { browser.search(webSearch.webQuery) }
                Button("收集并整理问题") {
                    browser.readNote(store: interviews, analyze: true, company: webSearch.company, role: webSearch.role, onReady: { openCollectedQuestions($0) }) { selectedID = $0 }
                }.buttonStyle(.flowPrimary).tint(accent).disabled(browser.busy || browser.loading)
                FlowActionMenu(title: "更多", actions: [
                    .init(title: "仅保存本篇原文", icon: "doc") { browser.readNote(store: interviews, onReady: { openCollectedQuestions($0, sourceOnly: true) }) { selectedID = $0 } },
                    .init(title: "AI 设置", icon: "slider.horizontal.3") { FlowIntent(route: "settings").post() }
                ]).disabled(browser.busy || browser.loading)
            }.padding(.horizontal, 12).padding(.top, 12)
            HStack {
                TextField("粘贴小红书或牛客帖子链接", text: $browser.address).textFieldStyle(.flow).onSubmit { browser.open(browser.address) }
                Button("打开") { browser.open(browser.address) }
                ApplicationViewportTools(viewport: viewport)
            }.padding(.horizontal, 12)
            if browser.loading { ProgressView().progressViewStyle(.linear) }
            VStack(spacing: 0) {
                InterviewWebView(browser: browser)
                ApplicationHorizontalScroll(viewport: viewport)
            }
        }
        .onChange(of: workspaceEnabled, initial: true) { _, active in
            if active { viewport.start(browser.webView) } else { viewport.stop() }
        }
        .onDisappear { viewport.stop() }
    }
    private func detailPanel(_ note: InterviewNote) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(note.title).font(.system(size: 19, weight: .semibold)).textSelection(.enabled).lineLimit(3)
                        Text([note.author, note.dateRaw].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    FlowActionMenu(title: "本篇面经操作", icon: "ellipsis", iconOnly: true, actions: [
                        .init(title: note.preparationTargetIDs?.contains(interviews.target.id) == true ? "取消关联当前准备目标" : "关联当前准备目标", icon: "link") {
                            let targetID = interviews.target.id
                            interviews.update(note.id) { item in
                                var targets = item.preparationTargetIDs ?? []
                                if targets.contains(targetID) { targets.remove(targetID) } else { targets.insert(targetID) }
                                item.preparationTargetIDs = targets
                            }
                        },
                        .init(title: "打开来源", icon: "arrow.up.right", enabled: !note.sourceURL.isEmpty) { browser.open(note.sourceURL); showingBrowser = true },
                        .init(title: note.extractionIsCurrent ? "重新提取问题" : "提取面试问题", icon: "text.magnifyingglass", enabled: !busy && !browser.busy && !note.segments.isEmpty) { extract(note) },
                        .init(title: "补充图片", icon: "photo", enabled: !busy && !browser.busy) { importImages(noteID: note.id) }
                    ])
                }
                HStack(spacing: 8) {
                    let metadata = [note.sourceCompany, note.sourceRole, note.sourceRound].compactMap { $0 }.filter { !$0.isEmpty }
                    Text(metadata.isEmpty ? "公司 / 岗位 / 轮次未标注" : metadata.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Button("标注") {
                        companyLabel = note.sourceCompany ?? ""
                        roleLabel = note.sourceRole ?? ""
                        roundLabel = note.sourceRound ?? "不限轮次"
                        editingLabels = true
                    }.popover(isPresented: $editingLabels) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("面经中的公司", text: $companyLabel)
                            TextField("面经中的岗位", text: $roleLabel)
                            FlowSelect(title: "面试轮次", selection: $roundLabel, options: CoachSources.rounds.map { ($0, $0) })
                            Button("保存标注") {
                                interviews.update(note.id) { item in
                                    item.sourceCompany = companyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                                    item.sourceRole = roleLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                                    item.sourceRound = roundLabel == "不限轮次" ? nil : roundLabel
                                }
                                editingLabels = false
                            }
                        }.padding().frame(width: 260)
                    }
                    .buttonStyle(.plain).font(.caption)
                    Spacer(minLength: 0)
                }
                HStack {
                    FlowSegments(selection: $detailTab, options: [("practice", "问题与练习 · \(note.questions.count)"), ("source", "原始面经")]).frame(width: 265)
                    Spacer()
                    Button("去陪练", systemImage: "bubble.left.and.bubble.right") { FlowIntent(route: "coach", company: note.sourceCompany ?? interviews.target.company, role: note.sourceRole ?? interviews.target.role, round: note.sourceRound).post() }.buttonStyle(.flowSecondary)
                }
            }.padding(22)
            Divider()
            if detailTab == "source" { sourcePanel(note) } else { practicePanel(note) }
        }.background(Color.white)
    }
    private func sourcePanel(_ note: InterviewNote) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if note.questions.isEmpty {
                    HStack {
                        Text(note.questionSummary).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("提取面试问题") { detailTab = "practice"; extract(note) }
                            .disabled(busy || browser.busy || !note.segments.contains { !$0.text.isEmpty })
                    }
                }
                DisclosureGroup("来源与读取情况") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.completeness).font(.caption).foregroundStyle(.secondary)
                        Text(note.category).font(.caption).foregroundStyle(.secondary)
                        if note.aiNotice { Text("来源页面提示：可能含 AI 生成内容。作者经历未经核实。").font(.callout).foregroundStyle(.orange) }
                        if !note.sourceURL.isEmpty { Button("打开来源") { browser.open(note.sourceURL); showingBrowser = true } }
                    }.padding(.top, 8)
                }.font(.callout)
                ForEach(note.segments) { segment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(segment.label).font(.headline)
                        if let file = segment.imageFile, let url = InterviewImages.url(file), let image = NSImage(contentsOf: url) {
                            Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 500)
                            Button("查看完整原图") { NSWorkspace.shared.open(url) }
                            DisclosureGroup("识别文字（请与图片核对）") { Text(segment.text.isEmpty ? "未识别到文字，可导入更清晰的截图。" : segment.text).textSelection(.enabled) }
                        } else { Text(segment.text).textSelection(.enabled) }
                    }
                    Divider()
                }
                if note.segments.isEmpty { Text("这篇资料还没有正文。请打开来源读取，或补充截图。").foregroundStyle(.secondary) }
            }.frame(maxWidth: 760, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }.background(.white)
    }
    private func practicePanel(_ note: InterviewNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !note.questions.isEmpty {
                    FlowSelect(title: "选择原题", selection: Binding(get: { question?.id ?? "" }, set: { selectedQuestion = $0 }), options: note.questions.map { ($0.id, ($0.answerMode?.label ?? "待判断") + " · " + String($0.original.prefix(42))) })
                }
                if let q = question {
                    Text("原题 · " + (note.segments.first { $0.id == q.segmentID }?.label ?? q.segmentID)).font(.caption).foregroundStyle(.secondary)
                    Text(q.original).font(.system(size: 18, weight: .medium)).lineSpacing(5).textSelection(.enabled)
                    HStack {
                        Text(q.category).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("查看原文") { detailTab = "source" }.buttonStyle(.plain).font(.caption)
                    }
                    section("考察意图", text: q.intent)
                    DisclosureGroup("为什么这样判断") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(q.reasoning).textSelection(.enabled)
                            if let reason = q.modeReason { Text(reason).foregroundStyle(.secondary).textSelection(.enabled) }
                        }.font(.callout).padding(.top, 8)
                    }.font(.callout).foregroundStyle(.secondary)
                    let matches = interviews.library.notes.filter { other in other.id != note.id && other.questions.contains { ArkClient.normalized($0.original) == ArkClient.normalized(q.original) } }
                    if !matches.isEmpty { Text("另有 \(matches.count) 篇资料包含相同原题；来源均独立保留。").font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    HStack {
                        Text(q.answerMode?.label ?? "回答方式待判断").font(.headline)
                        Spacer()
                        FlowActionMenu(title: "调整", actions: InterviewAnswerMode.allCases.map { mode in
                            FlowMenuAction(title: mode.label) {
                                cancel()
                                interviews.update(note.id) { value in
                                    guard let i = value.questions.firstIndex(where: { $0.id == q.id }) else { return }
                                    value.questions[i].answerMode = mode
                                    value.questions[i].modeReason = "已按你的选择调整。"
                                    value.questions[i].modeManuallySet = true
                                }
                            }
                        }).fixedSize()
                    }
                    if q.answerMode == nil {
                        Button("判断本篇旧题的回答方式") { classifyExisting(note) }.disabled(busy)
                    } else if q.answerMode == .direct {
                        HStack {
                            if practice == nil {
                                Button("直接写回答") {
                                    let draft = InterviewPractice(questionID: q.id, target: interviews.target, projectID: "", projectName: "直接回答原题", question: q.original, outline: [], followups: [], missing: [], evidence: [], model: "自主练习", sourceFingerprint: note.fingerprint)
                                    interviews.update(note.id) { $0.practices.append(draft) }
                                }
                            }
                            Button("生成原题回答提纲") { adapt(q, note: note) }.disabled(busy || !note.extractionIsCurrent)
                        }
                    } else {
                    FlowSelect(title: "使用我的经历", selection: Binding(get: { project?.id ?? "" }, set: { projectID = $0 }), options: projects.isEmpty ? [("", "尚未导入项目经历")] : projects.map { ($0.id, $0.name) })
                    if projects.isEmpty { Button("到个人资料解析简历或补充项目", action: openProfile) }
                    Text("会将当前原题、目标 JD 和所选项目事实交给已配置的模型生成提纲。").font(.caption).foregroundStyle(.secondary)
                    Button(practice == nil ? "根据我的项目定制" : "重新定制（保留旧版）") { adapt(q, note: note) }
                        .buttonStyle(.flowPrimary).tint(accent).disabled(busy || project == nil || !note.extractionIsCurrent)
                    }
                    if q.answerMode != nil, let p = practice {
                        if p.sourceFingerprint != note.fingerprint || p.target != interviews.target || (q.answerMode == .project && p.projectFingerprint != project.map({ InterviewRules.hash($0.facts.joined(separator: "\n")) })) { Text("来源、目标或项目资料已更新，此练习基于旧资料，可重新生成。").font(.caption).foregroundStyle(.orange) }
                        if q.answerMode == .project { section("定制问题", text: p.question) }
                        if !p.outline.isEmpty { bullets("回答提纲", p.outline) }
                        if !p.followups.isEmpty { bullets("继续追问", p.followups) }
                        if !p.missing.isEmpty { bullets("还需要你补充的事实", p.missing) }
                        if !p.evidence.isEmpty { DisclosureGroup("使用的个人事实") { ForEach(Array(p.evidence.enumerated()), id: \.offset) { _, fact in Text(fact).textSelection(.enabled).padding(.vertical, 4) } } }
                        Text("我的回答").font(.headline)
                        TextEditor(text: $answer).frame(minHeight: 150).flowEditorSurface()
                        HStack {
                            Button("保存我的回答") { interviews.update(note.id) { item in if let i = item.practices.firstIndex(where: { $0.id == p.id }) { item.practices[i].answer = answer } }; status = "回答已保存到当前练习。" }
                            Button("复制练习") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("原题：\(q.original)\n来源：\(note.sourceURL)\n\n练习问题：\(p.question)\n\n" + p.outline.joined(separator: "\n") + "\n\n我的回答：\(answer)", forType: .string) }
                        }
                        Text("\(p.model) · \(p.created.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                    history(note, question: q)
                } else {
                    Button("提取面试问题", systemImage: "sparkles") { extract(note) }.buttonStyle(.flowPrimary).disabled(busy || browser.busy || note.segments.isEmpty)
                    Button("查看已保存原文") { detailTab = "source" }
                    Text(note.questionSummary)
                        .foregroundStyle(.secondary)
                }
            }.frame(maxWidth: 760, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }.background(.white)
    }
    private func section(_ title: String, text: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(text).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading) }
    private func bullets(_ title: String, _ values: [String]) -> some View { VStack(alignment: .leading, spacing: 9) { Text(title).font(.headline); ForEach(Array(values.enumerated()), id: \.offset) { i, value in Text("\(i + 1). \(value)").textSelection(.enabled) } } }
    private func history(_ note: InterviewNote, question: InterviewQuestion) -> some View {
        let versions = note.practices.filter { $0.questionID == question.id }
        return DisclosureGroup("本题的练习版本（\(versions.count)）") {
            ForEach(versions.reversed()) { p in
                VStack(alignment: .leading, spacing: 7) {
                    Text("\(p.target.label) · \(p.projectName)").font(.headline)
                    Text(p.question).textSelection(.enabled)
                    Text(p.answer.isEmpty ? "尚未填写回答" : p.answer).textSelection(.enabled)
                    Text(p.created.formatted()).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
        }
    }
    private var targetSheet: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 16) {
            Text("准备哪个岗位的面试？").font(.title2.bold())
            FlowSelect(title: "从已保存岗位带入", selection: $importedJob, options: [("", "手动填写")] + jobs.jobs.filter { jobs.saved.contains($0.id) && $0.sourceURL != nil }.map { ($0.id, $0.company + " · " + $0.title) }).onChange(of: importedJob) { _, id in if let job = jobs.jobs.first(where: { $0.id == id }) { editingTarget.company = job.company; editingTarget.role = job.title; editingTarget.jd = job.jd } }
            TextField("公司，可不填", text: $editingTarget.company)
            TextField("岗位名称", text: $editingTarget.role)
            Text("岗位 JD（选填）").font(.headline)
            TextEditor(text: $editingTarget.jd).frame(height: 180).flowEditorSurface()
            HStack { Button("取消") { targetEditor = false }; Spacer(); Button("保存目标") { cancel(); interviews.saveTarget(editingTarget); resetForTarget(); targetEditor = false }.buttonStyle(.flowPrimary).disabled(editingTarget.role.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(24).frame(width: 600)
    
        }
    }
    private var importSheet: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 14) {
            Text("导入已有面经").font(.title2.bold())
            Text("粘贴笔记文字，或导入截图后识别。其他网站的资料也可以这样保存。").foregroundStyle(.secondary)
            TextField("标题", text: $importTitle)
            TextField("来源链接（选填）", text: $importURL)
            TextEditor(text: $importText).frame(height: 240).flowEditorSurface()
            HStack {
                Button("取消") { importEditor = false }
                Button("导入图片…") { saveImport(withImages: true) }
                Spacer()
                Button("保存原文") { saveImport(withImages: false) }.buttonStyle(.flowPrimary).disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 640)
    
        }
    }
    private func consumeIntent() {
        guard let request = journey.intent, request.route == "interviews" else { return }
        let job = request.jobID.flatMap { id in jobs.jobs.first { $0.id == id } }
        let company = job?.company ?? request.company ?? ""
        let role = job?.title ?? request.role ?? ""
        journey.intent = nil
        if !company.isEmpty || !role.isEmpty {
            interviews.prepareForApplication(jobID: request.jobID, company: company, role: role, jd: job?.jd)
        }
        resetForTarget()
        targetScope = !company.isEmpty || !role.isEmpty
        librarySearch.keyword = request.keyword ?? ""
    }
    private func resetForTarget() {
        cancel()
        browser.cancel()
        librarySearch = InterviewSearch()
        targetScope = true
        showingBrowser = false
        error = nil
        status = "原面经与个人练习分别保存，所有资料留在本机。"
        detailTab = "practice"
        selectedID = matchingNotes.first(where: { !$0.questions.isEmpty && $0.preparationTargetIDs?.contains(interviews.target.id) == true })?.id
            ?? matchingNotes.first(where: { !$0.questions.isEmpty })?.id ?? matchingNotes.first?.id
    }
    private func openCollectedQuestions(_ id: String, sourceOnly: Bool = false) {
        guard let saved = interviews.library.notes.first(where: { $0.id == id }) else { return }
        if !librarySearch.matches(saved) { librarySearch = InterviewSearch() }
        selectedID = saved.id
        selectedQuestion = saved.questions.first?.id ?? ""
        detailTab = sourceOnly || saved.questions.isEmpty || browser.error != nil ? "source" : "practice"
        error = browser.error.map { "原文已保存。整理问题失败：" + $0 }
        status = saved.questions.isEmpty && !sourceOnly ? saved.questionSummary : browser.status
        showingBrowser = false
    }
    private func search() {
        webSearch = InterviewSearch(company: librarySearch.company.isEmpty ? interviews.target.company : librarySearch.company,
                                    role: librarySearch.role.isEmpty ? interviews.target.role : librarySearch.role, keyword: librarySearch.keyword)
        showingBrowser = true
        browser.search(webSearch.webQuery)
    }
    private func cancel() { operation = UUID(); task?.cancel(); task = nil; busy = false }
    private func extract(_ source: InterviewNote) {
        cancel(); let ticket = operation; busy = true; error = nil; status = "正在提取原题、分类并分析考察意图…"
        task = Task {
            defer { if operation == ticket { busy = false } }
            do {
                let (category, questions, model) = try await InterviewAI.extract(source); try Task.checkCancellation()
                guard operation == ticket, interviews.library.notes.first(where: { $0.id == source.id })?.fingerprint == source.fingerprint else { return }
                interviews.update(source.id) { $0.applyExtraction(questions, category: category, model: model) }
                let count = interviews.library.notes.first { $0.id == source.id }?.questions.count ?? 0
                status = count == 0 ? "原文已保存，本篇未发现明确原题。" : "已整理 \(count) 道有原文依据的问题。"
            } catch is CancellationError {} catch { if operation == ticket { self.error = error.localizedDescription } }
        }
    }
    private func classifyExisting(_ note: InterviewNote) {
        cancel(); let ticket = operation; busy = true; error = nil; status = "正在判断本篇各题的回答方式…"
        task = Task {
            defer { if operation == ticket { busy = false } }
            do {
                let decisions = try await InterviewAI.classifyExisting(note)
                try Task.checkCancellation()
                guard operation == ticket else { return }
                let byID = Dictionary(uniqueKeysWithValues: decisions.map { ($0.id, $0) })
                interviews.update(note.id) { value in
                    for i in value.questions.indices where value.questions[i].answerMode == nil {
                        if let d = byID[value.questions[i].id] {
                            value.questions[i].answerMode = d.answerMode
                            value.questions[i].modeReason = d.modeReason
                        }
                    }
                }
                status = "已补充本篇旧题的回答方式。"
            } catch is CancellationError {} catch { if operation == ticket { self.error = error.localizedDescription } }
        }
    }
    private func adapt(_ question: InterviewQuestion, note: InterviewNote) {
        let selectedProject = project
        cancel(); let ticket = operation; let target = interviews.target; busy = true; error = nil
        status = question.answerMode == .direct ? "正在为原题生成回答提纲…" : "正在根据所选经历定制练习…"
        task = Task {
            defer { if operation == ticket { busy = false } }
            do {
                let result: InterviewPractice
                if question.answerMode == .direct {
                    result = try await InterviewAI.directPractice(question: question, note: note, target: target)
                } else if question.answerMode == .project, let selectedProject {
                    result = try await InterviewAI.adapt(question: question, note: note, target: target, project: selectedProject)
                } else { return }
                try Task.checkCancellation()
                guard operation == ticket else { return }
                interviews.update(note.id) { $0.practices.append(result) }; status = "回答提纲已保存，可以开始练习。"
            } catch is CancellationError {} catch { if operation == ticket { self.error = error.localizedDescription } }
        }
    }
    private func saveImport(withImages: Bool) {
        let id = InterviewRules.noteID(importURL) ?? "import:" + UUID().uuidString
        var value = InterviewNote(id: id, title: importTitle.isEmpty ? "导入面经" : importTitle)
        value.preparationTargetIDs = [interviews.target.id]
        value.sourceURL = InterviewRules.canonical(importURL)
        if !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value.segments = [.init(id: "import-text", label: "用户导入原文", text: importText)] }
        value.completeness = "用户导入内容 · 完整度由你核对"
        interviews.upsert(value); guard interviews.error == nil else { return }; detailTab = "source"; librarySearch = InterviewSearch(); selectedID = id; showingBrowser = false; importEditor = false
        importTitle = ""; importURL = ""; importText = ""
        if withImages { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { importImages(noteID: id) } }
    }
    private func importImages(noteID: String) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]; panel.allowsMultipleSelection = true
        panel.title = "选择面经截图，图片会在本机识别并保存"
        panel.begin { result in
            guard result == .OK else { return }
            cancel(); let ticket = operation; busy = true; error = nil
            let urls = panel.urls
            task = Task {
                defer { if operation == ticket { busy = false } }
                do {
                    for (i, url) in urls.enumerated() {
                        status = "正在识别导入图片 \(i + 1)/\(urls.count)…"
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        guard (attributes[.size] as? Int ?? 0) <= 20_000_000 else { throw AIError.message("单张图片超过 20 MB，请压缩后重试。") }
                        let segment = try await InterviewImages.recognize(Data(contentsOf: url), label: "导入图片 \(i + 1)", id: UUID().uuidString)
                        try Task.checkCancellation(); guard operation == ticket else { return }
                        interviews.update(noteID) { $0.segments.append(segment); $0.completeness = "已补充截图 · OCR 文字请与原图核对" }
                    }
                    status = "图片和识别文字已保存，提取前请核对。"
                } catch is CancellationError {} catch { if operation == ticket { self.error = error.localizedDescription } }
            }
        }
    }
}
