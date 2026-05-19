import AppKit
import Carbon.HIToolbox

/// Carbon-based global hotkey registration. Hotkeys fire from anywhere on the
/// system, even when Znap isn't the focused app, and — unlike
/// `NSEvent.addGlobalMonitorForEvents` — they do **not** require the user to
/// grant Accessibility permission.
final class HotKeyManager {
    typealias Action = () -> Void

    private var actions: [UInt32: Action] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    init() {
        installEventHandler()
    }

    deinit {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Register a global hotkey. Use Carbon constants — `kVK_ANSI_A` etc. for
    /// keys, and `cmdKey | optionKey | controlKey | shiftKey` for modifiers.
    func register(keyCode: Int, modifiers: Int, action: @escaping Action) {
        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(modifiers),
                                         hkID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr, let ref {
            refs[id] = ref
            actions[id] = action
        }
    }

    fileprivate func dispatch(_ id: UInt32) {
        actions[id]?()
    }

    /// 4-byte signature for our hotkey IDs — "Znap" as a FourCharCode.
    private var signature: OSType {
        var s: OSType = 0
        for b in "Znap".utf8 { s = (s << 8) | OSType(b) }
        return s
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                let s = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if s == noErr { mgr.dispatch(hkID.id) }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}
