import AppKit
import VoiceBarCore

@MainActor
final class ForegroundAppTracker {
    private let ownProcessID = ProcessInfo.processInfo.processIdentifier
    private let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
    private var lastExternalProcessID: pid_t?
    private var activationObserver: NSObjectProtocol?

    init() {
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            rememberIfExternal(frontmost)
        }

        activationObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.rememberIfExternal(application)
            }
        }
    }

    func targetProcessIDForRecording() -> pid_t? {
        let frontmostProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let previousProcessID = liveExternalProcessID()
        guard let resolved = RecordingTargetResolver.resolve(
            frontmostProcessID: frontmostProcessID,
            lastExternalProcessID: previousProcessID,
            ownProcessID: ownProcessID
        ) else {
            return nil
        }
        return pid_t(resolved)
    }

    private func rememberIfExternal(_ application: NSRunningApplication) {
        guard application.processIdentifier != ownProcessID, !application.isTerminated else { return }
        lastExternalProcessID = application.processIdentifier
    }

    private func liveExternalProcessID() -> pid_t? {
        guard let lastExternalProcessID,
              lastExternalProcessID != ownProcessID,
              let application = NSRunningApplication(processIdentifier: lastExternalProcessID),
              !application.isTerminated else {
            self.lastExternalProcessID = nil
            return nil
        }
        return lastExternalProcessID
    }

    deinit {
        if let activationObserver {
            workspaceNotificationCenter.removeObserver(activationObserver)
        }
    }
}
