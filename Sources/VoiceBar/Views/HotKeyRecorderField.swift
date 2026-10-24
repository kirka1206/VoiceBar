import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotKeyRecorderField: NSViewRepresentable {
    @Binding var isCapturing: Bool
    let onCapture: (Int, Int, String) -> Void

    func makeNSView(context: Context) -> HotKeyCaptureView {
        let view = HotKeyCaptureView()
        view.onBeginCapture = { isCapturing = true }
        view.onCancelCapture = { isCapturing = false }
        view.onCapture = { keyCode, modifiers, keyName in
            onCapture(Int(keyCode), Int(modifiers), keyName)
        }
        return view
    }

    func updateNSView(_ view: HotKeyCaptureView, context: Context) {
        view.onBeginCapture = { isCapturing = true }
        view.onCancelCapture = { isCapturing = false }
        view.onCapture = { keyCode, modifiers, keyName in
            onCapture(Int(keyCode), Int(modifiers), keyName)
        }
        view.isCapturing = isCapturing
    }
}

final class HotKeyCaptureView: NSView {
    var isCapturing = false
    var onBeginCapture: (() -> Void)?
    var onCancelCapture: (() -> Void)?
    var onCapture: ((UInt16, UInt32, String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isCapturing = true
        onBeginCapture?()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            onCancelCapture?()
            window?.makeFirstResponder(nil)
            return
        }

        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        guard carbonModifiers != 0 else {
            NSSound.beep()
            return
        }

        isCapturing = false
        onCapture?(event.keyCode, carbonModifiers, Self.name(for: event))
        window?.makeFirstResponder(nil)
    }

    private static func name(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Пробел"
        case kVK_Return: return "↩"
        case kVK_ANSI_KeypadEnter: return "Enter"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines)
            return characters?.uppercased().nilIfEmpty ?? "Клавиша \(event.keyCode)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
