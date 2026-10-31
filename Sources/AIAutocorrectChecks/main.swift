import AIAutocorrectCore
import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main enum AIBehaviorChecks {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(description: message) }
    }

    static func main() async {
        do {
            try correctionBoundary()
            try rangeBounds()
            try offsetSelectionReplacement()
            try namesAndKeepList()
            try secureAndUnknownControls()
            try protectedContexts()
            try editRaceAndUndo()
            try localEndpointPolicy()
            try humanizerPreservation()
            try tinySlipBounds()
            try transparentStyleScore()
            try await actualModelIfConfigured()
            print("ALL AI AUTOCORRECT CHECKS PASSED")
        } catch {
            fputs("AI AUTOCORRECT CHECK FAILED: \(error)\n", stderr)
            exit(1)
        }
    }

    static func correctionBoundary() throws {
        let text = "I recieved "
        guard let change = CorrectionLogic.boundaryChange(text: text, caret: text.utf16.count, boundary: " ",
                                                          validWords: [], corrections: ["recieved": "received"], contextHint: "") else {
            throw CheckFailure(description: "explicit typo correction was not produced")
        }
        try expect((text as NSString).replacingCharacters(in: change.range, with: change.replacement) == "I received ", "boundary correction changed wrong text")
        let builtIn = CorrectionLogic.boundaryChange(text: "The adress ", caret: 11, boundary: " ", validWords: [], corrections: [:], contextHint: "")
        try expect(builtIn?.replacement == "address", "built-in typo was not corrected")
        print("PASS typed-boundary custom correction")
    }

    static func namesAndKeepList() throws {
        try expect(CorrectionLogic.boundaryChange(text: "Teh ", caret: 4, boundary: " ", validWords: ["teh"], corrections: [:], contextHint: "") == nil, "kept word changed")
        try expect(CorrectionLogic.boundaryChange(text: "Grant ", caret: 6, boundary: " ", validWords: [], corrections: [:], contextHint: "") == nil, "capitalized name changed")
        print("PASS keep list and proper-name guard")
    }

    static func rangeBounds() throws {
        try expect(TextRangeGuard.isValid(location: 2, length: 3, utf16Length: 5), "valid UTF-16 range rejected")
        try expect(!TextRangeGuard.isValid(location: -1, length: 1, utf16Length: 5), "negative range accepted")
        try expect(!TextRangeGuard.isValid(location: 4, length: 2, utf16Length: 5), "out-of-bounds range accepted")
        print("PASS bounded UTF-16 selections")
    }

    static func offsetSelectionReplacement() throws {
        let field = "prefix hello suffix"
        let range = NSRange(location: 7, length: 5)
        try expect(SelectionEditGuard.canReplace(field: field, selectedText: "hello", range: range,
                                                 currentSelection: range, focusMatches: true,
                                                 role: "AXTextArea", bundleID: "editor", excluded: []),
                   "valid nonzero-offset selection rejected")
        let replaced = (field as NSString).replacingCharacters(in: range, with: "world")
        try expect(replaced == "prefix world suffix", "replacement changed surrounding text")
        try expect(!SelectionEditGuard.canReplace(field: field, selectedText: "hello", range: range,
                                                  currentSelection: NSRange(location: 0, length: 5), focusMatches: true,
                                                  role: "AXTextArea", bundleID: "editor", excluded: []),
                   "stale selection accepted")
        print("PASS nonzero-offset selected-text replacement guard")
    }

    static func secureAndUnknownControls() throws {
        try expect(!CorrectionLogic.supported(role: "AXSecureTextField", subrole: nil, valueIsSettable: true, bundleID: "editor", excluded: []), "secure field accepted")
        try expect(!CorrectionLogic.supported(role: "AXUnknown", subrole: nil, valueIsSettable: true, bundleID: "editor", excluded: []), "unknown role accepted")
        try expect(!CorrectionLogic.supported(role: "AXTextField", subrole: nil, valueIsSettable: true, bundleID: "editor", excluded: ["editor"]), "excluded app accepted")
        print("PASS secure, unknown, and excluded controls")
    }

    static func protectedContexts() throws {
        for (text, context, caret) in [
            ("https://example.com/teh ", "https://example.com/teh ", 24),
            ("`teh` ", "`teh` ", 6),
            ("12345 ", "12345 ", 6)
        ] {
            try expect(CorrectionLogic.boundaryChange(text: text, caret: caret, boundary: " ", validWords: [], corrections: ["teh": "the"], contextHint: context) == nil, "protected text changed: \(text)")
        }
        for (text, correction) in [("let teh ", ["teh": "the"]), ("teh@example.com ", ["com": "company"]), ("name123teh ", ["teh": "the"])] {
            try expect(CorrectionLogic.boundaryChange(text: text, caret: text.utf16.count, boundary: " ", validWords: [], corrections: correction, contextHint: text) == nil, "code, email, or identifier changed: \(text)")
        }
        print("PASS URL, code, and number guards")
    }

    static func editRaceAndUndo() throws {
        let range = NSRange(location: 4, length: 3)
        try expect(EditSnapshotGuard.canReplace(original: "say teh", current: "say teh", expectedSelection: range, currentSelection: range, focusStillMatches: true, role: "AXTextArea", bundleID: "editor", excluded: []), "valid selection rejected")
        try expect(!EditSnapshotGuard.canReplace(original: "say teh", current: "say the", expectedSelection: range, currentSelection: range, focusStillMatches: true, role: "AXTextArea", bundleID: "editor", excluded: []), "text race accepted")
        try expect(!EditSnapshotGuard.canReplace(original: "say teh", current: "say teh", expectedSelection: range, currentSelection: NSRange(location: 5, length: 2), focusStillMatches: true, role: "AXTextArea", bundleID: "editor", excluded: []), "selection race accepted")
        try expect(!EditSnapshotGuard.canReplace(original: "say teh", current: "say teh", expectedSelection: range, currentSelection: range, focusStillMatches: false, role: "AXTextArea", bundleID: "editor", excluded: []), "focus race accepted")
        let undo = GuardedTextUndo(before: "I recieved ", after: "I received ")
        try expect(undo.restoration(for: "I received ") == "I recieved ", "exact undo failed")
        try expect(undo.restoration(for: "I received more") == nil, "undo overwrote later text")
        print("PASS stale text, selection, focus, and guarded undo")
    }

    static func localEndpointPolicy() throws {
        try expect(LocalModelClient.isAllowedBaseURL("http://127.0.0.1:1234/v1"), "loopback endpoint rejected")
        try expect(LocalModelClient.isAllowedBaseURL("http://localhost:8080/v1"), "localhost endpoint rejected")
        try expect(!LocalModelClient.isAllowedBaseURL("https://api.example.com/v1"), "remote endpoint accepted")
        try expect(!LocalModelClient.isAllowedBaseURL("http://user:secret@127.0.0.1:1234/v1"), "credential URL accepted")
        try expect(!LocalModelClient.isAllowedBaseURL("http://127.0.0.1:1234/v1?token=x"), "query-token URL accepted")
        print("PASS local-only model endpoint policy")
    }

    static func humanizerPreservation() throws {
        let text = "On October 31, 2026, Maya Chen wrote \"Keep 4 boxes\" at https://example.com and ran `ship --fast`."
        let fragments = HumanizerLogic.protectedFragments(in: text)
        for value in ["31", "2026", "Maya Chen", "\"Keep 4 boxes\"", "https://example.com", "`ship --fast`"] {
            try expect(fragments.contains(value), "protected fragment missing: \(value)")
        }
        try expect(HumanizerLogic.preservesProtectedFragments(original: text, rewritten: text + " Review it."), "valid preservation failed")
        let changed = text.replacingOccurrences(of: "Maya Chen", with: "Maya Chenn")
        try expect(!HumanizerLogic.preservesProtectedFragments(original: text, rewritten: changed), "changed name accepted")
        let modelInput = "Maya Chen needs a decision by October 31, 2026, about 4 boxes at https://example.com."
        let modelOutput = "Maya Chen needs a decision by October 31, 2026, regarding 4 boxes at [example.com]."
        try expect(!HumanizerLogic.preservesProtectedFragments(original: modelInput, rewritten: modelOutput), "model's changed URL was accepted")
        print("PASS protected names, numbers, quotes, code, and URLs")
    }

    static func tinySlipBounds() throws {
        let paragraph = Array(repeating: "the clear result supports a useful decision today", count: 50).joined(separator: " ")
        try expect(HumanizerLogic.tinySlip(paragraph, enabled: false) == paragraph, "disabled tiny slip changed text")
        let changed = HumanizerLogic.tinySlip(paragraph, enabled: true)
        try expect(changed != paragraph && paragraph.count - changed.count == 1, "300-word text did not get exactly one missing-space slip")
        let short = Array(repeating: "the clear result supports a useful decision today", count: 20).joined(separator: " ")
        try expect(HumanizerLogic.tinySlip(short, enabled: true) == short, "short text got a tiny slip")
        print("PASS optional tiny-slip frequency bounds")
    }

    static func transparentStyleScore() throws {
        let signal = HumanizerLogic.styleSignal(for: "Moreover, this approach delves into a broader landscape.")
        try expect(signal.score > 0 && !signal.matches.isEmpty && signal.score <= 100, "style patterns were not reported")
        try expect(signal.disclosure == "This score cannot tell who wrote the text.", "authorship disclosure missing")
        print("PASS non-probability style signal and reasons")
    }

    static func actualModelIfConfigured() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["AI_AUTOCORRECT_TEST_API"],
              let model = ProcessInfo.processInfo.environment["AI_AUTOCORRECT_TEST_MODEL"] else {
            print("SKIP actual model check: test API not configured")
            return
        }
        let input = "I wanted to let you know that I would appreciate your help when we review the next draft because the opening is unclear and the ending repeats the same point."
        let models = try await LocalModelClient.models(at: endpoint)
        try expect(models.contains(model), "local model discovery did not return selected model")
        print("PASS real local model discovery")
        let result = try await HumanizerWorkflow.rewrite(input, endpoint: endpoint, model: model, tinySlip: false)
        try expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "model returned empty text")
        try expect(result.text != input, "model did not rewrite synthetic pasted text")
        print("LOCAL_MODEL_SYNTHETIC_REWRITE=\(result.text)")
        print("PASS actual local Qwen API request and response")
    }
}
