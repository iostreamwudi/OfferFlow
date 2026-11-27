import SwiftUI

struct CareerMatchingWorkspace: View {
    @ObservedObject var work: CareerWorkStore
    @ObservedObject var store: Store
    @ObservedObject var profile: ApplicationProfileStore
    @ObservedObject var liveJobs: LiveJobsSession
    let open: (String) -> Void
    @State private var preferences = CareerPreferences()
    @State private var source = "实时岗位库"
    @State private var selected: String?
    @State private var query = ""
    @State private var threshold = 0
    @State private var onlyAnalyzed = false
    @State private var pool: [Job] = []
    @State private var limit = 100
    @State private var busy = false
    @State private var progress = ""
    @State private var operation: Task<Void, Never>?
    @State private var message = ""
    private func report(_ job: Job) -> CareerMatchResult? { work.data.matches[job.id] }
    private var filtered: [Job] {
        pool.filter { job in
            let text = CareerWorkAI.source(job)
            let tokens = [query, preferences.role, preferences.city, preferences.industry, preferences.cohort, preferences.education, preferences.employmentType]
            guard tokens.allSatisfy({ value in value.isEmpty || value.split(whereSeparator: { $0.isWhitespace || $0 == "、" || $0 == "," || $0 == "，" }).contains { text.localizedCaseInsensitiveContains(String($0)) } }) else { return false }
            if preferences.exclusions.split(whereSeparator: { $0.isWhitespace || $0 == "、" || $0 == "," }).contains(where: { text.localizedCaseInsensitiveContains(String($0)) }) { return false }
            let result = report(job)
            return (!onlyAnalyzed || result != nil) && (threshold == 0 || (result?.score ?? -1) >= threshold)
        }.sorted { a, b in let x = report(a)?.score ?? -1, y = report(b)?.score ?? -1; return x == y ? a.created > b.created : x > y }
    }
    private var selectedJob: Job? { filtered.first { $0.id == selected } ?? filtered.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text("为你匹配的机会").font(.system(size: 25, weight: .semibold)); Text("根据求职偏好筛选，用真实经历解释匹配原因").foregroundStyle(.secondary) }
                Spacer()
                if busy { ProgressView().controlSize(.small); Button("暂停分析") { operation?.cancel() } }
            }
            DisclosureGroup("求职偏好") {
                VStack(spacing: 10) {
                    HStack { field("目标岗位", $preferences.role); field("城市", $preferences.city); field("行业", $preferences.industry) }
                    HStack { field("毕业届次", $preferences.cohort); field("学历", $preferences.education); field("求职类型", $preferences.employmentType) }
                    HStack { field("排除关键词", $preferences.exclusions); Button("保存偏好") { if work.update({ $0.preferences = preferences }) { message = "偏好已保存。" } } }
                    Text("同一项可用空格分隔多个候选值；不同项同时满足。信息不完整的招聘公告，仍需核对具体岗位 JD。").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            HStack {
                Picker("岗位来源", selection: $source) { Text("实时岗位库").tag("实时岗位库"); Text("已保存岗位").tag("已保存岗位") }.frame(width: 190)
                TextField("搜索公司或岗位", text: $query).textFieldStyle(.flow)
                Toggle("只看已分析", isOn: $onlyAnalyzed)
                Picker("最低匹配分", selection: $threshold) { ForEach([0,40,60,70,80,90], id: \.self) { Text($0 == 0 ? "不限分数" : "\($0) 分以上").tag($0) } }.frame(width: 150)
            }
            HStack {
                Text("\(filtered.count) 条机会").foregroundStyle(.secondary)
                Spacer()
                Button("分析所选岗位") { if let job = selectedJob { analyze([job], force: true) } }.disabled(busy || selectedJob == nil)
                Button("分析当前筛选结果（\(filtered.count)）") { analyze(filtered, force: false) }.disabled(busy || filtered.isEmpty)
            }
            if !progress.isEmpty { Text(progress).font(.caption).foregroundStyle(.secondary) }
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
            if let error = work.error { Text(error).foregroundStyle(.red) }
            HSplitView {
                VStack {
                    List(Array(filtered.prefix(limit)), selection: $selected) { job in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(job.title).fontWeight(.medium); Spacer(); if let result = report(job) { Text("\(result.score)").fontWeight(.semibold).foregroundStyle(.teal) } }
                            Text("\(job.company) · \(job.city)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).tag(job.id)
                    }.listStyle(.plain)
                    if filtered.count > limit { Button("继续显示更多岗位") { limit += 100 } }
                }.frame(minWidth: 300, idealWidth: 360)
                if let job = selectedJob { details(job) } else { ContentUnavailableView("没有匹配当前筛选的岗位", systemImage: "magnifyingglass", description: Text("调整偏好或更新岗位库后再试。")) }
            }
        }.padding(28).background(Color(nsColor: .windowBackgroundColor))
        .onAppear { preferences = work.data.preferences; refreshPool() }
        .onChange(of: source) { _, _ in refreshPool() }
        .onChange(of: liveJobs.dataRevision) { _, _ in refreshPool() }
        .onChange(of: store.jobs) { _, _ in refreshPool() }
        .onDisappear { operation?.cancel() }
    }
    private func field(_ label: String, _ binding: Binding<String>) -> some View { TextField(label, text: binding).textFieldStyle(.flow) }
    private func refreshPool() { pool = source == "实时岗位库" ? LiveJobListing.roleListings(from: liveJobs.jobs).map(Job.init(listing:)) : store.jobs.filter { $0.source != "示例岗位" }; limit = 100 }
    private func details(_ job: Job) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(job.title).font(.title2.bold()); Text("\(job.company) · \(job.city)").foregroundStyle(.secondary)
                if let result = report(job) {
                    Text("匹配评估 \(result.score)/100").font(.title3.weight(.semibold))
                    if result.sourceFingerprint != CareerWorkAI.fingerprint(job: job, profile: profile.profile, preferences: preferences) { Text("资料、偏好或岗位已变化，请重新分析。").foregroundStyle(.orange) }
                    Text(result.summary).textSelection(.enabled)
                    ForEach(Array(result.reasons.enumerated()), id: \.offset) { _, reason in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(reason.requirement).fontWeight(.medium)
                            Text(reason.explanation)
                            if let fact = CareerWorkAI.facts(profile.profile).first(where: { $0.id == reason.factID }) { Text("档案依据：\(fact.label)：\(fact.value)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if !result.gaps.isEmpty { Text("需要核对的差距").font(.headline); ForEach(result.gaps, id: \.self) { Text("• " + $0) } }
                    Text("\(result.model) · \(result.createdAt.formatted()) · 分数不是录用概率").font(.caption).foregroundStyle(.secondary)
                } else { Text("分析后将展示匹配依据和待核对条件。").foregroundStyle(.secondary) }
                Divider(); Text(job.jd).textSelection(.enabled)
                HStack {
                    Button("加入投递管理") { add(job) }
                    Button("定制简历") { add(job); open("resumes") }
                    if let url = job.sourceURL, LiveJobListing.safeHTTPURL(url) != nil { Button("加入网申队列") { add(job); if work.enqueue(company: job.company, role: job.title, url: url, jobID: store.selected) { message = "已加入队列。" } } }
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 360)
    }
    private func add(_ job: Job) {
        if let existing = store.jobs.first(where: { $0.id == job.id || ($0.company == job.company && $0.title == job.title) }) { store.selected = existing.id; _ = store.updateApplication(existing.id, stage: nil, notes: store.applications[existing.id]?.notes ?? "", followUpAt: store.applications[existing.id]?.followUpAt) }
        else { store.add(job); _ = store.updateApplication(job.id, stage: .planned, notes: "来自岗位匹配", followUpAt: nil) }
        message = store.notice.isEmpty ? "已保存公司与岗位。" : store.notice
    }
    private func analyze(_ jobs: [Job], force: Bool) {
        let facts = profile.profile, prefs = preferences
        let candidates = jobs.filter { force || report($0)?.sourceFingerprint != CareerWorkAI.fingerprint(job: $0, profile: facts, preferences: prefs) }
        guard !candidates.isEmpty else { message = "当前结果均已分析，所用资料未变化。"; return }
        busy = true; message = ""
        operation = Task { @MainActor in
            defer { busy = false }
            var done = 0, failures = 0
            for job in candidates {
                if Task.isCancelled { break }
                progress = "\(done + failures + 1)/\(candidates.count) · \(job.company) · \(job.title)"
                do {
                    let result = try await CareerWorkAI.match(job: job, profile: facts, preferences: prefs)
                    try Task.checkCancellation()
                    if work.update({ $0.matches[job.id] = result }) { done += 1 } else { break }
                } catch is CancellationError { break }
                catch { failures += 1; message = error.localizedDescription }
            }
            progress = "已分析 \(done) 条，失败 \(failures) 条。\(Task.isCancelled ? "已暂停，再次分析会复用有效结果。" : "")"
        }
    }
}
