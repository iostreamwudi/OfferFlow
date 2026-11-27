import SwiftUI

struct ApplicationManager: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var journey: FlowJourney
    let openChat: (Job) -> Void
    @State private var selected: String?
    @State private var filter = "全部进展"
    @State private var search = ""
    @State private var registering = false
    @State private var showTransfer = false
    @State private var transferJobIDs = Set<String>()
    @State private var newCompany = ""
    @State private var newTitle = ""
    @State private var newStage: ApplicationStage = .submitted
    @State private var registerError = ""
    var entries: [(Job, ApplicationRecord)] {
        store.jobs.compactMap { job in
            guard let record = store.applications[job.id],
                  search.split(whereSeparator: { $0.isWhitespace }).allSatisfy({ "\(job.title) \(job.company)".localizedCaseInsensitiveContains(String($0)) }),
                  filter == "全部进展" || (filter == "待跟进" ? (record.isOpen && record.followUpAt.map { $0 < Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400) } == true) : (record.stage.label == filter || filter == "阶段 · " + record.stage.group || (filter == "已结束的申请" && !record.isOpen))) else { return nil }
            return (job, record)
        }.sorted { $0.1.updatedAt > $1.1.updatedAt }
    }
    var body: some View {
        FlowSurface {
        let visible = entries
        HSplitView {
            VStack(spacing: 12) {
                TextField("搜索岗位或公司", text: $search).textFieldStyle(.flow)
                HStack {
                    FlowSelect(title: "筛选投递进展", selection: $filter, options: ["全部进展", "待跟进", "已结束的申请"].map { ($0,$0) } + ApplicationStage.groups.map { ("阶段 · " + $0.name, "全部 · " + $0.name) } + ApplicationStage.allCases.map { ($0.label,$0.label) })
                    Button("登记投递", systemImage: "plus") {
                        newCompany = ""; newTitle = ""; newStage = .submitted; registerError = ""; registering = true
                    }
                }
                Button("导入 / 导出当前筛选", systemImage: "arrow.up.arrow.down") {
                    transferJobIDs = Set(visible.map { $0.0.id }); showTransfer = true
                }
                Text("\(visible.count) 个岗位").font(.caption).foregroundStyle(muted)
                List(selection: $selected) {
                    ForEach(visible.map(\.0)) { job in
                        if let record = store.applications[job.id] {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(job.title).font(.headline)
                                Text(job.company).foregroundStyle(muted)
                                HStack {
                                    Text(record.stage.label).foregroundStyle(accent)
                                    Text(job.source).font(.caption).foregroundStyle(muted)
                                }
                                if let date = record.followUpAt, record.isOpen { Text("跟进：\(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(muted) }
                            }.padding(.vertical, 7).tag(job.id)
                        }
                    }
                }.listStyle(.inset)
            }.padding(16).frame(minWidth: 290, idealWidth: 340, maxWidth: 420)
            Group {
                if let (job, record) = visible.first(where: { $0.0.id == selected }) ?? visible.first {
                    ApplicationEditor(job: job, record: record, openChat: openChat).id(job.id)
                } else {
                    VStack(spacing: 14) {
                        Text("暂无对应的求职记录").font(.title3.bold())
                        Text("生成打招呼语、填入聊天框或加入投递清单后，岗位会出现在这里。").foregroundStyle(muted).multilineTextAlignment(.center)
                    }.padding(35).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if let id = store.selected { selected = id } }
        .onChange(of: journey.revision) { _, _ in if journey.intent?.route == "applications", let id = journey.intent?.jobID { search = ""; filter = "全部进展"; selected = id } }
        .sheet(isPresented: $showTransfer) { ApplicationTransferView(store: store, jobIDs: transferJobIDs) }
        .sheet(isPresented: $registering) {
            VStack(alignment: .leading, spacing: 16) {
                Text("登记岗位投递").font(.title2.bold())
                TextField("公司名称", text: $newCompany)
                TextField("岗位名称", text: $newTitle)
                StageMenu(stage: newStage) { newStage = $0 }
                Text("已有同公司、同岗位的记录会直接打开。").font(.caption).foregroundStyle(.secondary)
                if !registerError.isEmpty { Text(registerError).foregroundStyle(.orange) }
                HStack {
                    Button("取消") { registering = false }
                    Spacer()
                    Button("登记并查看") {
                        if let id = store.registerApplication(company: newCompany, title: newTitle, stage: newStage) {
                            search = ""; filter = "全部进展"; selected = id; registering = false
                        } else { registerError = store.notice }
                    }.buttonStyle(.flowPrimary)
                     .disabled([newCompany, newTitle].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
            }.buttonStyle(.flowSecondary).textFieldStyle(.flow).padding(24).frame(width: 440)
        }
    
        }
    }
}

private struct StageMenu: View {
    let stage: ApplicationStage
    let choose: (ApplicationStage) -> Void
    var body: some View {
        HStack {
            Text("当前进展")
            FlowSelect(title: "当前进展", selection: Binding(get: { stage }, set: choose), options: ApplicationStage.allCases.map { ($0, $0.label) }).frame(maxWidth: 230)
        }
    }
}

struct ApplicationEditor: View {
    @EnvironmentObject var store: Store
    let job: Job
    let record: ApplicationRecord
    let openChat: (Job) -> Void
    @State private var showingDetails = false
    @State private var stage: ApplicationStage
    @State private var notes: String
    @State private var followUp: Bool
    @State private var date: Date
    @State private var feedback = ""
    @State private var dirty = false
    @State private var stageEdited = false
    @State private var editIdentity = false
    @State private var editCompany = ""
    @State private var editRole = ""
    init(job: Job, record: ApplicationRecord, openChat: @escaping (Job) -> Void) {
        self.job = job; self.record = record; self.openChat = openChat
        _stage = State(initialValue: record.stage); _notes = State(initialValue: record.notes)
        _followUp = State(initialValue: record.followUpAt != nil)
        _date = State(initialValue: record.followUpAt ?? Calendar.current.date(byAdding: .day, value: 3, to: Date())!)
    }
    var latest: ApplicationRecord { store.applications[job.id] ?? record }
    var body: some View {
        if showingDetails {
            JobDetail(job: job, returnToApplication: { showingDetails = false })
        } else {
            editor
        }
    }
    private var editor: some View {
        FlowSurface {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(job.title).font(.system(size: 24, weight: .bold))
                Text([job.company, job.city, job.salary].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(muted)
                HStack {
                    Button("岗位详情") { if saveIfNeeded() { showingDetails = true } }
                    if job.source != "BOSS直聘" { Button("修改公司与岗位") { editCompany = job.company; editRole = job.title; editIdentity = true } }
                    if job.isWebApplication, job.sourceURL != nil {
                        Button("继续网申") { if saveIfNeeded() { FlowIntent(route: "application", jobID: job.id).post() } }.buttonStyle(.flowPrimary)
                    } else if job.sourceURL.flatMap(BossSite.canonical) != nil {
                        Button("打开 BOSS 聊天") { if saveIfNeeded() { openChat(job) } }.buttonStyle(.flowPrimary)
                    }
                }
                HStack {
                    Button("搜集面经") { if saveIfNeeded() { FlowIntent(route: "interviews", jobID: job.id, company: job.company, role: job.title).post() } }
                    Button("准备面试") { if saveIfNeeded() { FlowIntent(route: "coach", jobID: job.id, company: job.company, role: job.title).post() } }
                    Button("安排日程") { if saveIfNeeded() { FlowIntent(route: "calendar", jobID: job.id, company: job.company, role: job.title, title: job.company + " · 面试").post() } }
                }
                if let state = latest.formState { Text(state).font(.callout).foregroundStyle(.secondary) }
                if let version = latest.resumeVersion { Text("本次资料：" + version).font(.caption).foregroundStyle(.secondary) }
                Divider()
                StageMenu(stage: stage) { stage = $0; stageEdited = true; dirty = true }
                Toggle("设置下次跟进日期", isOn: $followUp)
                if followUp { DatePicker("下次跟进", selection: $date, displayedComponents: [.date, .hourAndMinute]).frame(maxWidth: 360) }
                Text("自动同步到求职日历，可在那里调整提醒。").font(.system(size: 11)).foregroundStyle(muted)
                Text("沟通备注 / 回复内容 / 面试安排").font(.headline)
                TextEditor(text: $notes).frame(minHeight: 150).flowEditorSurface().accessibilityLabel("求职跟进备注")
                HStack {
                    Button("保存进展") { _ = saveIfNeeded(force: true) }.buttonStyle(.flowPrimary)
                    Text(!store.notice.isEmpty && dirty ? store.notice : dirty ? "有待保存的修改，离开时自动保存" : feedback).font(.system(size: 11)).foregroundStyle(muted)
                }
                Divider()
                Text("进度时间线").font(.headline)
                ForEach(latest.timeline.reversed()) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(event.stage.label).bold()
                            Spacer()
                            Text(event.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(muted)
                        }
                        if !event.note.isEmpty { Text(event.note).textSelection(.enabled) }
                    }.font(.callout)
                }
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $editIdentity) {
            VStack(alignment: .leading, spacing: 18) {
                Text("修改申请关联").font(.title2.bold())
                TextField("公司", text: $editCompany).textFieldStyle(.flow)
                TextField("岗位", text: $editRole).textFieldStyle(.flow)
                if !store.notice.isEmpty { Text(store.notice).font(.caption).foregroundStyle(.orange) }
                HStack { Button("取消") { editIdentity = false }; Spacer(); Button("保存") { if saveIfNeeded(), store.renameApplication(job.id, company: editCompany, role: editRole) { editIdentity = false } }.buttonStyle(.flowPrimary) }
            }.buttonStyle(.flowSecondary).textFieldStyle(.flow).padding(24).frame(width: 460)
        }
        .onChange(of: notes) { _, _ in dirty = true }
        .onChange(of: followUp) { _, _ in dirty = true }
        .onChange(of: date) { _, _ in dirty = true }
        .onChange(of: latest.stage) { _, new in if !stageEdited { stage = new } }
        .onChange(of: latest.followUpAt) { _, new in if !dirty { followUp = new != nil; if let new { date = new } } }
        .onDisappear { _ = saveIfNeeded() }
    
        }
    }
    func stamp(_ title: String, _ date: Date) -> some View { Text("\(title)：\(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(muted) }
    @discardableResult func saveIfNeeded(force: Bool = false) -> Bool {
        guard dirty || force else { return true }
        let success = store.updateApplication(job.id, stage: stageEdited ? stage : nil, notes: notes, followUpAt: followUp ? date : nil)
        if !success { feedback = store.notice }
        if success { dirty = false; stageEdited = false; stage = latest.stage; feedback = "已保存到本机" }
        return success
    }
}
