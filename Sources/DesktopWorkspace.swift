import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

// The new workspace hosts bundled UI only. The established BOSS connector stays native.
struct DesktopWorkspace: View {
    @EnvironmentObject var store: Store
    @State private var journeys = Dictionary(uniqueKeysWithValues: WorkspaceTabs.items.map { ($0.id, FlowJourney()) })
    @StateObject private var applicationBrowsers = ApplicationBrowserPool()
    @StateObject private var boss = BossSession()
    @StateObject private var liveJobs = LiveJobsSession()
    @StateObject private var applicationProfile = ApplicationProfileStore()
    @StateObject private var interviews = InterviewStore()
    @StateObject private var interviewBrowser = InterviewBrowser()
    @StateObject private var work = CareerWorkStore()
    @StateObject private var chatHistory = CareerChatStore()
    @AppStorage("workspaceSidebarCollapsed") private var sidebarCollapsed = false
    @State private var applicationDestination: ApplicationDestination?
    @State private var tabs = WorkspaceTabs()
    @State private var chatToDelete: CareerChatHeader?
    @State private var deleteError: String?
    @State private var showSettings = false
    @State private var showAccount = false
    @State private var showAccountMenu = false
    @State private var accountNotice = ""
    @State private var nativePage: String? = "home"
    @State private var activeQueueID: String?
    @State private var showTransfer = false
    @State private var mailDraft: CareerMailDraft?
    @State private var nativeSurfaceHidden = false
    @State private var savedRevision = 0
    @State private var commandRevision = 0
    @State private var commandName = "quickSearch"

    var body: some View {
        ZStack(alignment: .leading) {
            LiveJobsSyncHost(session: liveJobs)
                .frame(width: 1200, height: 800)
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            BundledWorkspace(savedRevision: savedRevision, commandRevision: commandRevision, commandName: commandName, sidebarJSON: chatHistory.sidebarJSON) { action in
                if action.hasPrefix("selectChat:") {
                    let id = String(action.dropFirst("selectChat:".count))
                    if chatHistory.chats.contains(where: { $0.id == id }) { chatHistory.selected = id; openPage("home") }
                    return
                }
                if action.hasPrefix("deleteChat:") {
                    let id = String(action.dropFirst("deleteChat:".count))
                    chatToDelete = chatHistory.chats.first { $0.id == id }
                    return
                }
                switch action {
                case "openBoss": boss.attach(store); activatePage("boss")
                case "openSavedJobs": activatePage("saved")
                case "openApplications": activatePage("applications")
                case "openLiveJobs": activatePage("liveJobs")
                case "openInterviews": activatePage("interviews")
                case "openApplicationProfile": activatePage("profile")
                case "openHome": activatePage("home")
                case "openResumes": activatePage("resumes")
                case "openCoach": activatePage("coach")
                case "openCalendar": activatePage("calendar")
                case "openMail": activatePage("mail")
                case "openMatching": activatePage("matching")
                case "openQueue": activatePage("queue")
                case "openKnowledge": activatePage("knowledge")
                case "openTasks": activatePage("tasks")
                case "openEvents": activatePage("events")
                case "openOffers": activatePage("offers")
                case "collapseSidebar": sidebarCollapsed = true
                case "expandSidebar": sidebarCollapsed = false
                case "suspendNativeSurface": nativeSurfaceHidden = true
                case "showWorkspace": activatePage("home")
                case "openAISettings": showSettings = true
                case "openAccount": accountNotice = ""; showAccount = true
                case "openAccountMenu": showAccountMenu = true
                case "moreChats": chatHistory.showMoreChats()
                case "newChat":
                    chatHistory.startNew(); openPage("home")
                default: break
                }
            }
            VStack(spacing: 0) {
                WorkspaceTabBar(tabs: tabs, bossBusy: boss.batchRunning, select: openPage, close: closePage)
                ZStack {
                    ForEach(tabs.loaded, id: \.self) { page in
                        pageContent(page)
                            .environmentObject(store)
                            .environmentObject(journeys[page]!)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(nativePage == page && !nativeSurfaceHidden ? 1 : 0)
                            .allowsHitTesting(nativePage == page && !nativeSurfaceHidden)
                            .disabled(nativePage != page || nativeSurfaceHidden)
                            .accessibilityHidden(nativePage != page || nativeSurfaceHidden)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
            }
            .padding(.leading, sidebarCollapsed ? 72 : 232)
            .opacity(nativeSurfaceHidden ? 0 : 1)
            .allowsHitTesting(!nativeSurfaceHidden)
            .accessibilityHidden(nativeSurfaceHidden)
        }
        .overlay(alignment: .bottomLeading) {
            Button { showAccountMenu = true } label: {
                Color.clear.frame(width: sidebarCollapsed ? 52 : 204, height: 52).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("账户菜单").padding(14)
                .popover(isPresented: $showAccountMenu, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill").font(.system(size: 28)).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) { Text("个人工作空间").font(.system(size: 13, weight: .medium)); Text("本机账户").font(.system(size: 11)).foregroundStyle(.secondary) }
                        }.padding(10)
                        Divider().padding(.horizontal, 6)
                        accountMenuItem("个人资料", icon: "person.crop.rectangle") { openPage("profile") }
                        accountMenuItem("设置", icon: "gearshape") { commandName = "settings"; commandRevision += 1 }
                        Divider().padding(.horizontal, 6)
                        accountMenuItem("退出登录", icon: "rectangle.portrait.and.arrow.right") {
                            accountNotice = "当前使用本机工作区，没有已登录的云端账号。你可以在此登录，本机资料会保留。"
                            showAccount = true
                        }
                    }.padding(8).frame(width: 220).background(.white)
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowIntent)) { note in
            guard let request = note.object as? FlowIntent else { return }
            handleIntent(request)
        }
        .onChange(of: store.applications) { _, _ in FlowReminders.synchronize(store: store) }
        .onChange(of: store.jobs) { _, _ in FlowReminders.synchronize(store: store) }
        .alert("删除这条对话？", isPresented: Binding(
            get: { chatToDelete != nil }, set: { if !$0 { chatToDelete = nil } }
        ), presenting: chatToDelete) { chat in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    do { try await chatHistory.delete(chat.id) }
                    catch { deleteError = error.localizedDescription }
                }
            }
        } message: { chat in
            Text(chatHistory.replying.contains(chat.id)
                 ? "将停止生成并删除「\(chat.title)」的全部消息。删除后无法撤销。"
                 : "将删除「\(chat.title)」的全部消息。删除后无法撤销。")
        }
        .alert("删除失败", isPresented: Binding(
            get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }
        )) { Button("好") {} } message: { Text(deleteError ?? "") }
        .sheet(isPresented: $showSettings) { AISettingsSheet() }
        .sheet(isPresented: $showAccount) { AccountAccessSheet(notice: accountNotice) }
        .sheet(item: $mailDraft) { CareerMailComposer(store: store, profile: applicationProfile, mail: CareerMailStore.shared, draft: $0) }
        .sheet(isPresented: $showTransfer) { ApplicationTransferView(store: store) }
        .sheet(item: $applicationDestination, onDismiss: {
            if let id = activeQueueID, work.data.queue.first(where: { $0.id == id })?.status == "填写中" { work.setQueue(id, status: "已暂停") }
            activeQueueID = nil
        }) { destination in
            ApplicationBrowserView(url: destination.url, title: destination.title, profileStore: applicationProfile, resumeOverride: destination.resume,
                retainedSession: applicationBrowsers.session(key: destination.jobID ?? destination.url.absoluteString, url: destination.url),
                recordingContext: FlowIntent(route: "application", jobID: destination.jobID, company: destination.company, role: destination.role, url: destination.url.absoluteString),
                onRecordCreated: { id in applicationBrowsers.link(key: id, to: destination.jobID ?? destination.url.absoluteString) },
                onFillState: { filling, completed, error in
                    guard let id = destination.queueID else { return }
                    if filling { work.setQueue(id, status: "填写中") }
                    else if let error { work.setQueue(id, status: "失败", note: error) }
                    else if completed { work.setQueue(id, status: "待核对") }
                    else { work.setQueue(id, status: "已暂停") }
                }).environmentObject(store)
        }
        .onAppear {
            boss.attach(store)
            _ = CareerMailStore.shared
            _ = CareerCalendarStore.shared
            FlowReminders.synchronize(store: store)
            InterviewCoachStore.shared.synchronizeReviews()
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--open-application"), arguments.indices.contains(index + 1),
               let url = URL(string: arguments[index + 1]), url.scheme == "https", url.host != nil,
               url.user == nil, url.password == nil {
                applicationDestination = ApplicationDestination(url: url, title: url.host ?? "网申")
            }
            liveJobs.activate()
            liveJobs.startPeriodicUpdates()
            if store.profile.name == "体验用户",
               let resume = LocalAIStorage.read("resume.json", as: ResumeMaterial.self) {
                store.applyResume(name: resume.name, text: ArkClient.outboundResume(resume.text))
            }
        }
        .onChange(of: store.bossImportRevision) { _, _ in
            openPage("saved")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            liveJobs.foreground()
        }
        .onReceive(NotificationCenter.default.publisher(for: .careerWorkspaceCommand)) { notification in
            guard let command = notification.userInfo?["action"] as? String,
                  ["quickSearch", "settings", "toggleSidebar"].contains(command), !showSettings, !showAccount else { return }
            guard NSApp.modalWindow == nil,
                  !NSApp.windows.contains(where: {
                      $0.attachedSheet != nil || $0.sheetParent != nil || ($0 is NSSavePanel && $0.isVisible)
                  }) else { return }
            commandName = command
            commandRevision += 1
        }
    }

    private func accountMenuItem(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { showAccountMenu = false; action() } label: {
            HStack(spacing: 12) { Image(systemName: icon).font(.system(size: 15)).frame(width: 20); Text(title); Spacer() }
                .font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }

    @ViewBuilder private func pageContent(_ nativePage: String) -> some View {
        Group {
                    if nativePage == "boss" {
                        BossSearchSheet(session: boss, embedded: true, onReturn: { openPage("home") })
                    } else if nativePage == "home" {
                        if chatHistory.selected.isEmpty {
                            if let error = chatHistory.error { Text(error) }
                            else { ProgressView("正在读取对话…") }
                        } else {
                            CareerAssistantView(store: store, profile: applicationProfile, work: work, open: openPage,
                                                history: chatHistory, session: chatHistory.session(for: chatHistory.selected))
                                .id(chatHistory.selected)
                        }
                    } else if nativePage == "tasks" {
                        CareerTaskWorkspace(work: work, store: store, profile: applicationProfile, open: openPage)
                    } else if nativePage == "events" {
                        CareerImportantEventsView(store: store, openMail: { openPage("mail") }, openCalendar: { openPage("calendar") })
                    } else if nativePage == "resumes" {
                        ResumeStudio(profile: applicationProfile, store: store)
                    } else if nativePage == "coach" {
                        InterviewCoachView(interviews: interviews, profile: applicationProfile, store: store)
                    } else if nativePage == "calendar" {
                        CareerCalendarView(store: store, openMail: { openPage("mail") })
                    } else if nativePage == "mail" {
                        CareerMailView(store: store, profile: applicationProfile)
                    } else if nativePage == "matching" {
                        CareerMatchingWorkspace(work: work, store: store, profile: applicationProfile, liveJobs: liveJobs, open: openPage)
                    } else if nativePage == "queue" {
                        CareerApplicationQueue(work: work, store: store) { item, resume in
                            guard let url = LiveJobListing.safeHTTPURL(item.url) else { return }
                            activeQueueID = item.id
                            applicationDestination = ApplicationDestination(url: url, title: "\(item.company) · \(item.role)", queueID: item.id, resume: resume)
                        }
                    } else if nativePage == "knowledge" {
                        CareerKnowledgeView(profile: applicationProfile.profile)
                    } else if nativePage == "offers" {
                        OfferComparisonView(store: store)
                    } else if nativePage == "interviews" {
                        InterviewWorkspace(interviews: interviews, browser: interviewBrowser, profile: applicationProfile) { openPage("profile") }
                    } else if nativePage == "liveJobs" {
                        LiveJobsWorkspace(session: liveJobs, onOpenApplication: { url, title in
                            applicationDestination = ApplicationDestination(url: url, title: title)
                        }, onMail: { listing, address in
                            let existing = store.jobs.first { $0.company == listing.company && $0.title == listing.title }
                            let job = existing ?? Job(listing: listing)
                            if existing == nil { store.add(job) }
                            mailDraft = CareerMailDraft(jobID: job.id, to: address)
                        })
                    } else if nativePage == "profile" {
                        ApplicationProfileView(store: applicationProfile)
                    } else {
                        VStack(spacing: 0) {
                            Workspace(boss: boss, showsSidebar: false, initiallyManaging: nativePage == "applications", onModeChange: { managing in
                                if self.nativePage == nativePage { openPage(managing ? "applications" : "saved") }
                            }, onOpenBoss: { openPage("boss") })
                        }
                    }
        }
    }

    private func handleIntent(_ request: FlowIntent) {
        if request.route == "settings" { showSettings = true; return }
        if request.route == "application" {
            if let id = request.jobID, let job = store.jobs.first(where: { $0.id == id }), let url = job.sourceURL.flatMap(LiveJobListing.safeHTTPURL) {
                applicationDestination = ApplicationDestination(url: url, title: job.company + " · " + job.title, jobID: id)
            } else if let url = request.url.flatMap(LiveJobListing.safeHTTPURL) {
                applicationDestination = ApplicationDestination(url: url, title: request.company ?? url.host ?? "网申", company: request.company, role: request.role)
            }
            return
        }
        guard WorkspaceTabs.items.contains(where: { $0.id == request.route }) else { return }
        if ["applications", "saved"].contains(request.route), let id = request.jobID, store.selected != id { store.selected = id }
        journeys[request.route]?.accept(request)
        openPage(request.route)
    }

    private func activatePage(_ page: String) {
        guard WorkspaceTabs.items.contains(where: { $0.id == page }) else { return }
        if tabs.active != page { tabs.open(page) }
        nativePage = page
        nativeSurfaceHidden = false
    }
    private func openPage(_ page: String) {
        guard WorkspaceTabs.items.contains(where: { $0.id == page }) else { return }
        activatePage(page)
        commandName = page == "interviews" ? "opportunities" : page
        commandRevision += 1
    }
    private func closePage(_ page: String) {
        guard page != "boss" || !boss.batchRunning else { return }
        tabs.close(page)
        if nativePage == page { openPage(tabs.active) }
    }

}

struct BundledWorkspace: NSViewRepresentable {
    var savedRevision: Int
    var commandRevision: Int
    var commandName: String
    var sidebarJSON: String
    var action: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: "careerAI")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        context.coordinator.savedRevision = savedRevision
        context.coordinator.commandRevision = commandRevision
        context.coordinator.sidebarJSON = sidebarJSON
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("Workspace", isDirectory: true) {
            context.coordinator.allowedDirectory = directory.standardizedFileURL
            view.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.action = action
        if context.coordinator.sidebarJSON != sidebarJSON {
            context.coordinator.sidebarJSON = sidebarJSON
            context.coordinator.updateSidebar(view)
        }
        if context.coordinator.savedRevision != savedRevision {
            context.coordinator.savedRevision = savedRevision
            view.evaluateJavaScript("window.location.hash='saved';", completionHandler: nil)
        }
        if context.coordinator.commandRevision != commandRevision {
            context.coordinator.commandRevision = commandRevision
            if ["boss","saved","liveJobs","events","profile","home","tasks","resumes","coach","calendar","mail","matching","queue","knowledge","offers","applications","opportunities"].contains(commandName) { view.evaluateJavaScript("window.location.hash='\(commandName)';", completionHandler: nil); return }
            let command = ["settings", "toggleSidebar"].contains(commandName) ? commandName : "quickSearch"
            view.window?.makeFirstResponder(view)
            view.evaluateJavaScript("window.dispatchEvent(new CustomEvent('careerAI:command',{detail:{action:'\(command)'}}));", completionHandler: nil)
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "careerAI")
        view.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var action: (String) -> Void
        var allowedDirectory: URL?
        var savedRevision = 0
        var commandRevision = 0
        var sidebarJSON = "{}"
        func updateSidebar(_ view: WKWebView) {
            view.evaluateJavaScript("window.offerFlowSidebarUpdate && window.offerFlowSidebarUpdate(\(sidebarJSON));", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { updateSidebar(webView) }
        private let permittedActions = Set(["openBoss", "openSavedJobs", "openApplications", "openLiveJobs", "openApplicationProfile", "openInterviews", "openHome", "openResumes", "openCoach", "openCalendar", "openMail", "openMatching", "openQueue", "openKnowledge", "openTasks", "openOffers", "openEvents", "collapseSidebar", "expandSidebar", "openAccount", "openAccountMenu", "newChat", "moreChats", "showWorkspace", "suspendNativeSurface", "openAISettings", "exportMaterial"])

        init(action: @escaping (String) -> Void) { self.action = action }

        private func isBundled(_ url: URL?) -> Bool {
            guard let url, url.isFileURL, let directory = allowedDirectory else { return false }
            return url.standardizedFileURL.path.hasPrefix(directory.path + "/")
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, isBundled(message.frameInfo.request.url),
                  let payload = message.body as? [String: Any],
                  let requested = payload["action"] as? String,
                  (permittedActions.contains(requested) || ["selectChat:", "deleteChat:"].contains(where: { prefix in
                      requested.hasPrefix(prefix) && UUID(uuidString: String(requested.dropFirst(prefix.count))) != nil
                  })) else { return }
            if requested == "exportMaterial" {
                guard let text = payload["text"] as? String, text.utf8.count <= 1_048_576,
                      let filename = payload["filename"] as? String, filename.count <= 120,
                      !filename.contains("/"), !filename.contains("\\"), filename.hasSuffix(".txt") else { return }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.plainText]
                panel.nameFieldStringValue = filename
                panel.title = "保存示例项目材料"
                let view = message.webView
                panel.begin { [weak view] response in
                    var status = "cancelled"
                    if response == .OK, let destination = panel.url {
                        do { try text.write(to: destination, atomically: true, encoding: .utf8); status = "saved" }
                        catch { status = "failed" }
                    }
                    view?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('careerAI:export',{detail:{status:'\(status)'}}));", completionHandler: nil)
                }
                return
            }
            action(requested)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(isBundled(navigationAction.request.url) ? .allow : .cancel)
        }
    }
}

extension Notification.Name {
    static let careerWorkspaceCommand = Notification.Name("CareerAI.workspaceCommand")
}

private struct ApplicationDestination: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    var jobID: String? = nil
    var company: String? = nil
    var role: String? = nil
    var queueID: String? = nil
    var resume: URL? = nil
}
