import SwiftUI
import AppKit

struct CareerTaskWorkspace: View {
    @ObservedObject var work: CareerWorkStore
    @ObservedObject var store: Store
    @ObservedObject var profile: ApplicationProfileStore
    var home = false
    let open: (String) -> Void
    @State private var instruction = ""
    @State private var proposal: [CareerWorkTask] = []
    @State private var selectedID: String?
    @State private var filter = "全部"
    @State private var busy = false
    @State private var message = ""
    @State private var operation: Task<Void, Never>?
    @State private var editing: CareerWorkTask?
    private var tasks: [CareerWorkTask] { work.data.tasks.filter { filter == "全部" || $0.status == filter }.sorted { $0.updatedAt > $1.updatedAt } }
    private var selected: CareerWorkTask? { tasks.first { $0.id == selectedID } ?? tasks.first }
    private var realApplications: [ApplicationRecord] { store.applications.values.filter { record in store.jobs.contains { $0.id == record.jobID && $0.source != "示例岗位" } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(home ? "今天的求职工作台" : "任务中心").font(.system(size: 25, weight: .semibold))
                    Text(Date().formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small); Button("停止") { operation?.cancel() } }
                Button("新建任务", systemImage: "plus") { editing = .init(title: "", instruction: "", kind: .resume) }
            }
            if home { overview }
            HStack(alignment: .top) {
                TextField("告诉我你要推进的求职目标，例如：为目标岗位优化简历并准备一轮面试", text: $instruction, axis: .vertical).lineLimit(2...4).textFieldStyle(.flow)
                Button("生成计划", systemImage: "sparkles") { generatePlan() }.buttonStyle(.flowPrimary).disabled(busy || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !proposal.isEmpty { proposedPlan }
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            if let error = work.error { Text(error).foregroundStyle(.red) }
            if let brief = work.data.briefs.first {
                DisclosureGroup("每日简报 · \(brief.date.formatted(date: .abbreviated, time: .shortened))") { ScrollView { Text(brief.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 190) }
            }
            HSplitView {
                VStack(alignment: .leading) {
                    Picker("任务状态", selection: $filter) { ForEach(["全部","待开始","进行中","等待操作","已暂停","已完成","失败"], id: \.self) { Text($0) } }.labelsHidden()
                    List(tasks, selection: $selectedID) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title).fontWeight(.medium)
                            Text("\(task.kind.rawValue) · \(task.status)").font(.caption).foregroundStyle(.secondary)
                            if let date = task.dueAt { Text(date, style: .date).font(.caption) }
                        }.padding(.vertical, 6).tag(task.id)
                    }.listStyle(.plain)
                    if tasks.isEmpty { Text("还没有任务。创建一个，或让 AI 拆解你的目标。").foregroundStyle(.secondary).padding() }
                }.frame(minWidth: 260, idealWidth: 320)
                if let task = selected { detail(task) } else { ContentUnavailableView("从一个明确目标开始", systemImage: "checklist", description: Text("计划、产物和后续操作会保存在这里。")) }
            }
        }.padding(28).background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editing) { task in CareerTaskEditor(task: task, jobs: store.jobs.filter { $0.source != "示例岗位" }) { edited in
            if work.update({ next in if let i = next.tasks.firstIndex(where: { $0.id == edited.id }) { next.tasks[i] = edited } else { next.tasks.insert(edited, at: 0) } }) { editing = nil; selectedID = edited.id }
        } }
        .onDisappear { operation?.cancel() }
    }
    private var overview: some View {
        HStack(spacing: 16) {
            metric("进行中的申请", realApplications.filter(\.isOpen).count, "applications")
            metric("待推进任务", work.data.tasks.filter { $0.status != "已完成" }.count, "tasks")
            metric("网申队列", work.data.queue.filter { !["已提交","已移除"].contains($0.status) }.count, "queue")
            Spacer()
            Button("生成今日简报") { generateBrief() }.disabled(busy)
            Button("求职日历", systemImage: "calendar") { open("calendar") }
        }
    }
    private func metric(_ title: String, _ count: Int, _ route: String) -> some View {
        Button { open(route) } label: { VStack(alignment: .leading, spacing: 8) { Text(title).foregroundStyle(.secondary); Text("\(count)").font(.system(size: 27, weight: .semibold)) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
    }
    private var proposedPlan: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待加入的计划").font(.headline)
            ForEach(proposal) { step in HStack { Text(step.title); Spacer(); Text(step.kind.rawValue).foregroundStyle(.secondary) } }
            HStack {
                Button("加入任务中心") { if work.update({ $0.tasks.insert(contentsOf: proposal, at: 0) }) { proposal = [] } }.buttonStyle(.flowPrimary)
                Button("放弃这份计划") { proposal = [] }
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
    private func detail(_ task: CareerWorkTask) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text(task.title).font(.title2.bold()); Spacer(); Button("编辑") { editing = task } }
                if let job = store.jobs.first(where: { $0.id == task.jobID }) { Text("\(job.company) · \(job.title)").foregroundStyle(.secondary) }
                Text(task.instruction).textSelection(.enabled)
                HStack {
                    Button(task.status == "已暂停" ? "继续任务" : "执行任务", systemImage: "play.fill") { execute(task) }.buttonStyle(.flowPrimary).disabled(busy)
                    Button("打开\(task.kind.rawValue)") { if let id = task.jobID { store.selected = id }; open(task.kind.page) }
                    Menu("更新状态") { ForEach(["待开始","已暂停","已完成"], id: \.self) { status in Button(status) { work.setTask(task.id, status: status) } } }
                }
                if !task.result.isEmpty { Divider(); Text(task.result).textSelection(.enabled) }
                Text("更新时间：\(task.updatedAt.formatted())").font(.caption).foregroundStyle(.secondary)
                Button("删除任务", role: .destructive) { work.update { $0.tasks.removeAll { $0.id == task.id } } }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 360)
    }
    private func generatePlan() {
        busy = true; message = "正在根据现有公司和岗位生成计划…"
        operation = Task { @MainActor in
            defer { busy = false }
            do { proposal = try await CareerWorkAI.plan(instruction: instruction, store: store); try Task.checkCancellation(); message = "计划已生成，加入后可以逐项执行。" }
            catch is CancellationError { message = "已停止生成计划。" }
            catch { message = error.localizedDescription }
        }
    }
    private func execute(_ task: CareerWorkTask) {
        if ![.resume, .matching, .brief].contains(task.kind) {
            work.setTask(task.id, status: "等待操作", result: "已打开对应工具。完成后可回到任务中心确认完成。")
            if let id = task.jobID { store.selected = id }; open(task.kind.page); return
        }
        busy = true; work.setTask(task.id, status: "进行中")
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                switch task.kind {
                case .resume:
                    guard let job = store.jobs.first(where: { $0.id == task.jobID }) else { throw AIError.message("请编辑任务，选择对应的公司和岗位。") }
                    let document = try await ResumeStudioStore.shared.optimize(job: job, profile: profile.profile)
                    work.setTask(task.id, status: "已完成", result: "已生成岗位定制简历与修改建议：\(document.name)。请到简历工作室逐条核对采纳。")
                case .matching:
                    guard let job = store.jobs.first(where: { $0.id == task.jobID }) else { throw AIError.message("请编辑任务，选择对应的公司和岗位。") }
                    let result = try await CareerWorkAI.match(job: job, profile: profile.profile, preferences: work.data.preferences)
                    try Task.checkCancellation()
                    guard work.update({ $0.matches[job.id] = result }) else { throw AIError.message(work.error ?? "保存匹配结果失败") }
                    work.setTask(task.id, status: "已完成", result: "匹配评估 \(result.score)/100\n" + result.summary)
                case .brief:
                    let brief = try await makeBrief(); guard work.update({ $0.briefs.insert(brief, at: 0) }) else { throw AIError.message(work.error ?? "保存简报失败") }
                    work.setTask(task.id, status: "已完成", result: brief.text)
                default: break
                }
            } catch is CancellationError { work.setTask(task.id, status: "已暂停") }
            catch { work.setTask(task.id, status: "失败", result: error.localizedDescription) }
        }
    }
    private func makeBrief() async throws -> CareerDailyBrief {
        try await CareerWorkAI.brief(store: store, work: work)
    }
    private func generateBrief() {
        busy = true
        operation = Task { @MainActor in
            defer { busy = false }
            do { let brief = try await makeBrief(); if work.update({ $0.briefs.insert(brief, at: 0) }) { message = "今日简报已保存。" } }
            catch is CancellationError { message = "已停止。" }
            catch { message = error.localizedDescription }
        }
    }
}

private struct CareerTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var task: CareerWorkTask
    let jobs: [Job]
    let save: (CareerWorkTask) -> Void
    @State private var hasDue = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("任务详情").font(.title2.bold())
            TextField("任务标题", text: $task.title).textFieldStyle(.flow)
            Picker("任务类型", selection: $task.kind) { ForEach(CareerWorkKind.allCases) { Text($0.rawValue).tag($0) } }
            Picker("公司与岗位", selection: Binding(get: { task.jobID ?? "" }, set: { task.jobID = $0.isEmpty ? nil : $0 })) { Text("不关联岗位").tag(""); ForEach(jobs) { Text("\($0.company) · \($0.title)").tag($0.id) } }
            TextEditor(text: $task.instruction).frame(height: 150).border(.quaternary)
            Toggle("设置计划时间", isOn: $hasDue)
            if hasDue { DatePicker("计划时间", selection: Binding(get: { task.dueAt ?? Date() }, set: { task.dueAt = $0 })) }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存") { task.updatedAt = Date(); if !hasDue { task.dueAt = nil }; save(task) }.disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 540).onAppear { hasDue = task.dueAt != nil }
    }
}
