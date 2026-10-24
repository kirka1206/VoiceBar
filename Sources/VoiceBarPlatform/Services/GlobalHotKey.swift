import Carbon.HIToolbox
import Foundation

final class GlobalHotKey {
    enum Event: Equatable, Sendable {
        case pressed
        case released
    }

    private let action: @MainActor @Sendable (Event) -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    init(action: @escaping @MainActor @Sendable (Event) -> Void) {
        self.action = action
    }

    func register(keyCode: UInt32, modifiers: UInt32) throws {
        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let handlerStatus = eventTypes.withUnsafeBufferPointer { types in
            InstallEventHandler(
                GetApplicationEventTarget(),
                Self.eventHandler,
                types.count,
                types.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerReference
            )
        }
        guard handlerStatus == noErr else { throw GlobalHotKeyError.register(handlerStatus) }

        let identifier = EventHotKeyID(signature: 0x564F4943, id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard hotKeyStatus == noErr else {
            unregister()
            throw GlobalHotKeyError.register(hotKeyStatus)
        }
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    deinit {
        unregister()
    }

    private static let eventHandler: EventHandlerProcPtr = { _, event, context in
        guard let context, let event else { return noErr }
        let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
        let kind = GetEventKind(event)
        let hotKeyEvent: Event
        switch kind {
        case UInt32(kEventHotKeyPressed): hotKeyEvent = .pressed
        case UInt32(kEventHotKeyReleased): hotKeyEvent = .released
        default: return noErr
        }
        Task { @MainActor in
            hotKey.action(hotKeyEvent)
        }
        return noErr
    }
}

enum GlobalHotKeyError: LocalizedError {
    case register(OSStatus)

    var errorDescription: String? {
        switch self {
        case .register(let status): "Не удалось зарегистрировать сочетание клавиш (Carbon: \(status))."
        }
    }
}
