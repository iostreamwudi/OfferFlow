import AppKit
import SwiftUI

/// Handle the physical Return key before AppKit translates it into an editing
/// command. While text is marked, the input method must receive it first.
final class CareerChatTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 || event.keyCode == 76, !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if modifiers == .shift {
            insertNewline(nil)
        } else if modifiers.isEmpty, let onSubmit {
            if !event.isARepeat { onSubmit() }
        } else {
            super.keyDown(with: event)
        }
    }
}

struct CareerChatInput: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var submit: () -> Void

    @Binding var editing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = CareerChatTextView.scrollableTextView()
        let editor = scroll.documentView as! CareerChatTextView
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        scroll.drawsBackground = false
        editor.font = .systemFont(ofSize: 14)
        editor.textContainerInset = NSSize(width: 0, height: 3)
        editor.setAccessibilityLabel("对话输入框")
        editor.onSubmit = { [weak coordinator = context.coordinator, weak editor] in
            guard let coordinator, let editor else { return }
            coordinator.parent.text = editor.string
            coordinator.parent.submit()
        }
        editor.delegate = context.coordinator
        editor.string = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
        editor.setAccessibilityHelp(placeholder)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CareerChatInput
        init(_ parent: CareerChatInput) { self.parent = parent }
        func textDidBeginEditing(_ notification: Notification) { parent.editing = true }
        func textDidEndEditing(_ notification: Notification) { parent.editing = false }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
}
