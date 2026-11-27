import SwiftUI
import AppKit

let accent = Color(white: 0.12)
let ink = Color(white: 0.15)
let muted = Color(white: 0.48)
let canvas = Color(white: 0.975)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main struct CareerAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup("OfferFlow") {
            DesktopWorkspace().environmentObject(store).frame(minWidth: 1120, minHeight: 740)
                .preferredColorScheme(.light).tint(accent)
                .font(.system(size: 13)).buttonStyle(.flowSecondary).textFieldStyle(.flow)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1380, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("快速查找…") {
                    NotificationCenter.default.post(name: .careerWorkspaceCommand, object: nil, userInfo: ["action": "quickSearch"])
                }.keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("展开或收起侧边栏") {
                    NotificationCenter.default.post(name: .careerWorkspaceCommand, object: nil, userInfo: ["action": "toggleSidebar"])
                }.keyboardShortcut("\\", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    NotificationCenter.default.post(name: .careerWorkspaceCommand, object: nil, userInfo: ["action": "settings"])
                }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

struct Workspace: View {
    @EnvironmentObject var store: Store
    @State private var search = ""
    @State private var city = "全部城市"
    @State private var scope = "全部岗位"
    @State private var sort = "匹配优先"
    @State private var importing = false
    @State private var editingProfile = false
    @State private var bossSearching = false
    @State private var managing = false
    @StateObject private var boss: BossSession
    let showsSidebar: Bool
    var onModeChange: ((Bool) -> Void)?
    var onOpenBoss: (() -> Void)?
    let initiallyManaging: Bool
    init(boss: BossSession, showsSidebar: Bool = true, initiallyManaging: Bool = false, onModeChange: ((Bool) -> Void)? = nil, onOpenBoss: (() -> Void)? = nil) {
        _boss = StateObject(wrappedValue: boss)
        self.showsSidebar = showsSidebar
        self.onModeChange = onModeChange
        self.onOpenBoss = onOpenBoss
        self.initiallyManaging = initiallyManaging
        _managing = State(initialValue: initiallyManaging)
    }
    var filtered: [Job] {
        let result = store.jobs.filter { job in
            (search.isEmpty || "\(job.title) \(job.company) \(job.jd)".localizedCaseInsensitiveContains(search)) &&
            (city == "全部城市" || job.city == city) &&
            (scope != "我的收藏" || store.saved.contains(job.id)) &&
            (scope != "投递清单" || store.pipeline.contains(job.id))
        }
        if sort == "最近导入" { return result.sorted { $0.created > $1.created } }
        return result.sorted { (store.matchReport(for: $0).score ?? -1) > (store.matchReport(for: $1).score ?? -1) }
    }
    var body: some View {
        HStack(spacing: 0) {
            if showsSidebar {
                sidebar
                Divider()
            }
            VStack(spacing: 0) {
                header
                Divider()
                if managing {
                    ApplicationManager(openChat: { job in
                        boss.attach(store); openBossSearch(); boss.openTrackedConversation(job)
                    })
                } else {
                let visibleJobs = filtered
                let currentJob = visibleJobs.first { $0.id == store.selected } ?? visibleJobs.first
                HSplitView {
                    jobList(visibleJobs, selectedID: currentJob?.id).frame(minWidth: 340, idealWidth: 425, maxWidth: 510)
                    Group {
                        if let job = currentJob { JobDetail(job: job).id(job.id) }
                        else { emptyDetail }
                    }.frame(minWidth: 490, maxWidth: .infinity, maxHeight: .infinity)
                }
                }
            }
        }
        .foregroundStyle(ink).background(.white)
        .sheet(isPresented: $importing) { ImportSheet().environmentObject(store) }
        .sheet(isPresented: $editingProfile) { ProfileSheet().environmentObject(store) }
        .sheet(isPresented: $bossSearching) { BossSearchSheet(session: boss).environmentObject(store) }
        .onAppear {
            boss.attach(store)
            if store.profile.name == "体验用户", let resume = LocalAIStorage.read("resume.json", as: ResumeMaterial.self) {
                store.applyResume(name: resume.name, text: ArkClient.outboundResume(resume.text))
            }
        }
        .onChange(of: store.bossImportRevision) { _, _ in
            managing = false; scope = "全部岗位"; search = ""; city = "全部城市"; sort = "最近导入"
        }
        .onChange(of: store.selected) { _, _ in
            if store.preferredDetailTab == "匹配分析" { scope = "全部岗位"; search = ""; city = "全部城市" }
        }
        .onChange(of: store.jobs.count) { old, new in
            if new > old { scope = "全部岗位"; search = ""; city = "全部城市"; sort = "最近导入" }
        }
        .onChange(of: managing) { _, value in
            if let onModeChange, value != initiallyManaging {
                onModeChange(value)
                managing = initiallyManaging
            }
        }
        .alert("本地存储提示", isPresented: Binding(get: { !store.notice.isEmpty }, set: { if !$0 { store.notice = "" } })) {
            Button("知道了") { store.notice = "" }
        } message: { Text(store.notice) }
    }
    private func openBossSearch() {
        if let onOpenBoss { onOpenBoss() } else { bossSearching = true }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.square.fill").font(.system(size: 29)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OfferFlow").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("你的下一站，从这里开始").font(.system(size: 10)).foregroundStyle(muted)
                }
            }.padding(.top, 46).padding(.bottom, 36).padding(.horizontal, 22)
            Text("求职工作台").font(.system(size: 11, weight: .medium)).foregroundStyle(muted).padding(.horizontal, 24).padding(.bottom, 12)
            navItem("岗位发现", "sparkle.magnifyingglass", active: true)
            navItem("简历中心", "doc.text", active: false)
            navItem("AI 面试教练", "waveform", active: false)
            navItem("求职管理", "square.stack.3d.up", active: true)
            Divider().padding(22)
            Text("我的机会").font(.system(size: 11, weight: .medium)).foregroundStyle(muted).padding(.horizontal, 24).padding(.bottom, 10)
            collection("我的收藏", "bookmark", store.saved.count)
            collection("投递清单", "tray", store.pipeline.count)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: "person.crop.square"); Text("个人经历档案").fontWeight(.semibold) }.font(.system(size: 12))
                Text("补充真实经历，让岗位分析更贴近你。").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4)
                Button("编辑我的档案", systemImage: "pencil") { editingProfile = true }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
            }.padding(16).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12)).padding(16)
            HStack(spacing: 10) {
                Text(String(store.profile.name.prefix(1))).font(.system(size: 13, weight: .semibold)).frame(width: 32, height: 32).background(accent.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 3) { Text(store.profile.name.isEmpty ? "我的档案" : store.profile.name).font(.system(size: 12, weight: .medium)); Text("本地体验版").font(.system(size: 10)).foregroundStyle(muted) }
                Spacer()
                Button { editingProfile = true } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.plain).help("编辑个人档案")
            }.padding(20)
        }.frame(width: 210).background(canvas)
    }
    func navItem(_ title: String, _ icon: String, active: Bool) -> some View {
        let isSelected = active && (managing ? title == "求职管理" : title == "岗位发现")
        return Button { managing = title == "求职管理"; scope = "全部岗位" } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 20)
                Text(title).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
                if !active { Text("稍后").font(.system(size: 9)).foregroundStyle(muted) }
            }.padding(.horizontal, 14).padding(.vertical, 12)
                .foregroundStyle(isSelected ? accent : muted)
                .background(isSelected ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(!active).help(active ? "查看全部岗位" : "后续版本开放，当前先体验岗位发现").padding(.horizontal, 12).padding(.bottom, 4)
    }
    func collection(_ title: String, _ icon: String, _ count: Int) -> some View {
        Button { managing = false; scope = scope == title ? "全部岗位" : title } label: {
            HStack { Image(systemName: icon).frame(width: 20); Text(title); Spacer(); Text("\(count)").font(.system(size: 11)).monospacedDigit() }
                .font(.system(size: 12)).padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(scope == title ? accent : muted)
                .background(scope == title ? accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).padding(.horizontal, 12)
    }
    var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(managing ? "投递管理" : "已保存岗位").font(.system(size: 25, weight: .bold))
                Text(managing ? "生成、填入、发送分别记录；继续跟进每个目标岗位。" : "目标方向：\(store.profile.target.isEmpty ? "待设置" : store.profile.target) · 找到值得投递的机会。").font(.system(size: 12)).foregroundStyle(muted)
            }
            Spacer()
            Button { openBossSearch() } label: { Label("搜索 BOSS 岗位", systemImage: "magnifyingglass").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 11).foregroundStyle(accent).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
            Button { importing = true } label: { Label("导入岗位 JD", systemImage: "plus").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 11).foregroundStyle(.white).background(accent, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).keyboardShortcut("i", modifiers: .command)
        }.padding(.horizontal, 28).padding(.top, 38).padding(.bottom, 24)
    }
    private func jobList(_ filtered: [Job], selectedID: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(muted)
                TextField("搜索岗位、公司或技能", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(muted) }.buttonStyle(.plain).help("清除搜索") }
            }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.07))).padding(.horizontal, 20).padding(.top, 20)
            HStack {
                FlowSelect(title: "城市", selection: $city, options: [("全部城市","全部城市")] + Array(Set(store.jobs.map(\.city))).sorted().map { ($0,$0) }).labelsHidden().frame(width: 110)
                Spacer()
                FlowSelect(title: "排序", selection: $sort, options: [("匹配优先","匹配优先"),("最近导入","最近导入")]).labelsHidden().frame(width: 110)
            }.padding(.horizontal, 16).padding(.vertical, 14)
            HStack { Text(scope).fontWeight(.semibold); Text("\(filtered.count)").foregroundStyle(muted); Spacer(); if scope != "全部岗位" || !search.isEmpty || city != "全部城市" { Button("重置") { search = ""; city = "全部城市"; scope = "全部岗位" }.buttonStyle(.plain).foregroundStyle(accent) } }.font(.system(size: 11)).padding(.horizontal, 22).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 10) {
                    if filtered.isEmpty {
                        VStack(spacing: 14) { Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(muted); Text("暂时没有符合条件的岗位").font(.system(size: 13, weight: .medium)); Text("调整筛选条件，或导入一份新的 JD。").font(.system(size: 11)).foregroundStyle(muted) }.frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(filtered) { job in
                        JobCard(job: job, selected: selectedID == job.id) { store.selected = job.id }
                    }
                }.padding(.horizontal, 18).padding(.bottom, 20)
            }
            HStack(spacing: 6) { Image(systemName: "info.circle"); Text("内置公司和职位均为虚构示例") }.font(.system(size: 10)).foregroundStyle(muted).padding(16).frame(maxWidth: .infinity)
        }.background(canvas.opacity(0.65))
    }
    var emptyDetail: some View {
        VStack(spacing: 16) { Image(systemName: "rectangle.and.text.magnifyingglass").font(.system(size: 40)).foregroundStyle(accent.opacity(0.5)); Text("下一份机会，等你发现").font(.title3.bold()); Text("从左侧选择岗位，或导入自己的目标职位。").foregroundStyle(muted) }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct JobCard: View {
    @EnvironmentObject var store: Store
    var job: Job
    var selected: Bool
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(job.initial).font(.system(size: 17, weight: .semibold)).foregroundStyle(job.color).frame(width: 38, height: 38).background(job.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) { Text(job.title).font(.system(size: 14, weight: .semibold)).lineLimit(1); Text(job.company).font(.system(size: 11)).foregroundStyle(muted) }
                Spacer(minLength: 0)
                Button { store.toggleSaved(job.id) } label: { Image(systemName: store.saved.contains(job.id) ? "bookmark.fill" : "bookmark").foregroundStyle(store.saved.contains(job.id) ? accent : muted).padding(6) }.buttonStyle(.plain).help(store.saved.contains(job.id) ? "取消收藏" : "收藏岗位")
            }
            HStack { Text(job.salary).font(.system(size: 13, weight: .semibold)).foregroundStyle(accent); Spacer(); Text(job.city).font(.system(size: 11)).foregroundStyle(muted) }
            HStack(spacing: 5) { ForEach(job.tags.prefix(3), id: \.self) { tag in Tag(text: tag) }; Spacer(minLength: 0) }
            HStack {
                if let score = store.matchReport(for: job).score { Text("关键词覆盖 \(score)%").foregroundStyle(accent) } else { Text("待补充分析").foregroundStyle(muted) }
                Spacer()
                Text(store.pipeline.contains(job.id) ? "已加入清单" : job.source).foregroundStyle(muted)
            }.font(.system(size: 10))
        }.padding(16).background(selected ? Color.white : Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? accent.opacity(0.65) : .black.opacity(0.06), lineWidth: selected ? 1.3 : 1))
            .contentShape(Rectangle()).onTapGesture(perform: action)
            .accessibilityElement(children: .contain).accessibilityLabel(job.title + " " + job.company)
    }
}

struct Tag: View {
    var text: String
    var body: some View { Text(text).font(.system(size: 10)).foregroundStyle(muted).padding(.horizontal, 7).padding(.vertical, 4).background(canvas, in: RoundedRectangle(cornerRadius: 4)) }
}

struct JobDetail: View {
    @EnvironmentObject var store: Store
    var job: Job
    var returnToApplication: (() -> Void)? = nil
    @State private var tab = "岗位详情"
    @State private var draft = ""
    @State private var copied = false
    var report: MatchReport { store.matchReport(for: job) }
    var body: some View {
        VStack(spacing: 0) {
            if let returnToApplication {
                HStack {
                    Button("返回投递记录", systemImage: "chevron.left", action: returnToApplication)
                    Spacer()
                }.padding(.horizontal, 28).padding(.top, 16)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack { Label(job.source, systemImage: job.source == "手动导入" ? "square.and.arrow.down" : "square.grid.2x2").font(.system(size: 10)).foregroundStyle(muted); Spacer(); Text("仅保存在本机").font(.system(size: 10)).foregroundStyle(muted) }
                    HStack(alignment: .top, spacing: 14) {
                        Text(job.initial).font(.system(size: 25, weight: .semibold)).foregroundStyle(job.color).frame(width: 58, height: 58).background(job.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 8) { Text(job.title).font(.system(size: 25, weight: .bold)); Text([job.company, job.city, job.experience].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(muted) }
                        Spacer(minLength: 0)
                    }
                    if !job.salary.isEmpty { Text(job.salary).font(.system(size: 20, weight: .semibold)).foregroundStyle(accent) }
                    if !job.tags.isEmpty { HStack(spacing: 6) { ForEach(job.tags, id: \.self) { Tag(text: $0) } } }
                    if job.isWebApplication {
                        webApplicationContent
                    } else {
                        standardDetail
                    }
                }.padding(28)
            }
            Divider()
            HStack(spacing: 10) {
                Button { store.toggleSaved(job.id) } label: { Label(store.saved.contains(job.id) ? "已收藏" : "收藏", systemImage: store.saved.contains(job.id) ? "bookmark.fill" : "bookmark").padding(.horizontal, 14).padding(.vertical, 11).background(canvas, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                Spacer()
                Button { store.togglePipeline(job.id) } label: { Label(store.pipeline.contains(job.id) ? "已加入投递清单" : "加入投递清单", systemImage: store.pipeline.contains(job.id) ? "checkmark" : "plus").padding(.horizontal, 16).padding(.vertical, 11).foregroundStyle(.white).background(accent, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 28).padding(.vertical, 16)
            Text("清单用于本地记录，不会向招聘平台发送或投递。").font(.system(size: 9)).foregroundStyle(muted).padding(.bottom, 10)
        }.background(.white)
        .onAppear {
            if returnToApplication == nil { tab = store.preferredDetailTab; store.preferredDetailTab = "岗位详情" }
        }
        .onChange(of: job.fetchedAt) { _, _ in tab = "匹配分析" }
        .onChange(of: store.preferredDetailTab) { _, value in
            if returnToApplication == nil, value == "匹配分析" { tab = value; store.preferredDetailTab = "岗位详情" }
        }
    }
    @ViewBuilder private var webApplicationContent: some View {
        if let record = store.applications[job.id] {
            VStack(alignment: .leading, spacing: 10) {
                Text("投递进展").font(.headline)
                Text(record.stage.label)
                if let status = record.formState, !status.isEmpty { Text(status).foregroundStyle(muted) }
                if let version = record.resumeVersion, !version.isEmpty { Text("本次资料：" + version).foregroundStyle(muted) }
            }
        }
        if let raw = job.sourceURL, let url = LiveJobListing.safeHTTPURL(raw) {
            Link("查看网申页面 ↗", destination: url)
        }
        if !job.jd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("职位描述").font(.headline)
            Text(job.jd).lineSpacing(6).textSelection(.enabled)
        }
    }
    @ViewBuilder private var standardDetail: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Label("与你的经历有哪些关联？", systemImage: "sparkles").font(.system(size: 12, weight: .semibold)); Spacer(); Text("规则演示").font(.system(size: 9)).foregroundStyle(muted) }
            Text(report.matched.isEmpty ? "当前档案尚未找到明确的关键词关联。可以补充经历，再判断是否值得投递。" : "你的档案提及\(report.matched.prefix(3).joined(separator: "、"))，与这份 JD 存在关键词关联，建议进一步核实实践深度。")
                .font(.system(size: 12)).lineSpacing(5).foregroundStyle(accent)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        HStack(spacing: 26) {
            ForEach(["岗位详情", "匹配分析", "打招呼"], id: \.self) { title in
                Button { tab = title; if title == "打招呼" && draft.isEmpty { draft = Analysis.greeting(job, store.profile) } } label: {
                    VStack(spacing: 12) { Text(title).font(.system(size: 12, weight: tab == title ? .semibold : .regular)); Rectangle().fill(tab == title ? accent : .clear).frame(height: 2) }.foregroundStyle(tab == title ? accent : muted)
                }.buttonStyle(.plain)
            }
            Spacer()
        }.overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.06)).frame(height: 1) }
        if tab == "岗位详情" { jdContent }
        if tab == "匹配分析" { matchContent }
        if tab == "打招呼" { greetingContent }
    }
    var jdContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let raw = job.sourceURL, let url = URL(string: raw) {
                HStack { Link("查看 BOSS 原岗位 ↗", destination: url).foregroundStyle(accent); Spacer(); if let date = job.fetchedAt { Text("读取于 \(date.formatted(date: .numeric, time: .shortened))").foregroundStyle(muted) } }.font(.system(size: 10))
            }
            Text("职位描述").font(.system(size: 15, weight: .semibold))
            Text(job.jd).font(.system(size: 12)).lineSpacing(8).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    var matchContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.score.map { "\($0)%" } ?? "—").font(.system(size: 38, weight: .semibold, design: .rounded)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) { Text("JD 关键词覆盖").font(.system(size: 12, weight: .semibold)); Text("\(report.matched.count) / \(report.requirements.count) 个已识别关键词").font(.system(size: 10)).foregroundStyle(muted) }
            }
            Text("按 JD 与个人经历中的关键词交集计算，不代表能力评分或录用概率；未提及不等于不具备。").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(5)
            Text("已找到的经历依据").font(.system(size: 13, weight: .semibold))
            if report.matched.isEmpty { Text("暂无依据，请补充个人经历。").font(.system(size: 12)).foregroundStyle(muted) }
            ForEach(report.matched, id: \.self) { word in
                VStack(alignment: .leading, spacing: 6) {
                    Label(word, systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                    Text("档案原文：\(Analysis.evidence(store.profile, keyword: word))").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4).textSelection(.enabled)
                }
            }
            Divider()
            Text("需要补充确认").font(.system(size: 13, weight: .semibold))
            Text(report.missing.isEmpty ? (report.requirements.isEmpty ? "未识别到内置词表中的关键词，请人工阅读 JD。" : "已识别关键词都有提及，仍需核实实际经验与岗位要求。") : report.missing.joined(separator: "、") + "：个人档案中未找到明确提及，建议补充真实经历或提前准备。")
                .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5)
        }
    }
    var greetingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("给 HR 的第一句话").font(.system(size: 15, weight: .semibold)); Spacer(); Button("重新生成") { draft = Analysis.greeting(job, store.profile); copied = false }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 11)) }
            Text("本地模板根据当前 JD 和档案生成，编辑后可复制使用。").font(.system(size: 11)).foregroundStyle(muted)
            TextEditor(text: $draft).font(.system(size: 13)).lineSpacing(7).scrollContentBackground(.hidden).padding(12).frame(height: 200).background(canvas, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(.black.opacity(0.08)))
                .accessibilityLabel("打招呼语").onChange(of: draft) { _, _ in copied = false }
            HStack {
                Text("\(draft.count) 字").font(.system(size: 10)).foregroundStyle(muted)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft, forType: .string); copied = true } label: { Label(copied ? "已复制" : "复制打招呼语", systemImage: copied ? "checkmark" : "doc.on.doc") }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("请核对项目、职责与成果后再发送。当前版本支持 BOSS 页面读取，不会自动发送消息。").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(5)
        }
    }
}

struct ProfileSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var profile = Profile()
    var body: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 18) {
            Text("让岗位发现更了解你").font(.system(size: 23, weight: .bold))
            Text("以下为体验档案，可替换为你自己的真实经历。内容仅保存在本机。").font(.system(size: 12)).foregroundStyle(muted)
            TextField("称呼", text: $profile.name).textFieldStyle(.flow)
            TextField("目标岗位", text: $profile.target).textFieldStyle(.flow)
            Text("项目与工作经历").font(.system(size: 13, weight: .semibold))
            TextEditor(text: $profile.experience).font(.system(size: 13)).padding(8).frame(height: 190).overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3))).accessibilityLabel("项目与工作经历")
            Text("建议写明：项目背景、你做了什么、使用的技术和可核实的结果。保存后会重新计算岗位关键词覆盖。").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4)
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存档案") { store.profile = profile; store.persist(); dismiss() }.buttonStyle(.flowPrimary).disabled(profile.experience.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 550).onAppear { profile = store.profile }
    
        }
    }
}

struct ImportSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var company = ""
    @State private var city = "上海"
    @State private var salary = ""
    @State private var jd = ""
    var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !jd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 18) {
            Label("把机会带进工作台", systemImage: "square.and.arrow.down").font(.system(size: 23, weight: .bold))
            Text("粘贴职位描述，保存后即可查看关键词关联和生成打招呼语。").font(.system(size: 12)).foregroundStyle(muted)
            HStack { TextField("岗位名称（必填）", text: $title); TextField("公司名称（必填）", text: $company) }.textFieldStyle(.flow)
            HStack { TextField("城市（必填）", text: $city); TextField("薪资，例如 20–30K", text: $salary) }.textFieldStyle(.flow)
            Text("职位描述 JD（必填）").font(.system(size: 13, weight: .semibold))
            TextEditor(text: $jd).font(.system(size: 13)).padding(8).frame(height: 230).overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3))).accessibilityLabel("职位描述 JD")
            HStack { Text("当前支持文本导入，链接抓取后续接入。").font(.system(size: 11)).foregroundStyle(muted); Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("导入并分析") {
                let tags = Analysis.vocabulary.filter { Analysis.contains(jd, $0) }
                store.add(Job(title: title.trimmingCharacters(in: .whitespacesAndNewlines), company: company.trimmingCharacters(in: .whitespacesAndNewlines), city: city.trimmingCharacters(in: .whitespacesAndNewlines), salary: salary.isEmpty ? "薪资面议" : salary, experience: "以 JD 为准", tags: tags, jd: jd, source: "手动导入", colorIndex: store.jobs.count))
                dismiss()
            }.buttonStyle(.flowPrimary).disabled(!valid).keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 640)
    
        }
    }
}
