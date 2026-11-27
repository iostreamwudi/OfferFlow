import SwiftUI
import AppKit

struct CareerApplicationQueue: View {
    @ObservedObject var work: CareerWorkStore
    @ObservedObject var store: Store
    @ObservedObject private var resumes = ResumeStudioStore.shared
    let openApplication: (CareerQueueItem, URL?) -> Void
    @State private var selected: String?
    @State private var filter = "全部"
    @State private var bulk = ""
    @State private var showAdd = false
    @State private var message = ""
    @State private var company = ""
    @State private var role = ""
    @State private var url = ""
    private var items: [CareerQueueItem] { work.data.queue.filter { $0.status != "已移除" && (filter == "全部" || $0.status == filter) } }
    private var current: CareerQueueItem? { items.first { $0.id == selected } ?? items.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text("网申任务队列").font(.system(size: 25, weight: .semibold)); Text("每个公司、每个岗位，分别选择简历并准备申请").foregroundStyle(.secondary) }
                Spacer(); Button("添加岗位", systemImage: "plus") { showAdd = true }
                Button("继续下一项", systemImage: "play.fill") { if let item = work.data.queue.first(where: { ["待准备","已暂停","等待登录","失败"].contains($0.status) }) { selected = item.id; launch(item) } }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            if let error = work.error { Text(error).foregroundStyle(.red) }
            HSplitView {
                VStack(alignment: .leading) {
                    Picker("状态", selection: $filter) { ForEach(["全部","待准备","等待登录","填写中","已暂停","待核对","已提交","失败"], id: \.self) { Text($0) } }
                    List(items, selection: $selected) { item in VStack(alignment: .leading, spacing: 7) { Text(item.role).fontWeight(.medium); Text(item.company).font(.callout); Text(item.status).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 6).tag(item.id) }.listStyle(.plain)
                }.frame(minWidth: 280, idealWidth: 330)
                if let item = current { detail(item) } else { ContentUnavailableView("还没有网申任务", systemImage: "list.bullet.rectangle", description: Text("从实时岗位库加入，或粘贴公司、岗位和网申链接。")) }
            }
        }.padding(28).background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showAdd) { addSheet }
    }
    private func detail(_ item: CareerQueueItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.company).foregroundStyle(.secondary); Text(item.role).font(.title2.bold())
                Text(item.url).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Picker("本次申请的简历", selection: Binding(get: { item.resumeID ?? "" }, set: { value in work.update { next in if let i = next.queue.firstIndex(where: { $0.id == item.id }) { next.queue[i].resumeID = value.isEmpty ? nil : value } } })) {
                    Text("使用网申档案当前简历").tag("")
                    ForEach(resumes.documents) { Text($0.name).tag($0.id) }
                }
                Text("选择的简历只用于这次网申附件；基础信息仍从个人资料填写。登录与验证码由你完成，最终提交前自行核对。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("打开并准备填写", systemImage: "globe") { launch(item) }.buttonStyle(.flowPrimary)
                    Button("暂停") { work.setQueue(item.id, status: "已暂停") }
                    Button("跳到下一项") { if let next = items.first(where: { $0.id != item.id && !["已提交","填写中"].contains($0.status) }) { selected = next.id; launch(next) } }
                }
                Divider()
                Text("记录实际进展").font(.headline)
                HStack {
                    Button("等待登录") { work.setQueue(item.id, status: "等待登录") }
                    Button("已填好，待核对") { work.setQueue(item.id, status: "待核对") }
                    Button("我已在网站提交") { confirmSubmitted(item) }
                }
                TextField("本次申请备注", text: Binding(get: { item.note }, set: { work.setQueue(item.id, status: item.status, note: $0) }), axis: .vertical).lineLimit(3...8).textFieldStyle(.flow)
                Text("仅标记用户已确认的提交，不将填写完成记作已投递。").font(.caption).foregroundStyle(.secondary)
                Button("移出队列", role: .destructive) { work.setQueue(item.id, status: "已移除") }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 370)
    }
    private func launch(_ item: CareerQueueItem) {
        guard let target = LiveJobListing.safeHTTPURL(item.url) else { message = "这个网申链接无效，请重新添加。"; return }
        do {
            let file = try item.resumeID.map { try resumes.materializeAttachment(documentID: $0) }
            if let resumeID = item.resumeID, let jobID = item.jobID { try resumes.bind(documentID: resumeID, jobID: jobID) }
            _ = target
            work.setQueue(item.id, status: "等待登录")
            openApplication(item, file)
        } catch { message = error.localizedDescription; work.setQueue(item.id, status: "失败", note: error.localizedDescription) }
    }
    private func confirmSubmitted(_ item: CareerQueueItem) {
        let jobID = item.jobID ?? store.registerApplication(company: item.company, title: item.role, stage: .submitted)
        guard let jobID else { message = store.notice; return }
        let record = store.applications[jobID]
        guard store.updateApplication(jobID, stage: (record?.stage.order ?? 0) >= ApplicationStage.submitted.order ? nil : .submitted, notes: record?.notes ?? item.note, followUpAt: record?.followUpAt) else { message = store.notice; return }
        work.update { next in if let i = next.queue.firstIndex(where: { $0.id == item.id }) { next.queue[i].jobID = jobID; next.queue[i].status = "已提交"; next.queue[i].updatedAt = Date() } }
        message = "已同步到该公司与岗位的投递记录。"
    }
    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加网申岗位").font(.title2.bold())
            HStack { TextField("公司", text: $company); TextField("岗位", text: $role) }.textFieldStyle(.flow)
            TextField("https://… 网申链接", text: $url).textFieldStyle(.flow)
            Button("添加这条") { if !company.isEmpty && !role.isEmpty && work.enqueue(company: company, role: role, url: url) { showAdd = false; company = ""; role = ""; url = "" } }
            Divider(); Text("批量粘贴：每行 公司 ⇥ 岗位 ⇥ 网申链接（Tab 分隔）").font(.caption)
            TextEditor(text: $bulk).frame(height: 180).border(.quaternary)
            HStack { Spacer(); Button("取消") { showAdd = false }; Button("加入队列") {
                var candidates: [CareerQueueItem] = [], invalid = 0
                for line in bulk.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    let parts = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count == 3 && !parts[0].isEmpty && !parts[1].isEmpty && LiveJobListing.safeHTTPURL(parts[2]) != nil {
                        candidates.append(.init(company: parts[0], role: parts[1], url: parts[2]))
                    } else { invalid += 1 }
                }
                let count = work.enqueueBatch(candidates)
                message = "已加入 \(count) 条；重复条目自动跳过；\(invalid) 条格式或链接无效。"
                if invalid == 0 && work.error == nil { bulk = ""; showAdd = false }

            }.buttonStyle(.flowPrimary) }
            if let error = work.error { Text(error).foregroundStyle(.red) }
        }.padding(24).frame(width: 620)
    }
}
