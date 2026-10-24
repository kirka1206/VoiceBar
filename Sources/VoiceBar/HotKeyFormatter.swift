import Carbon.HIToolbox
import VoiceBarCore

enum HotKeyFormatter {
    static func displayName(modifiers rawModifiers: Int, keyName: String) -> String {
        let modifiers = UInt32(clamping: rawModifiers)
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName)
        return parts.joined()
    }

    static func instruction(mode: DictationHotKeyMode, combination: String) -> String {
        switch mode {
        case .toggle:
            "Нажмите \(combination), чтобы начать диктовку, затем нажмите ещё раз, чтобы остановить."
        case .pushToTalk:
            "Удерживайте \(combination) во время речи. Отпустите сочетание, чтобы остановить диктовку."
        }
    }
}
