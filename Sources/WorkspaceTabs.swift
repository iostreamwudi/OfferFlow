import SwiftUI

struct WorkspaceTabItem: Identifiable {
    let id: String
    let title: String
    let icon: String
}

struct WorkspaceTabs {
    static let items: [WorkspaceTabItem] = [
        .init(id: "home", title: "新对话", icon: "square.grid.2x2"),
        .init(id: "boss", title: "岗位发现 · BOSS", icon: "magnifyingglass"),
        .init(id: "liveJobs", title: "实时岗位库", icon: "tablecells"),
        .init(id: "applications", title: "投递管理", icon: "briefcase"),
        .init(id: "saved", title: "已保存岗位", icon: "bookmark"),
        .init(id: "interviews", title: "面经资料", icon: "text.bubble"),
        .init(id: "coach", title: "面试陪练", icon: "bubble.left.and.bubble.right"),
        .init(id: "calendar", title: "求职日历", icon: "calendar"),
        .init(id: "mail", title: "求职邮箱", icon: "envelope"),
        .init(id: "profile", title: "个人资料", icon: "person.crop.rectangle")
    ]
    private(set) var opened = ["home"]
    // Keep each visited view's identity for this session, including locally edited
    // forms. Switching/closing a tab must not throw away its in-memory draft.
    private(set) var loaded = ["home"]
    private(set) var active = "home"

    mutating func open(_ id: String) {
        guard Self.items.contains(where: { $0.id == id }) else { return }
        if !opened.contains(id) { opened.append(id) }
        if !loaded.contains(id) { loaded.append(id) }
        active = id
    }
    mutating func close(_ id: String) {
        guard id != "home", let index = opened.firstIndex(of: id) else { return }
        opened.remove(at: index)
        // Editing pages keep their drafts; lightweight pages save their state and can be released.
        if ["liveJobs", "calendar", "saved"].contains(id) { loaded.removeAll { $0 == id } }
        if active == id { active = opened[max(0, index - 1)] }
    }
}

struct WorkspaceTabBar: View {
    let tabs: WorkspaceTabs
    var bossBusy: Bool
    var select: (String) -> Void
    var close: (String) -> Void
    private let highlight = Color(white: 0.15)

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(tabs.opened, id: \.self) { id in
                            if let item = WorkspaceTabs.items.first(where: { $0.id == id }) {
                                HStack(spacing: 0) {
                                    Button { select(id) } label: {
                                        Label(item.title, systemImage: item.icon)
                                            .font(.system(size: 13, weight: tabs.active == id ? .semibold : .regular))
                                            .foregroundStyle(tabs.active == id ? Color.primary : Color.secondary)
                                            .padding(.leading, 18).padding(.trailing, 12)
                                            .frame(height: 48).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("切换到" + item.title)
                                    .accessibilityAddTraits(tabs.active == id ? .isSelected : [])
                                    if id != "home" {
                                        Button { close(id) } label: {
                                            Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.secondary).frame(width: 26, height: 32)
                                                .contentShape(Rectangle())
                                        }.buttonStyle(.plain).padding(.trailing, 8)
                                            .accessibilityLabel("关闭" + item.title + "标签页")
                                            .help(id == "boss" && bossBusy ? "投递进行中，停止后可关闭标签" : "关闭标签，保留资料与编辑草稿")
                                            .disabled(id == "boss" && bossBusy)
                                    }
                                }
                                .background(tabs.active == id ? Color.white : Color.clear)
                                .overlay(alignment: .bottom) {
                                    if tabs.active == id { Rectangle().fill(highlight).frame(height: 2) }
                                }
                                .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1, height: 20) }
                                .id(id)
                            }
                        }
                    }
                }
                .onChange(of: tabs.active) { _, id in reader.scrollTo(id, anchor: .center) }
                .onChange(of: tabs.opened) { _, _ in reader.scrollTo(tabs.active, anchor: .center) }
            }
            FlowActionMenu(title: "已打开的标签页", icon: "chevron.down", iconOnly: true,
                actions: tabs.opened.compactMap { id in
                    WorkspaceTabs.items.first(where: { $0.id == id }).map { item in FlowMenuAction(title: item.title, icon: tabs.active == id ? "checkmark" : item.icon) { select(id) } }
                })
            FlowActionMenu(title: "打开功能标签页", icon: "plus", iconOnly: true,
                actions: WorkspaceTabs.items.map { item in FlowMenuAction(title: item.title, icon: tabs.opened.contains(item.id) ? "checkmark" : item.icon) { select(item.id) } })
                .padding(.horizontal, 6)

        }
        .frame(height: 49)
        .background(Color(white: 0.98))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1) }
        .accessibilityElement(children: .contain).accessibilityLabel("已打开的功能标签页")
    }
}
