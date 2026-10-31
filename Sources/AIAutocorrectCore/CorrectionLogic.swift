import AppKit
import Foundation

public struct CorrectionChange: Equatable {
    public let original: String
    public let replacement: String
    public let range: NSRange
    public init(original: String, replacement: String, range: NSRange) {
        self.original = original; self.replacement = replacement; self.range = range
    }
}

public struct GuardedTextUndo: Equatable {
    public let before: String
    public let after: String
    public init(before: String, after: String) { self.before = before; self.after = after }
    public func restoration(for current: String) -> String? { current == after ? before : nil }
}

public enum EditSnapshotGuard {
    public static func canReplace(original: String, current: String, expectedSelection: NSRange,
                           currentSelection: NSRange, focusStillMatches: Bool, role: String,
                           bundleID: String, excluded: Set<String>) -> Bool {
        guard original == current, expectedSelection == currentSelection, focusStillMatches else { return false }
        return CorrectionLogic.supported(role: role, subrole: nil, valueIsSettable: true,
                                         bundleID: bundleID, excluded: excluded)
    }
}

public enum TextRangeGuard {
    public static func isValid(location: Int, length: Int, utf16Length: Int) -> Bool {
        location >= 0 && length >= 0 && location <= utf16Length && length <= utf16Length - location
    }
}

public enum SelectionEditGuard {
    public static func canReplace(field: String, selectedText: String, range: NSRange,
                                  currentSelection: NSRange, focusMatches: Bool,
                                  role: String, bundleID: String, excluded: Set<String>) -> Bool {
        guard TextRangeGuard.isValid(location: range.location, length: range.length,
                                     utf16Length: (field as NSString).length),
              range.length == (selectedText as NSString).length,
              range == currentSelection, focusMatches,
              (field as NSString).substring(with: range) == selectedText else { return false }
        return CorrectionLogic.supported(role: role, subrole: nil, valueIsSettable: true,
                                         bundleID: bundleID, excluded: excluded)
    }
}

public enum CorrectionLogic {
    public static let allowedRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]
    public static let secureRoles: Set<String> = ["AXSecureTextField", "AXPasswordField"]
    public static let builtInCorrections = ["teh": "the", "recieve": "receive", "seperate": "separate", "adress": "address", "occured": "occurred"]

    public static func supported(role: String, subrole: String?, valueIsSettable: Bool, bundleID: String?, excluded: Set<String>) -> Bool {
        guard !secureRoles.contains(role), allowedRoles.contains(role), valueIsSettable else { return false }
        guard let bundleID, !bundleID.isEmpty, !excluded.contains(bundleID) else { return false }
        if let subrole, (subrole.localizedCaseInsensitiveContains("password") || subrole.localizedCaseInsensitiveContains("secure")) { return false }
        return true
    }

    public static func localContext(_ text: String, caret: Int) -> String {
        let ns = text as NSString
        let safeCaret = min(max(0, caret), ns.length)
        let start = max(0, safeCaret - 128)
        let end = min(ns.length, safeCaret + 64)
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    public static func shouldSkip(token: String, context: String) -> Bool {
        let codePattern = #"\b(let|var|const|func|def|class|import|return|select|from)\b|[{}\[\];=]"#
        let hasCode = (try? NSRegularExpression(pattern: codePattern, options: [.caseInsensitive]))?
            .firstMatch(in: context, range: NSRange(context.startIndex..., in: context)) != nil
        guard !token.isEmpty, token.count <= 32,
              token.rangeOfCharacter(from: .decimalDigits) == nil,
              token.rangeOfCharacter(from: CharacterSet(charactersIn: "@:/\\")) == nil,
              !context.contains("/"), !context.contains("@"), !hasCode,
              !context.contains("```"), !context.contains("`"),
              !context.localizedCaseInsensitiveContains("http://"),
              !context.localizedCaseInsensitiveContains("https://"),
              !context.localizedCaseInsensitiveContains("www.") else { return true }
        return false
    }

    public static func boundaryChange(text: String, caret: Int, boundary: String,
                               validWords: Set<String>, corrections: [String: String],
                               contextHint: String) -> CorrectionChange? {
        guard boundary == " " || boundary == "\n" else { return nil }
        let ns = text as NSString
        guard caret > 0, caret <= ns.length,
              ns.substring(with: NSRange(location: caret - 1, length: 1)) == boundary else { return nil }
        var start = caret - 1
        while start > 0 {
            let c = ns.substring(with: NSRange(location: start - 1, length: 1))
            guard c.rangeOfCharacter(from: CharacterSet.letters) != nil || c == "'" || c == "’" || c == "-" else { break }
            start -= 1
        }
        guard start < caret - 1 else { return nil }
        let range = NSRange(location: start, length: caret - 1 - start)
        let token = ns.substring(with: range)
        if start > 0 {
            let previous = ns.substring(with: NSRange(location: start - 1, length: 1))
            if previous.rangeOfCharacter(from: .decimalDigits) != nil || previous == "_" { return nil }
        }
        let key = token.lowercased()
        let context = contextHint + ns.substring(with: NSRange(location: max(0, start - 48), length: min(ns.length, caret) - max(0, start - 48)))
        guard !shouldSkip(token: token, context: context), !validWords.contains(key) else { return nil }
        var replacement = corrections[key] ?? builtInCorrections[key]
        if replacement == nil {
            guard token.first?.isUppercase != true else { return nil }
            let checker = NSSpellChecker.shared
            let tag = NSSpellChecker.uniqueSpellDocumentTag()
            defer { checker.closeSpellDocument(withTag: tag) }
            let tokenRange = NSRange(location: 0, length: (token as NSString).length)
            guard checker.checkSpelling(of: token, startingAt: 0) == tokenRange else { return nil }
            replacement = checker.correction(forWordRange: tokenRange, in: token,
                                             language: checker.language(), inSpellDocumentWithTag: tag)
        }
        guard let candidate = replacement, !candidate.isEmpty, candidate.caseInsensitiveCompare(token) != .orderedSame else { return nil }
        var finalReplacement = candidate
        if token == token.uppercased() { finalReplacement = candidate.uppercased() }
        else if token.first?.isUppercase == true { finalReplacement = candidate.prefix(1).uppercased() + candidate.dropFirst() }
        return CorrectionChange(original: token, replacement: finalReplacement, range: range)
    }
}
