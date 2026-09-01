import Carbon
import Foundation

enum HotkeyID: UInt32 {
    case newIdea = 1
    case library = 2
    case board = 3
    case archive = 4
}

final class Hotkeys {
    static let shared = Hotkeys()

    var onNewIdea: (() -> Void)?
    var onLibrary: (() -> Void)?
    var onBoard: (() -> Void)?
    var onArchive: (() -> Void)?

    private var handlerRef: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []

    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            flowKeeperHotkeyCallback,
            1,
            &spec,
            nil,
            &handlerRef
        )
        if status != noErr {
            NSLog("FlowKeeper: hotkey handler failed \(status)")
        }

        register(id: .newIdea, keyCode: UInt32(kVK_ANSI_N))
        register(id: .library, keyCode: UInt32(kVK_ANSI_A))
        register(id: .board, keyCode: UInt32(kVK_ANSI_B))
        register(id: .archive, keyCode: UInt32(kVK_ANSI_L))
    }

    func handle(_ id: UInt32) {
        switch HotkeyID(rawValue: id) {
        case .newIdea: onNewIdea?()
        case .library: onLibrary?()
        case .board: onBoard?()
        case .archive: onArchive?()
        case .none: break
        }
    }

    private func register(id: HotkeyID, keyCode: UInt32) {
        var ref: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: OSType(0x464C4B50), id: id.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            refs.append(ref)
        } else {
            NSLog("FlowKeeper: could not register hotkey \(id) (\(status))")
        }
    }
}

private func flowKeeperHotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    if err == noErr {
        DispatchQueue.main.async {
            Hotkeys.shared.handle(hotKeyID.id)
        }
    }
    return noErr
}
