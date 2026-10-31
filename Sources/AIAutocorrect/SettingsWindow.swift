import AppKit
import AIAutocorrectCore

final class SettingsWindow: NSObject {
    private let settingsProvider: () -> AppSettings
    private let saveSettings: (AppSettings) -> Void
    private var window: NSWindow?
    private let keepWord = NSTextField(string: "")
    private let typo = NSTextField(string: "")
    private let replacement = NSTextField(string: "")
    private let excluded = NSTextField(string: "")
    private let hotkey = NSTextField(string: "")
    private let status = NSTextField(wrappingLabelWithString: "")

    init(settingsProvider: @escaping () -> AppSettings, saveSettings: @escaping (AppSettings) -> Void) {
        self.settingsProvider = settingsProvider; self.saveSettings = saveSettings
    }

    func show() {
        if window == nil { build() }
        let settings = settingsProvider()
        hotkey.stringValue = settings.humanizeHotkey
        excluded.stringValue = settings.excludedBundleIDs.joined(separator: ", ")
        status.stringValue = ""
        window?.center(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AI Autocorrect Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "AI Autocorrect")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Keep useful words, set corrections, and choose where typing help is active.")
        subtitle.textColor = .secondaryLabelColor

        let keepButton = button("Keep word", #selector(addKeepWord))
        let typoButton = button("Add correction", #selector(addCorrection))
        let hotkeyButton = button("Save settings", #selector(savePreferences))
        let stack = NSStackView(views: [
            title, subtitle, label("Word to keep as written"), keepWord, keepButton,
            label("Custom correction: typo → replacement"), typo, replacement, typoButton,
            label("Humanize shortcut, such as command+shift+h"), hotkey, hotkeyButton,
            label("Excluded app bundle IDs, separated by commas"), excluded,
            NSTextField(wrappingLabelWithString: "Sensitive fields, unknown text controls, and excluded apps are skipped. Typed text and dictionary data stay on this Mac.")
        ])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        [keepWord, typo, replacement, hotkey, excluded].forEach { $0.widthAnchor.constraint(equalToConstant: 500).isActive = true }
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        stack.addArrangedSubview(status)
        let root = NSView(); root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22)
        ])
        window.contentView = root; self.window = window
    }

    private func label(_ text: String) -> NSTextField {
        let result = NSTextField(labelWithString: text); result.font = .systemFont(ofSize: 13, weight: .medium); return result
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    @objc private func addKeepWord() {
        let word = keepWord.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { status.stringValue = "Enter one word first."; return }
        var settings = settingsProvider(); settings.validWords.append(word)
        saveSettings(settings); keepWord.stringValue = ""; status.stringValue = "Saved to this Mac's keep list."
    }

    @objc private func addCorrection() {
        let from = typo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = replacement.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard from.range(of: #"^[A-Za-z]{1,32}$"#, options: .regularExpression) != nil,
              to.range(of: #"^[A-Za-z]{1,32}$"#, options: .regularExpression) != nil else {
            status.stringValue = "Use one English word on each side of the correction."; return
        }
        var settings = settingsProvider(); settings.corrections[from.lowercased()] = to
        saveSettings(settings); typo.stringValue = ""; replacement.stringValue = ""; status.stringValue = "Saved to this Mac."
    }

    @objc private func savePreferences() {
        var settings = settingsProvider()
        settings.humanizeHotkey = hotkey.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.excludedBundleIDs = excluded.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        saveSettings(settings); status.stringValue = "Settings saved on this Mac."
    }
}
