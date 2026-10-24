public enum DictationHotKeyMode: String, CaseIterable, Identifiable, Sendable {
    case toggle
    case pushToTalk

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .toggle: "Нажать — начать, нажать ещё раз — остановить"
        case .pushToTalk: "Удерживать для диктовки"
        }
    }
}

public enum DictationHotKeyEvent: Sendable {
    case pressed
    case released
}

public enum DictationHotKeyAction: Equatable, Sendable {
    case none
    case toggle
    case start
    case stop
}

public struct DictationHotKeyStateMachine: Sendable {
    private var isKeyDown = false
    private var heldInPushToTalkMode = false

    public init() {}

    public mutating func handle(
        _ event: DictationHotKeyEvent,
        mode: DictationHotKeyMode
    ) -> DictationHotKeyAction {
        switch event {
        case .pressed:
            guard !isKeyDown else { return .none }
            isKeyDown = true
            guard mode == .pushToTalk else { return .toggle }
            heldInPushToTalkMode = true
            return .start

        case .released:
            isKeyDown = false
            guard heldInPushToTalkMode else { return .none }
            heldInPushToTalkMode = false
            return .stop
        }
    }

    @discardableResult
    public mutating func cancel() -> DictationHotKeyAction {
        let action: DictationHotKeyAction = heldInPushToTalkMode ? .stop : .none
        isKeyDown = false
        heldInPushToTalkMode = false
        return action
    }
}
