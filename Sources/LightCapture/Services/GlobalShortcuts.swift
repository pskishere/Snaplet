import Carbon
import Foundation

@MainActor final class GlobalShortcuts {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var action: ((UInt32) -> Void)?
    func register() -> Bool {
        guard handler == nil else { return true }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let identifier = id.id
            let shortcuts = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in shortcuts.action?(identifier) }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        // Control + Option + Command avoids macOS's built-in screenshot combinations.
        for (index, key) in [UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4)].enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key, UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x534E4150, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else { unregister(); return false }
            references.append(ref)
        }
        return true
    }
    func unregister() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
