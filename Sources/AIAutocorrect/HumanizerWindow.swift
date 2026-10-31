import AppKit
import ApplicationServices
import AIAutocorrectCore

final class HumanizerWindow: NSObject {
    private let settingsProvider: () -> AppSettings
    private let saveSettings: (AppSettings) -> Void
    private let corrector: AccessibilityCorrector
    private var window: NSWindow?
    private let input = NSTextView()
    private let output = NSTextView()
    private let endpoint = NSTextField(string: "")
    private let model = NSTextField(string: "")
    private let tinySlip = NSButton(checkboxWithTitle: "Add up to one tiny typo per 250 words", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let score = NSTextField(wrappingLabelWithString: "")
    private let replaceSelectionButton = NSButton(title: "Replace selected text", target: nil, action: nil)
    private var selectedSource: (element: AXUIElement, pid: pid_t, text: String, range: CFRange)?
    private var lastRewrite: String?
    private var requestGeneration = 0

    init(settingsProvider: @escaping () -> AppSettings, saveSettings: @escaping (AppSettings) -> Void,
         corrector: AccessibilityCorrector) {
        self.settingsProvider = settingsProvider; self.saveSettings = saveSettings; self.corrector = corrector
        super.init()
    }

    func show(prefill selection: (element: AXUIElement, pid: pid_t, text: String, range: CFRange)? = nil) {
        requestGeneration += 1
        if window == nil { buildWindow() }
        let settings = settingsProvider()
        endpoint.stringValue = settings.apiBaseURL; model.stringValue = settings.model
        tinySlip.state = settings.tinySlipEnabled ? .on : .off
        selectedSource = selection; replaceSelectionButton.isEnabled = selection != nil
        input.string = selection?.text ?? ""
        output.string = ""; score.stringValue = ""; status.stringValue = ""
        lastRewrite = nil
        window?.center(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 700),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "AI Autocorrect"
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.contentView = makeContent()
        window = w
    }

    private func makeContent() -> NSView {
        let title = NSTextField(labelWithString: "AI Autocorrect")
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Fix typing and rewrite selected text locally without losing your meaning.")
        subtitle.font = .systemFont(ofSize: 13); subtitle.textColor = .secondaryLabelColor

        endpoint.placeholderString = "Local API URL, for example http://127.0.0.1:1234/v1"
        model.placeholderString = "Model name"
        let modelButtons = NSStackView(views: [button("Test connection", #selector(testConnection)), button("Find models", #selector(findModels))])
        modelButtons.orientation = .horizontal; modelButtons.spacing = 8
        let modelRow = NSStackView(views: [endpoint, model, modelButtons])
        modelRow.orientation = .vertical; modelRow.alignment = .leading; modelRow.spacing = 7
        endpoint.widthAnchor.constraint(equalToConstant: 590).isActive = true
        model.widthAnchor.constraint(equalToConstant: 590).isActive = true
        modelButtons.alignment = .leading

        let inputScroll = textScroll(input, height: 150)
        let outputScroll = textScroll(output, height: 175)
        input.font = .systemFont(ofSize: 14); output.font = .systemFont(ofSize: 14)
        input.textColor = .white; output.textColor = .white
        input.isRichText = false; output.isRichText = false; output.isEditable = false
        input.textContainerInset = NSSize(width: 10, height: 10); output.textContainerInset = NSSize(width: 10, height: 10)
        let actions = NSStackView(views: [button("Check writing", #selector(checkWriting)), button("Rewrite", #selector(rewrite)), replaceSelectionButton, button("Copy", #selector(copyOutput))])
        actions.orientation = .horizontal; actions.spacing = 8
        tinySlip.state = .on
        replaceSelectionButton.target = self; replaceSelectionButton.action = #selector(replaceSelection)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        score.font = .systemFont(ofSize: 12); score.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, subtitle, sectionLabel("Local model"), modelRow,
                                       sectionLabel("Text to rewrite"), inputScroll, tinySlip, actions,
                                       sectionLabel("Rewrite"), outputScroll, score, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView(); scroll.documentView = stack; scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -18)
        ])
        return root
    }

    private func textScroll(_ view: NSTextView, height: CGFloat) -> NSScrollView {
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 580, height: CGFloat.greatestFiniteMagnitude)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: height))
        scroll.hasVerticalScroller = true
        scroll.documentView = view
        view.frame = NSRect(x: 0, y: 0, width: 580, height: height)
        view.minSize = NSSize(width: 580, height: height)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.borderType = .bezelBorder; scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 600).isActive = true
        return scroll
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 14, weight: .semibold); return label
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let result = NSButton(title: title, target: self, action: action); result.bezelStyle = .rounded
        return result
    }

    @objc private func testConnection() {
        saveCurrentModelSettings()
        Task { @MainActor in
            do { _ = try await LocalModelClient.models(at: endpoint.stringValue); status.stringValue = "Connected to a local model API." }
            catch { status.stringValue = error.localizedDescription }
        }
    }

    @objc private func findModels() {
        saveCurrentModelSettings()
        Task { @MainActor in
            do {
                let values = try await LocalModelClient.models(at: endpoint.stringValue)
                guard let first = values.first else { status.stringValue = "No models were listed by the local API."; return }
                let alert = NSAlert(); alert.messageText = "Models on this Mac"; alert.informativeText = values.joined(separator: "\n")
                alert.addButton(withTitle: "Use first model"); alert.addButton(withTitle: "Close")
                if alert.runModal() == .alertFirstButtonReturn { model.stringValue = first; saveCurrentModelSettings() }
            } catch { status.stringValue = error.localizedDescription }
        }
    }

    @objc private func rewrite() {
        let original = input.string
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status.stringValue = "Paste or select text to rewrite."; return }
        saveCurrentModelSettings()
        requestGeneration += 1
        let generation = requestGeneration
        let endpointValue = endpoint.stringValue
        let modelValue = model.stringValue
        let tinySlipValue = tinySlip.state == .on
        output.string = ""; score.stringValue = ""; lastRewrite = nil
        replaceSelectionButton.isEnabled = false
        status.stringValue = "Rewriting on this Mac…"
        Task { @MainActor in
            do {
                let result = try await HumanizerWorkflow.rewrite(original, endpoint: endpointValue,
                                                                 model: modelValue,
                                                                 tinySlip: tinySlipValue)
                guard requestGeneration == generation else { return }
                output.string = result.text; lastRewrite = result.text
                replaceSelectionButton.isEnabled = selectedSource != nil
                score.stringValue = scoreText(result.signal)
                status.stringValue = "The rewrite used only the configured local endpoint."
            } catch {
                guard requestGeneration == generation else { return }
                status.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func checkWriting() {
        let text = input.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            requestGeneration += 1
            output.string = ""; score.stringValue = ""; lastRewrite = nil
            replaceSelectionButton.isEnabled = false
            status.stringValue = "Paste or select text to check."
            return
        }
        requestGeneration += 1
        output.string = ""; lastRewrite = nil
        replaceSelectionButton.isEnabled = false
        score.stringValue = scoreText(HumanizerLogic.styleSignal(for: text))
        status.stringValue = "Checked on this Mac. No model request was made."
    }

    private func scoreText(_ signal: StyleSignal) -> String {
        let patterns = signal.matches.isEmpty ? "No listed patterns matched." : "Matched: " + signal.matches.joined(separator: ", ") + "."
        return "AI-style signal: \(signal.score)%. Rule-based estimate, not a probability. \(signal.disclosure) \(patterns)"
    }

    @objc private func replaceSelection() {
        guard let source = selectedSource, let rewrite = lastRewrite else { status.stringValue = "No selected text is ready to replace."; return }
        status.stringValue = "Returning to the source app and checking the selection…"
        Task { @MainActor in
            if await corrector.replaceSelectionIfUnchanged(element: source.element, pid: source.pid,
                                                           original: source.text, range: source.range, replacement: rewrite) {
                status.stringValue = "The selected text was replaced."
                selectedSource = nil; replaceSelectionButton.isEnabled = false
            } else { status.stringValue = "The source app or selection changed. Nothing was replaced." }
        }
    }

    @objc private func copyOutput() {
        guard let lastRewrite else { status.stringValue = "There is no rewrite to copy."; return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lastRewrite, forType: .string)
        status.stringValue = "Copied to the clipboard."
    }

    private func saveCurrentModelSettings() {
        var settings = settingsProvider()
        settings.apiBaseURL = endpoint.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.model = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.tinySlipEnabled = tinySlip.state == .on
        settings = SettingsStore.sanitized(settings)
        saveSettings(settings)
    }
}
