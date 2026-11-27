import SwiftUI
import AppKit

/// A native view of the public recruitment feed. Source records remain leads,
/// rather than being treated as complete BOSS job descriptions.
struct LiveJobsWorkspace: View {
    @EnvironmentObject private var journey: FlowJourney
    @State private var filtersRestored = false
    @ObservedObject var session: LiveJobsSession
    let onOpenApplication: (URL, String) -> Void
    var onMail: ((LiveJobListing, String) -> Void)? = nil
    var onQueue: (([LiveJobListing]) -> Void)? = nil
    @State private var filters = LiveJobFilterState()
    @State private var showFilters = false
    @State private var selectedID: String?
    @State private var selectedIDs: Set<String> = []
    @State private var roleView = false
    @State private var preparedRoleView = false
    @State private var visibleJobs: [LiveJobListing] = []
    @State private var visibleJobPositions: [String: Int] = [:]
    @State private var listRevision = 0
    @State private var searchIndex: LiveJobSearchIndex?
    @State private var preparedDataRevision = -1
    @State private var isFiltering = true
    @State private var appliedFilterKey: FeedFilterKey?
    @State private var filterOptions: [Int: [String]] = [:]

    private func consumeIntent() {
        guard let request = journey.intent, request.route == "liveJobs" else { return }
        if let company = request.company { filters.company = company }
        if let role = request.role { filters.role = role }
        if let keyword = request.keyword { filters.query = keyword }
        journey.intent = nil
    }
    private var selectedJob: LiveJobListing? {
        guard let selectedID, let position = visibleJobPositions[selectedID], visibleJobs.indices.contains(position) else { return nil }
        return visibleJobs[position]
    }

    private var filterKey: FeedFilterKey {
        FeedFilterKey(filters: filters, favoriteIDs: filters.onlyFavorites ? session.favoriteIDs : [],
                      dataRevision: session.dataRevision, preparedRevision: preparedDataRevision, roleView: roleView, preparedRoleView: preparedRoleView)
    }

    private var filterPending: Bool { isFiltering || appliedFilterKey != filterKey }

    var body: some View {
        FlowSurface {
        VStack(spacing: 0) {
            header
            if let error = session.lastError {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("重试更新") { session.refresh() }.buttonStyle(.borderless)
                }.padding(.horizontal, 28).padding(.vertical, 11)
                    .background(Color.orange.opacity(0.07))
            }
            searchAndFilters
            Divider()
            if session.jobs.isEmpty {
                initialState
            } else if visibleJobs.isEmpty && filterPending {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("正在整理岗位列表…").font(.system(size: 12)).foregroundStyle(muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleJobs.isEmpty {
                noResults
            } else {
                HSplitView {
                    jobList.frame(minWidth: 330, idealWidth: 405, maxWidth: 520)
                    if let job = selectedJob {
                        LiveJobDetail(job: job, isFavorite: session.favoriteIDs.contains(job.id),
                                      toggleFavorite: { session.toggleFavorite(job.id) }, onOpenApplication: onOpenApplication, onMail: onMail)
                            .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 28)).foregroundStyle(muted)
                            Text("选择一条招聘信息").font(.system(size: 16, weight: .medium))
                            Text("查看岗位要求、截止时间与投递方式")
                                .font(.system(size: 12)).foregroundStyle(muted)
                        }.frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .foregroundStyle(ink).background(.white)
         .onAppear {
            if !filtersRestored { filters = LocalAIStorage.read("job-filters-v1.json", as: LiveJobFilterState.self) ?? LiveJobFilterState(); filtersRestored = true }
            consumeIntent(); session.activate()
        }
        .onChange(of: filters) { _, value in if filtersRestored { try? LocalAIStorage.save(value, name: "job-filters-v1.json") } }
        .onChange(of: journey.revision) { _, _ in consumeIntent() }
        .task(id: "\(session.dataRevision)-\(roleView)") { await prepareSearchIndex() }
        .task(id: filterKey) { await applyFilters() }
    
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("实时岗位库").font(.system(size: 23, weight: .bold))
                    if !session.jobs.isEmpty {
                        Text("\(session.jobs.count.formatted()) 条招聘信息")
                            .font(.system(size: 12)).foregroundStyle(muted)
                    }
                }
                HStack(spacing: 7) {
                    if session.isRefreshing {
                        ProgressView().controlSize(.mini)
                        Text(session.statusText).lineLimit(1)
                    } else {
                        Image(systemName: session.lastError == nil ? "checkmark.circle" : "clock")
                            .foregroundStyle(session.lastError == nil ? accent : muted)
                        if let date = session.lastSuccessfulUpdate {
                            Text("上次更新 \(date.formatted(date: .abbreviated, time: .shortened))")
                        } else {
                            Text("打开时自动更新")
                        }
                    }
                }.font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer(minLength: 10)
            if let onQueue {
                Menu("加入网申队列") {
                    Button("选中的岗位（\(selectedIDs.count) 条）") { onQueue(visibleJobs.filter { selectedIDs.contains($0.id) && !$0.applicationURLs.isEmpty }) }.disabled(filterPending || selectedIDs.isEmpty)
                    Button("当前岗位") { if let job = selectedJob { onQueue([job]) } }.disabled(selectedJob?.applicationURLs.isEmpty != false)
                    Button("当前筛选结果（\(visibleJobs.filter { !$0.applicationURLs.isEmpty }.count) 条）") { onQueue(visibleJobs.filter { !$0.applicationURLs.isEmpty }) }.disabled(filterPending)
                }
            }
            
            Button {
                session.refresh()
            } label: {
                Label(session.isRefreshing ? "更新中" : "更新岗位", systemImage: "arrow.clockwise")
            }.buttonStyle(.flowPrimary).tint(accent)
                .disabled(session.isRefreshing)
                .help("更新最新招聘信息")
        }.padding(.horizontal, 28).padding(.vertical, 23)
    }

    private var searchAndFilters: some View {
        VStack(spacing: 11) {
            HStack {
                FlowSegments(selection: $roleView, options: [(false, "招聘项目"), (true, "岗位明细")]).frame(width: 200)
                Text(roleView ? "按来源中明确列出的岗位拆分，要求以原公告为准" : "按招聘项目浏览").font(.caption).foregroundStyle(muted)
                Spacer()
                Button("全选当前结果") { selectedIDs = Set(visibleJobs.map(\.id)) }.disabled(filterPending)
                Button("清除选择") { selectedIDs = []; selectedID = nil }.disabled(selectedIDs.isEmpty)
                Text("已选 \(selectedIDs.count)").font(.caption).foregroundStyle(muted)
            }
            HStack(spacing: 10) {
                Text("岗位关键词").font(.system(size: 13, weight: .medium))
                TextField("例如：产品、AI 产品、数据分析", text: $filters.role)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .accessibilityLabel("岗位关键词模糊查询")
                if !filters.role.isEmpty {
                    Button { filters.role = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(muted) }
                        .buttonStyle(.plain).accessibilityLabel("清除岗位关键词")
                }
            }.padding(.horizontal, 13).padding(.vertical, 11)
                .background(accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent.opacity(0.22)))
            Text("输入部分岗位名称即可匹配；多个关键词用空格分隔，顺序不限，需同时包含。忽略大小写、全半角及名称中的空格。")
                .font(.caption).foregroundStyle(muted).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(muted)
                TextField("综合搜索：公司、岗位或城市", text: $filters.query)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .accessibilityLabel("搜索岗位库")
                if !filters.query.isEmpty {
                    Button { filters.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(muted) }
                        .buttonStyle(.plain).accessibilityLabel("清除岗位搜索")
                }
            }.padding(.horizontal, 13).padding(.vertical, 11)
                .background(.white, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.09)))
            HStack(spacing: 8) {
                facet(5, label: "工作地点")
                facet(3, label: "行业")
                facet(7, label: "届次")
                Toggle(isOn: $filters.onlyFavorites) { Label("已收藏", systemImage: filters.onlyFavorites ? "bookmark.fill" : "bookmark") }
                    .toggleStyle(.button).tint(accent)
                Button { showFilters.toggle() } label: {
                    Label(filters.activeCount == 0 ? "更多筛选" : "筛选 · \(filters.activeCount)", systemImage: "line.3.horizontal.decrease")
                }.popover(isPresented: $showFilters, arrowEdge: .bottom) {
                    LiveJobFilterPanel(filters: $filters, options: filterOptions, close: { showFilters = false })
                }
                Spacer(minLength: 6)
                if !session.jobs.isEmpty {
                    Text(filterPending ? "筛选中…" : "\(visibleJobs.count.formatted()) 条结果")
                        .font(.system(size: 11)).foregroundStyle(muted).monospacedDigit()
                }
            }.controlSize(.small)
            HStack {
                FlowSelect(title: "投递方式", selection: $filters.channel, options: LiveJobFilterState.Channel.allCases.map { ($0, $0.rawValue) }).frame(width: 245)
                FlowSelect(title: "排序", selection: $filters.sort, options: LiveJobFilterState.Sort.allCases.map { ($0, $0.rawValue) }).frame(width: 245)
                Spacer()
                Text("按 ⌘ 多选，按 ⇧ 连续选择").font(.caption).foregroundStyle(muted)
            }.controlSize(.small)
            if filters.activeCount > 0 {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if !filters.query.isEmpty { chip("搜索：" + filters.query) { filters.query = "" } }
                            ForEach(LiveJobSearchIndex.facetFields, id: \.self) { field in
                                if let values = filters.selected[field], !values.isEmpty {
                                    chip(LiveJobParser.expectedHeaders[field] + "：" + values.sorted().joined(separator: "、")) { filters.selected[field] = nil }
                                }
                            }
                            if !filters.company.isEmpty { chip("公司：" + filters.company) { filters.company = "" } }
                            if !filters.role.isEmpty { chip("岗位：" + filters.role) { filters.role = "" } }
                            if !filters.major.isEmpty { chip("专业：" + filters.major) { filters.major = "" } }
                            if filters.channel != .all { chip(filters.channel.rawValue) { filters.channel = .all } }
                            if filters.onlyFavorites { chip("已收藏") { filters.onlyFavorites = false } }
                            if filters.deadline != .all { chip(filters.deadline.rawValue) { filters.deadline = .all } }
                            if !filters.updatedFrom.isEmpty || !filters.updatedTo.isEmpty {
                                chip("更新：\(filters.updatedFrom) — \(filters.updatedTo)") { filters.updatedFrom = ""; filters.updatedTo = "" }
                            }
                            if !filters.deadlineFrom.isEmpty || !filters.deadlineTo.isEmpty {
                                chip("截止：\(filters.deadlineFrom) — \(filters.deadlineTo)") { filters.deadlineFrom = ""; filters.deadlineTo = "" }
                            }
                            ForEach(filters.rules.filter(\.isActive)) { rule in
                                chip(LiveJobParser.expectedHeaders[rule.field] + " " + rule.operation.rawValue + " " + rule.value) { filters.rules.removeAll { $0.id == rule.id } }
                            }
                        }
                    }
                    Button("清除全部") { filters = LiveJobFilterState() }.buttonStyle(.borderless).font(.system(size: 11))
                }
            }
            if let error = filters.dateError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.horizontal, 28).padding(.top, 2).padding(.bottom, 15)
            .background(canvas)
    }

    private func facet(_ field: Int, label: String) -> some View {
        LiveJobFacetPicker(label: label, values: filterOptions[field] ?? [], selection: Binding(
            get: { filters.selected[field] ?? [] }, set: { filters.selected[field] = $0 }))
    }

    private func chip(_ text: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(text).lineLimit(1).truncationMode(.tail)
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }.font(.system(size: 10)).padding(.horizontal, 8).padding(.vertical, 5)
                .background(accent.opacity(0.07), in: Capsule()).foregroundStyle(accent)
        }.buttonStyle(.plain).frame(maxWidth: 200).help("移除筛选：" + text)
    }

    private var jobList: some View {
        LiveJobsTable(jobs: visibleJobs, positions: visibleJobPositions, revision: listRevision,
                      favorites: session.favoriteIDs, selectedID: $selectedID, selectedIDs: $selectedIDs)
    }

    private var initialState: some View {
        VStack(spacing: 15) {
            if session.isRefreshing {
                ProgressView().controlSize(.regular)
                Text("正在获取最新招聘信息").font(.system(size: 18, weight: .semibold))
                Text("首次读取需要一点时间，后续打开会先显示已保存的岗位。")
                    .font(.system(size: 12)).foregroundStyle(muted)
            } else {
                Image(systemName: "tray").font(.system(size: 32)).foregroundStyle(muted)
                Text("等待更新岗位库").font(.system(size: 18, weight: .semibold))
                Text("获取最新招聘信息，在这里搜索、收藏和投递。")
                    .font(.system(size: 12)).foregroundStyle(muted)
                Button("更新岗位") { session.refresh() }.buttonStyle(.flowPrimary).tint(accent)
            }
        }.multilineTextAlignment(.center).padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 14) {
            Image(systemName: filters.onlyFavorites ? "bookmark" : "magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(muted)
            Text(filters.onlyFavorites ? "还没有符合条件的收藏" : "没有找到符合条件的招聘信息")
                .font(.system(size: 17, weight: .semibold))
            Text("试试更短的关键词，或调整筛选条件。")
                .font(.system(size: 12)).foregroundStyle(muted)
            Button("清除筛选") {
                filters = LiveJobFilterState()
            }
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func prepareSearchIndex() async {
        let revision = session.dataRevision
        let jobs = session.jobs, mode = roleView
        let adapters = ApplicationSiteRuleStore()
        let adaptedURLs = Set(jobs.flatMap(\.applicationURLs).filter { adapters.rule(for: $0) != nil }.map(\.absoluteString))
        let worker = Task.detached(priority: .userInitiated) { LiveJobSearchIndex(jobs: mode ? LiveJobListing.roleListings(from: jobs) : jobs, adaptedURLs: adaptedURLs) }
        let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, revision == session.dataRevision, mode == roleView, let result else { return }
        filterOptions = result.options
        // Keep explicit selections when a refreshed source has no matching
        // values; silently clearing them would unexpectedly broaden results.
        searchIndex = result
        preparedDataRevision = revision
        preparedRoleView = mode
    }

    private func applyFilters() async {
        let key = filterKey
        isFiltering = true
        guard preparedDataRevision == session.dataRevision, preparedRoleView == roleView, let index = searchIndex else { return }
        if key.filters.activeCount > 0 {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        }
        let worker = Task.detached(priority: .userInitiated) {
            index.filter(key.filters, favorites: key.favoriteIDs)
        }
        let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, key == filterKey, let result else { return }
        visibleJobs = result.jobs
        visibleJobPositions = result.positions
        listRevision += 1
        if let selectedID, result.positions[selectedID] == nil { self.selectedID = nil }
        selectedIDs.formIntersection(Set(result.positions.keys))
        if selectedID == nil { selectedID = result.jobs.first?.id; if let selectedID { selectedIDs.insert(selectedID) } }
        appliedFilterKey = key
        isFiltering = false
    }
}

private struct FeedFilterKey: Hashable, Sendable {
    let filters: LiveJobFilterState
    let favoriteIDs: Set<String>
    let dataRevision: Int
    let preparedRevision: Int
    let roleView: Bool
    let preparedRoleView: Bool
}

private struct LiveJobDetail: View {
    let job: LiveJobListing
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let onOpenApplication: (URL, String) -> Void
    var onMail: ((LiveJobListing, String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            Text(job.company).font(.system(size: 23, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            Spacer(minLength: 5)
                            Button(action: toggleFavorite) {
                                Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
                            }.buttonStyle(.flowSecondary)
                                .help(isFavorite ? "取消收藏" : "收藏招聘信息")
                                .accessibilityLabel(isFavorite ? "取消收藏招聘信息" : "收藏招聘信息")
                        }
                        HStack(spacing: 7) {
                            if !job.nature.isEmpty { tag(job.nature) }
                            if !job.industry.isEmpty { tag(job.industry) }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 18) {
                        metadata("工作地点", job.city, icon: "mappin.and.ellipse")
                        metadata("截止时间", job.deadline, icon: "calendar")
                        metadata("招聘届次", job.cohort, icon: "graduationcap")
                        metadata("学历要求", job.education, icon: "doc.text")
                    }
                    Divider()
                    section("招聘岗位", text: job.title)
                    if useful(job.majorRequirements) { section("专业要求", text: job.majorRequirements) }
                    if useful(job.exam) { section("笔试安排", text: job.exam) }
                    if useful(job.notes) { section("补充说明", text: job.notes) }
                    if !job.applyRaw.isEmpty && job.applyURL == nil {
                        section("投递方式", text: job.applyRaw)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("信息更新时间：\(job.sourceUpdated.isEmpty ? "未注明" : job.sourceUpdated)")
                        Text("招聘范围以企业公告为准，具体岗位要求请查看公告或网申页面。")
                            .fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 11)).foregroundStyle(muted)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(canvas, in: RoundedRectangle(cornerRadius: 10))
                }.padding(27).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 10) {
                if let url = job.announcementURL {
                    Button("招聘公告", systemImage: "doc.text") { open(url) }
                }
                Spacer(minLength: 8)
                if let onMail, !job.applicationEmails.isEmpty {
                    FlowActionMenu(title: "AI 投递邮件", actions: job.applicationEmails.map { address in .init(title: address, icon: "envelope") { onMail(job, address) } })
                }
                if job.applicationURLs.count > 1 {
                    FlowActionMenu(title: "选择投递入口", icon: "arrow.up.right", actions: job.applicationURLs.enumerated().map { index, url in
                        .init(title: "入口 \(index + 1) · \(url.host ?? "网申页面")") { open(url) }
                    })
                } else if let url = job.applicationURLs.first {
                    Button("打开网申", systemImage: "arrow.up.right") { open(url) }
                        .buttonStyle(.flowPrimary).tint(accent)
                } else {
                    Text("请按上方投递方式申请").font(.system(size: 11)).foregroundStyle(muted)
                }
            }.padding(.horizontal, 27).padding(.vertical, 18).background(.white)
        }.background(.white)
    }

    private func tag(_ value: String) -> some View {
        Text(value).font(.system(size: 10, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .foregroundStyle(accent).background(accent.opacity(0.07), in: Capsule())
    }

    private func metadata(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.system(size: 10)).foregroundStyle(muted)
            Text(value.isEmpty ? "未注明" : value).font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 13)).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func useful(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value != "/" && value != "-"
    }

    private func open(_ url: URL) {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return }
        if job.applicationURLs.contains(url) {
            FlowIntent(route: "application", company: job.company, role: job.title, url: url.absoluteString).post()
        } else { onOpenApplication(url, job.company) }
    }
}

private struct LiveJobFacetPicker: View {
    let label: String
    let values: [String]
    @Binding var selection: Set<String>
    @State private var expanded = false
    @State private var search = ""
    private var choices: [String] {
        let all = Array(Set(values).union(selection)).sorted()
        return search.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 5) {
                Text(selection.isEmpty ? label : "\(label) · \(selection.count)").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
        }.accessibilityLabel("筛选" + label).help(selection.sorted().joined(separator: "、"))
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(label).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("清除") { selection = [] }.buttonStyle(.borderless)
                        Button("完成") { expanded = false }.buttonStyle(.borderless)
                    }
                    TextField("搜索" + label, text: $search).textFieldStyle(.flow)
                    Text("同一项可多选，满足任一所选值即可").font(.system(size: 10)).foregroundStyle(muted)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(choices, id: \.self) { value in
                                Toggle(value, isOn: Binding(get: { selection.contains(value) }, set: { selected in
                                    if selected { selection.insert(value) } else { selection.remove(value) }
                                })).toggleStyle(.checkbox).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if choices.isEmpty { Text("没有匹配选项").foregroundStyle(muted).font(.system(size: 12)) }
                        }.padding(.vertical, 4)
                    }
                }.padding(18).frame(width: 300, height: 355)
            }
    }
}

private struct LiveJobFilterPanel: View {
    @Binding var filters: LiveJobFilterState
    let options: [Int: [String]]
    let close: () -> Void
    private let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
    var body: some View {
        FlowSurface {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("筛选招聘信息").font(.system(size: 19, weight: .semibold))
                    Text("不同字段同时满足；同一字段多选时满足任一值。")
                        .font(.system(size: 11)).foregroundStyle(muted)
                }
                Spacer()
                Button("清除全部") { filters = LiveJobFilterState() }.buttonStyle(.borderless)
                Button("完成", action: close).buttonStyle(.flowPrimary).tint(accent)
            }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sectionTitle("招聘范围")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        field(5, "工作地点")
                        field(2, "企业性质")
                        field(3, "行业分类")
                        field(7, "招聘届次")
                        field(8, "学历要求")
                        field(9, "招聘批次")
                        field(15, "笔试安排")
                        field(10, "公告来源")
                        VStack(alignment: .leading, spacing: 7) {
                            Text("收藏").font(.system(size: 11)).foregroundStyle(muted)
                            Toggle("仅看已收藏", isOn: $filters.onlyFavorites).toggleStyle(.checkbox)
                        }
                    }.controlSize(.regular)
                    Divider()
                    sectionTitle("岗位内容")
                    HStack(spacing: 14) {
                        keyword("公司名称", text: $filters.company, prompt: "包含公司名称")
                        keyword("岗位关键词", text: $filters.role, prompt: "例如 AI 产品（模糊匹配）")
                        keyword("专业要求", text: $filters.major, prompt: "例如 计算机")
                    }
                    Divider()
                    sectionTitle("时间范围")
                    HStack(alignment: .top, spacing: 25) {
                        dateRange("信息更新时间", from: $filters.updatedFrom, to: $filters.updatedTo)
                        dateRange("招聘截止时间", from: $filters.deadlineFrom, to: $filters.deadlineTo)
                    }
                    HStack(spacing: 12) {
                        Text("截止状态").font(.system(size: 11)).foregroundStyle(muted)
                        FlowSelect(title: "截止状态", selection: $filters.deadline, options: LiveJobFilterState.Deadline.allCases.map { ($0, $0.rawValue) }).frame(width: 205)
                    }
                    Text("日期范围包含起止当天。“尽快投递”等文字归入“未给出具体日期”，不推断是否仍在招聘。")
                        .font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    if let error = filters.dateError { Text(error).foregroundStyle(.orange).font(.system(size: 11)) }
                    Divider()
                    HStack {
                        sectionTitle("更多筛选条件")
                        Spacer()
                        FlowSelect(title: "条件关系", selection: $filters.matchAnyRule, options: [(false, "满足以下全部条件"), (true, "满足以下任一条件")]).frame(width: 180)
                    }
                    Text("支持岗位库全部 23 个字段，按完整单元格原文筛选。其他筛选项仍需同时满足。")
                        .font(.system(size: 10)).foregroundStyle(muted)
                    ForEach($filters.rules) { $rule in
                        HStack(spacing: 8) {
                            FlowSelect(title: "筛选字段", selection: $rule.field, options: Array(LiveJobParser.expectedHeaders.enumerated()).map { ($0.offset, $0.element) }).frame(width: 160)
                            FlowSelect(title: "匹配方式", selection: $rule.operation, options: LiveJobFieldRule.Operation.allCases.map { ($0, $0.rawValue) }).frame(width: 100)
                            if rule.operation.needsValue {
                                TextField("输入匹配内容", text: $rule.value).textFieldStyle(.flow)
                            } else {
                                Text("无需填写内容").font(.system(size: 11)).foregroundStyle(muted).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button { filters.rules.removeAll { $0.id == rule.id } } label: {
                                Image(systemName: "minus.circle").foregroundStyle(muted)
                            }.buttonStyle(.borderless).accessibilityLabel("移除此字段条件")
                        }
                    }
                    Button("添加字段条件", systemImage: "plus") { filters.rules.append(LiveJobFieldRule()) }
                        .buttonStyle(.borderless).foregroundStyle(accent)
                }.padding(22)
            }
            Divider()
            HStack {
                Text("已启用 \(filters.activeCount) 项筛选").font(.system(size: 11, weight: .medium))
                Spacer()
                Text("修改即时生效，岗位总量不限制").font(.system(size: 10)).foregroundStyle(muted)
            }.padding(.horizontal, 22).padding(.vertical, 14)
        }.frame(width: 740, height: 640).foregroundStyle(ink).background(.white)
    
        }
    }
    private func field(_ index: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(muted)
            LiveJobFacetPicker(label: "全部" + title, values: options[index] ?? [], selection: Binding(
                get: { filters.selected[index] ?? [] }, set: { filters.selected[index] = $0 }))
        }
    }
    private func keyword(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(muted)
            TextField(prompt, text: text).textFieldStyle(.flow)
        }
    }
    private func dateRange(_ title: String, from: Binding<String>, to: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(muted)
            HStack(spacing: 7) {
                TextField("YYYY-MM-DD", text: from).textFieldStyle(.flow).accessibilityLabel(title + "起始日期")
                Text("至").font(.system(size: 11)).foregroundStyle(muted)
                TextField("YYYY-MM-DD", text: to).textFieldStyle(.flow).accessibilityLabel(title + "结束日期")
            }
        }
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.system(size: 13, weight: .semibold)) }
}
