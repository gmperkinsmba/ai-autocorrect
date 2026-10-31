import AppKit
import ApplicationServices
import Foundation
import AIAutocorrectCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings = SettingsStore.load()
    private var statusItem: NSStatusItem!
    private var corrector: AccessibilityCorrector!
    private var humanizer: HumanizerWindow!
    private var settingsWindow: SettingsWindow!
    private let hotKey = HotKeyManager()
    private var latestStatus = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        corrector = AccessibilityCorrector(settings: settings)
        corrector.statusChanged = { [weak self] value in self?.latestStatus = value; self?.refreshMenu() }
        corrector.settingsChanged = { [weak self] value in self?.apply(value) }
        humanizer = HumanizerWindow(settingsProvider: { [weak self] in self?.settings ?? AppSettings() },
                                    saveSettings: { [weak self] in self?.apply($0) }, corrector: corrector)
        settingsWindow = SettingsWindow(settingsProvider: { [weak self] in self?.settings ?? AppSettings() },
                                        saveSettings: { [weak self] in self?.apply($0) })
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Aa"
        statusItem.button?.toolTip = "AI Autocorrect"
        hotKey.action = { [weak self] in self?.humanizeSelection() }
        if !hotKey.register(settings.humanizeHotkey) { latestStatus = "Humanize shortcut unavailable. Choose another shortcut in Settings." }
        corrector.start(); refreshMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func apply(_ settings: AppSettings) {
        self.settings = SettingsStore.sanitized(settings)
        do { try SettingsStore.save(self.settings) }
        catch { latestStatus = "Settings could not be saved." }
        corrector.update(settings: self.settings)
        if !hotKey.register(self.settings.humanizeHotkey) { latestStatus = "Humanize shortcut unavailable. Choose another shortcut in Settings." }
        refreshMenu()
    }

    private func refreshMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        let heading = NSMenuItem(title: "AI Autocorrect", action: nil, keyEquivalent: "")
        heading.isEnabled = false; menu.addItem(heading)
        let state = NSMenuItem(title: settings.enabled ? "Typing correction on" : "Typing correction off",
                               action: #selector(toggleEnabled), keyEquivalent: "")
        state.target = self; state.state = settings.enabled ? .on : .off; menu.addItem(state)
        let pause = NSMenuItem(title: settings.paused ? "Resume corrections" : "Pause corrections",
                               action: #selector(togglePaused), keyEquivalent: "")
        pause.target = self; pause.state = settings.paused ? .on : .off; menu.addItem(pause)
        menu.addItem(.separator())
        let selected = NSMenuItem(title: "Humanize selected text…", action: #selector(humanizeSelection), keyEquivalent: "")
        selected.target = self; menu.addItem(selected)
        let paste = NSMenuItem(title: "Humanize pasted text…", action: #selector(humanizePasted), keyEquivalent: "")
        paste.target = self; menu.addItem(paste)
        let undo = NSMenuItem(title: "Undo last correction", action: #selector(undo), keyEquivalent: "")
        undo.target = self; undo.isEnabled = corrector.canUndo
        menu.addItem(undo)
        let keep = NSMenuItem(title: "Keep last word as written", action: #selector(keepWord), keyEquivalent: "")
        keep.target = self; keep.isEnabled = corrector.canKeepLastWord
        menu.addItem(keep)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self; menu.addItem(settingsItem)
        let permission = NSMenuItem(title: AXIsProcessTrusted() ? "Accessibility access is on" : "Allow Accessibility access…",
                                    action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permission.target = self; permission.isEnabled = !AXIsProcessTrusted(); menu.addItem(permission)
        if !latestStatus.isEmpty {
            let status = NSMenuItem(title: latestStatus, action: nil, keyEquivalent: ""); status.isEnabled = false
            menu.addItem(status)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit AI Autocorrect", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() { var next = settings; next.enabled.toggle(); apply(next) }
    @objc private func togglePaused() { var next = settings; next.paused.toggle(); apply(next); latestStatus = next.paused ? "Corrections paused." : "Corrections resumed."; refreshMenu() }
    @objc private func humanizeSelection() { humanizer.show(prefill: corrector.selectedTextForHumanizing()) }
    @objc private func humanizePasted() { humanizer.show() }
    @objc private func undo() {
        latestStatus = "Returning to the source app and checking the text…"; refreshMenu()
        Task { @MainActor in
            let restored = await corrector.undo()
            latestStatus = restored ? "Restored the exact text." : "The source app or text changed. Nothing was restored."
            refreshMenu()
        }
    }
    @objc private func keepWord() { _ = corrector.keepLastCorrectedWord(); latestStatus = ""; refreshMenu() }
    @objc private func openSettings() { settingsWindow.show() }
    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

@main
enum AIAutocorrectMain {
    static var retainedDelegate: AppDelegate?
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.run()
    }
}
