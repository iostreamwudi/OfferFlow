import Foundation

@main struct WorkspaceTabsTests {
    static func main() {
        var tabs = WorkspaceTabs()
        let removed = ["matching", "offers", "tasks", "knowledge", "queue", "events", "resumes"]
        precondition(removed.allSatisfy { id in !WorkspaceTabs.items.contains { $0.id == id } })
        for id in removed { tabs.open(id) }
        precondition(tabs.opened == ["home"])

        tabs.open("profile")
        tabs.open("boss")
        tabs.open("profile")
        precondition(tabs.opened == ["home", "profile", "boss"])
        precondition(tabs.active == "profile")
        tabs.close("boss")
        precondition(tabs.active == "profile")
        tabs.close("profile")
        precondition(tabs.active == "home")
        precondition(tabs.loaded == ["home", "profile", "boss"])
        tabs.open("profile")
        precondition(tabs.loaded == ["home", "profile", "boss"])
        tabs.close("home")
        precondition(tabs.opened == ["home", "profile"])
        tabs.open("unknown")
        precondition(tabs.active == "profile")
        for item in WorkspaceTabs.items { tabs.open(item.id) }
        precondition(Set(tabs.opened).count == WorkspaceTabs.items.count)
        for item in WorkspaceTabs.items.reversed() { tabs.close(item.id) }
        precondition(tabs.opened == ["home"] && tabs.active == "home")
        print("PASS duplicate opening, active/inactive closing, reopen state retention, pinned home, all feature tabs")
    }
}
