import AppKit
import ApplicationServices
import Foundation
import AIAutocorrectCore

private struct FieldSnapshot {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let role: String
    let caret: Int
    let leftTail: String
}

private struct UndoRecord {
    let element: AXUIElement
    let pid: pid_t
    let before: String
    let after: String
    let range: NSRange
    let beforeSelection: CFRange
    let correctedWord: String
}

final class AccessibilityCorrector {
    var settingsChanged: ((AppSettings) -> Void)?
    var statusChanged: ((String) -> Void)?
    private var settings: AppSettings
    private var appObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var appActivationToken: NSObjectProtocol?
    private var focusedElement: AXUIElement?
    private var valueObservedElement: AXUIElement?
    private var snapshot: FieldSnapshot?
    private var undoRecord: UndoRecord?
    private var lastCorrectedWord: String?
    private var applyingChange = false
    private let maxFieldLength = 50_000

    var canUndo: Bool { undoRecord != nil }
    var canKeepLastWord: Bool { lastCorrectedWord != nil }

    init(settings: AppSettings) { self.settings = settings }

    func start() {
        appActivationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshApplication() }
        refreshApplication()
    }

    deinit {
        if let appActivationToken { NSWorkspace.shared.notificationCenter.removeObserver(appActivationToken) }
        if let appObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(appObserver), .defaultMode) }
    }

    func update(settings: AppSettings) {
        self.settings = settings
        if !settings.enabled || settings.paused { stopObserving() }
        else { refreshApplication() }
    }

    func undo() async -> Bool {
        guard let record = undoRecord,
              let app = NSRunningApplication(processIdentifier: record.pid),
              valid(record.range, in: record.before),
              valid(record.beforeSelection, in: record.before) else {
            undoRecord = nil; return false
        }
        app.activate(options: [])
        try? await Task.sleep(for: .milliseconds(250))
        guard isFrontmost(record.pid), isFocused(record.element, pid: record.pid),
              let current = read(record.element),
              let restoration = GuardedTextUndo(before: record.before, after: record.after).restoration(for: current.text) else {
            undoRecord = nil; return false
        }
        applyingChange = true
        defer { applyingChange = false; undoRecord = nil }
        let correctedRange = CFRange(location: record.range.location, length: (record.after as NSString).length - (record.before as NSString).length + record.range.length)
        guard valid(correctedRange, in: record.after) else { return false }
        guard isFrontmost(record.pid), isFocused(record.element, pid: record.pid) else { return false }
        setSelection(record.element, correctedRange)
        guard isFrontmost(record.pid), isFocused(record.element, pid: record.pid),
              let rechecked = read(record.element), rechecked.text == current.text,
              let selected = selectionRange(record.element), selected.location == correctedRange.location,
              selected.length == correctedRange.length,
              isFrontmost(record.pid), isFocused(record.element, pid: record.pid),
              AXUIElementSetAttributeValue(record.element, kAXSelectedTextAttribute as CFString, record.correctedWord as CFTypeRef) == .success,
              read(record.element)?.text == restoration else { return false }
        setSelection(record.element, record.beforeSelection)
        lastCorrectedWord = nil
        statusChanged?("Restored the exact text. The undo copy stays in memory only until the next edit or quit.")
        if observedPID == record.pid { refreshSnapshot(for: record.element) } else { snapshot = nil }
        return true
    }

    func keepLastCorrectedWord() -> Bool {
        guard let word = lastCorrectedWord else { return false }
        var next = settings
        next.validWords.append(word.lowercased())
        next = SettingsStore.sanitized(next)
        do {
            try SettingsStore.save(next)
            settings = next; settingsChanged?(next); lastCorrectedWord = nil
            statusChanged?("Added the word to your local keep list.")
            return true
        } catch { statusChanged?("Could not save the keep list."); return false }
    }

    func selectedTextForHumanizing() -> (element: AXUIElement, pid: pid_t, text: String, range: CFRange)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        guard
              roleAllowed(element), let current = read(element),
              let range = selectionRange(element), valid(range, in: current.text), range.length > 0 else { return nil }
        let text = (current.text as NSString).substring(with: NSRange(location: range.location, length: range.length))
        guard text.utf8.count <= 32_000 else { return nil }
        return (element, pid, text, range)
    }

    func replaceSelectionIfUnchanged(element: AXUIElement, pid: pid_t, original: String, range: CFRange, replacement: String) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), range.location >= 0,
              range.length == (original as NSString).length else { return false }
        app.activate(options: [])
        try? await Task.sleep(for: .milliseconds(250))
        guard isFrontmost(pid), isFocused(element, pid: pid), let current = read(element),
              valid(range, in: current.text),
              (current.text as NSString).length + (replacement as NSString).length <= maxFieldLength,
              let currentRange = selectionRange(element), valid(currentRange, in: current.text),
              currentRange.location == range.location,
              currentRange.length == range.length,
              (current.text as NSString).substring(with: NSRange(location: range.location, length: range.length)) == original,
              let role = role(element), let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
              SelectionEditGuard.canReplace(field: current.text, selectedText: original,
                                            range: NSRange(location: range.location, length: range.length),
                                            currentSelection: NSRange(location: currentRange.location, length: currentRange.length),
                                            focusMatches: isFocused(element, pid: pid), role: role,
                                            bundleID: bundleID, excluded: Set(settings.excludedBundleIDs)) else { return false }
        var updatedRange = range
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                           AXValueCreate(.cfRange, &updatedRange)!) == .success else { return false }
        guard isFrontmost(pid), isFocused(element, pid: pid), let rechecked = read(element), rechecked.text == current.text,
              let recheckedRange = selectionRange(element), recheckedRange.location == range.location,
              recheckedRange.length == range.length else { return false }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFTypeRef) == .success else { return false }
        let expected = (current.text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: replacement)
        return read(element)?.text == expected
    }

    private func refreshApplication() {
        guard AXIsProcessTrusted() else { stopObserving(); statusChanged?("Allow Accessibility in System Settings to enable typing correction."); return }
        guard settings.enabled, !settings.paused,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier,
              !settings.excludedBundleIDs.contains(bundleID) else { stopObserving(); return }
        let pid = app.processIdentifier
        guard pid != observedPID else { refreshFocusedElement(); return }
        stopObserving(); observedPID = pid
        var observer: AXObserver?
        let error = AXObserverCreate(pid, accessibilityCallback, &observer)
        guard error == .success, let observer else { stopObserving(); return }
        appObserver = observer
        let appElement = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        refreshFocusedElement()
    }

    fileprivate func receiveAXNotification(_ element: AXUIElement, _ notification: String) {
        guard AXIsProcessTrusted(), settings.enabled, !settings.paused,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == observedPID else { stopObserving(); return }
        if notification == kAXFocusedUIElementChangedNotification as String { refreshFocusedElement(); return }
        guard notification == kAXValueChangedNotification as String, !applyingChange else { return }
        handleValueChange(element)
    }

    private func refreshFocusedElement() {
        guard observedPID != 0, let appObserver else { return }
        let app = AXUIElementCreateApplication(observedPID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let rawElement = value else { focusedElement = nil; snapshot = nil; return }
        let element = rawElement as! AXUIElement
        focusedElement = element
        if let valueObservedElement, !CFEqual(valueObservedElement, element) {
            AXObserverRemoveNotification(appObserver, valueObservedElement, kAXValueChangedNotification as CFString)
        }
        valueObservedElement = element
        AXObserverAddNotification(appObserver, element, kAXValueChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        refreshSnapshot(for: element)
    }

    private func handleValueChange(_ element: AXUIElement) {
        guard roleAllowed(element), let current = read(element), current.text.utf16.count <= maxFieldLength else {
            if let undoRecord, CFEqual(undoRecord.element, element) { self.undoRecord = nil; lastCorrectedWord = nil }
            return
        }
        if let undoRecord, CFEqual(undoRecord.element, element), current.text != undoRecord.after {
            self.undoRecord = nil; lastCorrectedWord = nil
        }
        guard isFocused(element, pid: observedPID), let selection = selectionRange(element), valid(selection, in: current.text),
              selection.length == 0 else { refreshSnapshot(for: element); return }
        guard selection.location > 0,
              let previous = snapshot, CFEqual(previous.element, element), previous.pid == observedPID,
              selection.location == previous.caret + 1 else { refreshSnapshot(for: element); return }
        let ns = current.text as NSString
        guard selection.location <= ns.length else { refreshSnapshot(for: element); return }
        let boundary = ns.substring(with: NSRange(location: selection.location - 1, length: 1))
        guard boundary == " " || boundary == "\n" else { refreshSnapshot(for: element); return }
        let beforeBoundary = ns.substring(to: selection.location - 1)
        let currentTail = String((beforeBoundary as NSString).substring(from: max(0, (beforeBoundary as NSString).length - previous.leftTail.utf16.count)))
        guard currentTail == previous.leftTail else { refreshSnapshot(for: element); return }
        snapshot = makeSnapshot(element, text: current.text, caret: selection.location, bundleID: previous.bundleID, role: previous.role)
        guard settings.enabled, !settings.paused,
              !sensitiveTitle(element),
              let bundleID = NSRunningApplication(processIdentifier: observedPID)?.bundleIdentifier,
              !settings.excludedBundleIDs.contains(bundleID) else { return }
        let valid = Set(settings.validWords.map { $0.lowercased() })
        if let change = CorrectionLogic.boundaryChange(text: current.text, caret: selection.location,
                                                       boundary: boundary, validWords: valid,
                                                       corrections: settings.corrections,
                                                       contextHint: CorrectionLogic.localContext(current.text, caret: selection.location)) {
            apply(change, to: element, pid: observedPID, current: current.text, selection: selection)
        }
    }

    private func apply(_ change: CorrectionChange, to element: AXUIElement, pid: pid_t,
                       current text: String, selection: CFRange) {
        let ns = text as NSString
        let expected = ns.replacingCharacters(in: change.range, with: change.replacement)
        guard expected.utf16.count <= maxFieldLength,
              isFocused(element, pid: pid), let check = read(element), check.text == text,
              let checkSelection = selectionRange(element), checkSelection.location == selection.location,
              checkSelection.length == 0, let role = role(element),
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
              EditSnapshotGuard.canReplace(original: text, current: check.text,
                                           expectedSelection: NSRange(location: selection.location, length: 0),
                                           currentSelection: NSRange(location: checkSelection.location, length: checkSelection.length),
                                           focusStillMatches: isFocused(element, pid: pid), role: role,
                                           bundleID: bundleID, excluded: Set(settings.excludedBundleIDs)) else { return }
        applyingChange = true
        defer { applyingChange = false }
        setSelection(element, CFRange(location: change.range.location, length: change.range.length))
        guard isFocused(element, pid: pid), let selected = read(element), selected.text == text,
              let selectedRange = selectionRange(element), selectedRange.location == change.range.location,
              selectedRange.length == change.range.length,
              EditSnapshotGuard.canReplace(original: text, current: selected.text,
                                           expectedSelection: change.range,
                                           currentSelection: NSRange(location: selectedRange.location, length: selectedRange.length),
                                           focusStillMatches: isFocused(element, pid: pid), role: role,
                                           bundleID: bundleID, excluded: Set(settings.excludedBundleIDs)),
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, change.replacement as CFTypeRef) == .success else {
            statusChanged?("This text field did not allow a safe correction."); refreshSnapshot(for: element); return
        }
        guard isFrontmost(pid), isFocused(element, pid: pid), let afterEdit = read(element), afterEdit.text == expected else {
            statusChanged?("The text changed during correction. No further edit was made."); undoRecord = nil; refreshSnapshot(for: element); return
        }
        let nextSelection = CFRange(location: selection.location + change.replacement.utf16.count - change.original.utf16.count, length: 0)
        guard valid(nextSelection, in: expected) else { undoRecord = nil; return }
        setSelection(element, nextSelection)
        undoRecord = UndoRecord(element: element, pid: pid, before: text, after: expected,
                                range: change.range, beforeSelection: selection, correctedWord: change.original)
        lastCorrectedWord = change.original
        statusChanged?("\(change.original) → \(change.replacement). Undo is available in the menu.")
        snapshot = makeSnapshot(element, text: expected, caret: nextSelection.location,
                                bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "", role: "")
    }

    private func refreshSnapshot(for element: AXUIElement) {
        guard roleAllowed(element), let current = read(element), let range = selectionRange(element),
              valid(range, in: current.text), range.length == 0,
              let bundleID = NSRunningApplication(processIdentifier: observedPID)?.bundleIdentifier,
              let role = role(element) else { snapshot = nil; return }
        snapshot = makeSnapshot(element, text: current.text, caret: range.location, bundleID: bundleID, role: role)
    }

    private func makeSnapshot(_ element: AXUIElement, text: String, caret: Int, bundleID: String, role: String) -> FieldSnapshot {
        let ns = text as NSString
        let safeCaret = min(max(0, caret), ns.length)
        let prefix = ns.substring(to: safeCaret) as NSString
        return FieldSnapshot(element: element, pid: observedPID, bundleID: bundleID, role: role,
                             caret: caret, leftTail: prefix.substring(from: max(0, prefix.length - 64)))
    }

    private func role(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func roleAllowed(_ element: AXUIElement) -> Bool {
        guard let role = role(element), !sensitiveTitle(element) else { return false }
        var subroleValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
        var settable = DarwinBoolean(false)
        let canSet = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        var pid: pid_t = 0; AXUIElementGetPid(element, &pid)
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        return CorrectionLogic.supported(role: role, subrole: subroleValue as? String,
                                         valueIsSettable: canSet, bundleID: bundleID,
                                         excluded: Set(settings.excludedBundleIDs))
    }

    private func sensitiveTitle(_ element: AXUIElement) -> Bool {
        for attribute in [kAXTitleAttribute, kAXPlaceholderValueAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let text = value as? String else { continue }
            let lower = text.lowercased()
            if ["password", "passcode", "secret", "token", "credential", "username", "user name", "email", "e-mail", "login", "account number", "security code", "one-time code", "verification code", "pin", "ssn"].contains(where: lower.contains) { return true }
        }
        return false
    }

    private func read(_ element: AXUIElement) -> (text: String, range: CFRange?)? {
        guard roleAllowed(element) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, text.utf16.count <= maxFieldLength else { return nil }
        return (text, selectionRange(element))
    }

    private func selectionRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private func setSelection(_ element: AXUIElement, _ range: CFRange) {
        var value = range
        if let axValue = AXValueCreate(.cfRange, &value) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axValue)
        }
    }

    private func isFocused(_ element: AXUIElement, pid: pid_t) -> Bool {
        guard isFrontmost(pid) else { return false }
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let rawCurrent = value else { return false }
        let current = rawCurrent as! AXUIElement
        return CFEqual(current, element)
    }

    private func isFrontmost(_ pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    private func valid(_ range: CFRange, in text: String) -> Bool {
        let length = (text as NSString).length
        return TextRangeGuard.isValid(location: range.location, length: range.length, utf16Length: length)
    }

    private func valid(_ range: NSRange, in text: String) -> Bool {
        TextRangeGuard.isValid(location: range.location, length: range.length, utf16Length: (text as NSString).length)
    }

    private func stopObserving() {
        if let appObserver {
            if let valueObservedElement {
                AXObserverRemoveNotification(appObserver, valueObservedElement, kAXValueChangedNotification as CFString)
            }
            AXObserverRemoveNotification(appObserver, AXUIElementCreateApplication(observedPID), kAXFocusedUIElementChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(appObserver), .defaultMode)
        }
        appObserver = nil; valueObservedElement = nil; observedPID = 0
        focusedElement = nil; snapshot = nil
    }
}

private func accessibilityCallback(_ observer: AXObserver, _ element: AXUIElement,
                                   _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let monitor = Unmanaged<AccessibilityCorrector>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async { monitor.receiveAXNotification(element, notification as String) }
}
