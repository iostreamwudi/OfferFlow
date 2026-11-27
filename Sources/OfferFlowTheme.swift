import SwiftUI

struct FlowButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, primary: primary)
    }
    private struct Face: View {
        let configuration: ButtonStyle.Configuration
        let primary: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label.font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(primary ? Color.white : (configuration.role == .destructive ? Color.red : Color.primary))
                .background(primary ? Color(white: configuration.isPressed ? 0.3 : hovered ? 0.22 : 0.12) : Color(white: configuration.isPressed ? 0.91 : hovered ? 0.95 : 0.99), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? Color.clear : Color.black.opacity(0.12)).allowsHitTesting(false))
                .opacity(enabled ? 1 : 0.4).onHover { hovered = $0 }
        }
    }
}
extension ButtonStyle where Self == FlowButtonStyle {
    static var flowPrimary: FlowButtonStyle { .init(primary: true) }
    static var flowSecondary: FlowButtonStyle { .init() }
}
struct FlowTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).padding(.horizontal, 11).padding(.vertical, 9)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.13)).allowsHitTesting(false))
    }
}
extension TextFieldStyle where Self == FlowTextFieldStyle { static var flow: FlowTextFieldStyle { .init() } }
struct FlowSelect<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var compact = false
    @State private var presented = false
    @State private var query = ""
    private var visible: [Int] { options.indices.filter { query.isEmpty || options[$0].1.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        Button { query = ""; presented = true } label: {
            HStack(spacing: 8) {
                if !compact {
                    Text(options.first { $0.0 == selection }?.1 ?? title).lineLimit(1)
                    Spacer(minLength: 8)
                }
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }.font(.system(size: 13)).padding(.horizontal, compact ? 8 : 11).padding(.vertical, 10)
                .frame(maxWidth: compact ? nil : .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.13)).allowsHitTesting(false))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(options.first { $0.0 == selection }?.1 ?? "未选择")
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if options.count > 10 { TextField("搜索选项", text: $query).textFieldStyle(.flow).padding(4) }
                    if visible.isEmpty { Text("暂无可选项").foregroundStyle(.secondary).padding(12) }
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(visible, id: \.self) { index in
                                Button { selection = options[index].0; presented = false } label: {
                                    HStack(spacing: 10) {
                                        Text(options[index].1).font(.system(size: 13)).lineLimit(3).multilineTextAlignment(.leading)
                                        Spacer(minLength: 10)
                                        if selection == options[index].0 { Image(systemName: "checkmark").font(.system(size: 11, weight: .medium)) }
                                    }.padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selection == options[index].0 ? Color.black.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxHeight: min(CGFloat(max(visible.count, 1)) * 43, 330))
                }.padding(8).frame(width: compact ? 240 : 310).background(.white)
            }
    }
}

/// Sheets establish their own style scope instead of relying on window inheritance.
struct FlowSurface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.font(.system(size: 13)).foregroundStyle(Color(white: 0.15))
            .buttonStyle(.flowSecondary).textFieldStyle(.flow).tint(Color(white: 0.12))
            .background(Color.white)
    }
}
private struct FlowEditorSurface: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.font(.system(size: 13)).lineSpacing(4).scrollContentBackground(.hidden)
            .focused($focused).padding(10)
            .background(Color(white: 0.985), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(focused ? 0.25 : 0.1)).allowsHitTesting(false))
    }
}
extension View {
    func flowEditorSurface() -> some View { modifier(FlowEditorSurface()) }
}
struct FlowSegments<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { index in
                Button { selection = options[index].0 } label: {
                    Text(options[index].1).font(.system(size: 12, weight: selection == options[index].0 ? .semibold : .regular))
                        .foregroundStyle(selection == options[index].0 ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity).padding(.horizontal, 10).padding(.vertical, 8)
                        .background(selection == options[index].0 ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).accessibilityAddTraits(selection == options[index].0 ? .isSelected : [])
            }
        }.padding(3).background(Color(white: 0.955), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct FlowMenuAction {
    let title: String
    var icon = ""
    var enabled = true
    let run: () -> Void
}
struct FlowActionMenu: View {
    let title: String
    var icon = "chevron.down"
    var iconOnly = false
    let actions: [FlowMenuAction]
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 8) {
                if !iconOnly { Text(title) }
                Image(systemName: icon).font(.system(size: iconOnly ? 15 : 10, weight: .medium))
            }
        }.buttonStyle(.browserToolbar).accessibilityLabel(title)
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(actions.indices, id: \.self) { index in
                            Button { presented = false; actions[index].run() } label: {
                                HStack(spacing: 9) {
                                    if !actions[index].icon.isEmpty { Image(systemName: actions[index].icon).frame(width: 17) }
                                    Text(actions[index].title).lineLimit(3).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.browserToolbar).disabled(!actions[index].enabled)
                        }
                    }
                }.frame(width: 260, height: min(CGFloat(actions.count) * 42, 340)).padding(8).background(.white)
            }
    }
}


struct FlowDateTimeField: View {
    let title: String
    @Binding var selection: Date
    @State private var presented = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Button { presented = true } label: {
                HStack {
                    Text(selection.formatted(.dateTime.year().month(.defaultDigits).day().hour().minute()))
                    Spacer(minLength: 8)
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                }.font(.system(size: 13)).padding(11)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.13)))
            }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(selection.formatted())
                .popover(isPresented: $presented) {
                    VStack(alignment: .leading, spacing: 16) {
                        DatePicker(title, selection: $selection, displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden()
                        DatePicker("时间", selection: $selection, displayedComponents: .hourAndMinute)
                        HStack { Spacer(); Button("完成") { presented = false }.buttonStyle(.flowPrimary) }
                    }.padding(16).frame(width: 300).tint(Color(white: 0.12)).background(.white)
                }
        }.frame(maxWidth: .infinity)
    }
}
