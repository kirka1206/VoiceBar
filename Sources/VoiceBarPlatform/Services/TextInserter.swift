import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum TextInsertionResult: Equatable, Sendable {
    case pasted
    case clipboardOnly(String)
}

struct TextInserter {
    init() {}

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func insert(_ text: String, intoProcess expectedProcessID: pid_t?) -> TextInsertionResult {
        copyToClipboard(text)

        guard let expectedProcessID else {
            return .clipboardOnly("Текст скопирован: активное приложение при начале диктовки не определилось.")
        }
        guard expectedProcessID != ProcessInfo.processInfo.processIdentifier else {
            return .clipboardOnly("Текст скопирован: VoiceBar активно. Переключитесь в приложение для ввода и запустите диктовку горячей клавишей.")
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedProcessID else {
            return .clipboardOnly("Текст скопирован: активное приложение изменилось во время распознавания.")
        }

        guard CGPreflightPostEventAccess() else {
            return .clipboardOnly("Текст скопирован. Разрешите VoiceBar управлять компьютером в настройках Конфиденциальность и безопасность → Универсальный доступ (в новых версиях macOS — Управление устройством и доступ к данным).")
        }

        // Recheck immediately before posting so Cmd+V never targets a newly focused app.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedProcessID else {
            return .clipboardOnly("Текст скопирован: активное приложение изменилось перед вставкой.")
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return .clipboardOnly("Текст скопирован, но macOS не создала событие Cmd+V.")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(expectedProcessID)
        usleep(35_000)
        keyUp.postToPid(expectedProcessID)
        return .pasted
    }
}
