import Carbon.HIToolbox
import HopCore

/// A single system-wide hotkey via Carbon — works without Accessibility permission.
final class GlobalHotKey {
    var onPress: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var current: Hotkey?
    private static var handlerInstalled = false
    private static weak var shared: GlobalHotKey?

    init() {
        GlobalHotKey.shared = self
        guard !Self.handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotKey.shared?.onPress?() }
            return noErr
        }, 1, &spec, nil, nil)
        Self.handlerInstalled = true
    }

    /// Replaces any previously registered hotkey. Returns false if the system refused it.
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool {
        if hotkey == current, ref != nil { return true }
        unregister()
        let id = EventHotKeyID(signature: OSType(0x686F_7021), id: 1) // 'hop!'
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { ref = nil; return false }
        current = hotkey
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        current = nil
    }
}
