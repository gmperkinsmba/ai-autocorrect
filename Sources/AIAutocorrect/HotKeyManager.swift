import AppKit
import Carbon

final class HotKeyManager {
    var action: (() -> Void)?
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var handlerInstalled = false

    func register(_ value: String) -> Bool {
        unregisterHotKey()
        guard let (keyCode, modifiers) = Self.parse(value) else { return false }
        if !handlerInstalled {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard result == noErr, identifier.signature == 0x41494143 else { return OSStatus(eventNotHandledErr) }
                Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().action?()
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return false }
            handlerInstalled = true
        }
        let identifier = EventHotKeyID(signature: 0x41494143, id: 1)
        return RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    func unregisterHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    }

    deinit {
        unregisterHotKey()
        if let handler { RemoveEventHandler(handler) }
    }

    private static func parse(_ value: String) -> (UInt32, UInt32)? {
        let parts = value.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last, let code = keyCodes[key], parts.count >= 2 else { return nil }
        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "command", "cmd": modifiers |= UInt32(cmdKey)
            case "option", "alt": modifiers |= UInt32(optionKey)
            case "control", "ctrl": modifiers |= UInt32(controlKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: return nil
            }
        }
        guard modifiers != 0 else { return nil }
        return (code, modifiers)
    }

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46
    ]
}
