import Carbon.HIToolbox
import Foundation

/// Keeps the keyboard on a Latin layout while the panel is open: app and
/// project names are typed in Latin, so a Russian layout only gets in the way.
final class LatinInput {
    /// What was selected before the panel opened, if it wasn't Latin.
    private var previous: TISInputSource?
    private var observer: NSObjectProtocol?

    /// Switches to the last used ASCII-capable layout and holds it there until `end()`.
    func begin() {
        if observer == nil {
            let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            previous = Self.isLatin(current) ? nil : current
            observer = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                object: nil, queue: .main
            ) { _ in Self.selectLatin() }
        }
        Self.selectLatin()
    }

    /// Stops holding and brings back the layout from before `begin()`.
    func end() {
        guard let observer else { return }
        DistributedNotificationCenter.default().removeObserver(observer)
        self.observer = nil
        if let previous { TISSelectInputSource(previous) }
        previous = nil
    }

    private static func selectLatin() {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard !isLatin(current) else { return }
        TISSelectInputSource(TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue())
    }

    private static func isLatin(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue() == kCFBooleanTrue
    }
}
