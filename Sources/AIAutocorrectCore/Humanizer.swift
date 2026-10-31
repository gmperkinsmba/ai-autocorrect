import Foundation

public struct StyleSignal: Equatable {
    public let score: Int
    public let matches: [String]
    public let disclosure = "This score cannot tell who wrote the text."
    public init(score: Int, matches: [String]) { self.score = score; self.matches = matches }
}

public enum HumanizerLogic {
    public static let prompt = """
    Rewrite only the supplied text. Keep its meaning and the writer's point of view. Keep names, numbers, dates, quoted text, URLs, and code unchanged. Do not add facts. Use direct, natural language with plain words and varied sentence lengths. Remove canned openings, inflated transitions, repeated conclusions, and stock phrases. Keep the writer's tone. Return only the rewrite. Do not claim to identify or evade AI detectors.
    """

    public static func protectedFragments(in text: String) -> [String] {
        let patterns = [
            #"https?://[^\s<>\]\[()]+|www\.[^\s<>\]\[()]+"#,
            #"[$€£]\s?\d+(?:[.,]\d+)*(?:%|st|nd|rd|th)?|\b\d+(?:[.,]\d+)*(?:%|st|nd|rd|th)?\b"#,
            #"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}(?:,\s+\d{4})?\b"#,
            #"`[^`\n]*`|```[\s\S]*?```"#,
            #"“[^”\n]*”|‘[^’\n]*’|"[^"\n]*"|'[^'\n]+'"#,
            #"(?<![.!?]\s)\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,3}\b"#
        ]
        let commonSentenceStarts: Set<String> = ["a", "an", "as", "at", "but", "for", "here", "i", "if", "in", "it", "my", "on", "our", "please", "she", "that", "the", "they", "this", "today", "we", "when", "he", "you"]
        var fragments: Set<String> = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).forEach {
                var value = ns.substring(with: $0.range)
                if pattern == patterns[0] {
                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
                }
                if pattern == patterns[5] {
                    let first = value.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
                    if commonSentenceStarts.contains(first) {
                        value = value.split(separator: " ").dropFirst().joined(separator: " ")
                    }
                }
                if !value.isEmpty { fragments.insert(value) }
            }
        }
        return fragments.sorted()
    }

    public static func preservesProtectedFragments(original: String, rewritten: String) -> Bool {
        return protectedFragments(in: original).allSatisfy { fragment in
            let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: fragment) + #"(?![\p{L}\p{N}_])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: rewritten, range: NSRange(rewritten.startIndex..., in: rewritten)) != nil
        }
    }

    public static func styleSignal(for text: String) -> StyleSignal {
        let checks: [(String, String, Int)] = [
            ("Canned transition", #"\b(moreover|furthermore|in conclusion|it is important to note)\b"#, 16),
            ("Stock wording", #"\b(delves into|delve into|foster|leverage|landscape|tapestry)\b"#, 18),
            ("Repeated phrase", #"\b([A-Za-z]{3,}(?:\s+[A-Za-z]{3,}){0,2})\b(?:[\s\S]{0,240})\b\1\b"#, 20),
            ("Em dash", #"—"#, 10),
            ("Numbered transition", #"\b(firstly|secondly|thirdly|lastly)\b"#, 12)
        ]
        var matches: [String] = []
        var points = 0
        for (label, pattern, weight) in checks {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                matches.append(label); points += weight
            }
        }
        return StyleSignal(score: min(100, points), matches: matches)
    }

    public static func tinySlip(_ text: String, enabled: Bool) -> String {
        guard enabled, !text.contains("```"), !text.contains("http://"),
              !text.contains("https://") else { return text }
        guard let wordRegex = try? NSRegularExpression(pattern: #"\b[\p{L}\p{N}’'-]+\b"#) else { return text }
        let words = wordRegex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        guard words >= 200,
              let regex = try? NSRegularExpression(pattern: #"\b(?:a|the|and|of|to|in|is|for|with|on|at|by|as)\s+[a-z][a-z'-]+\b"#),
              let protectedRegex = try? NSRegularExpression(pattern: #"`[^`]*`|“[^”]*”|‘[^’]*’|"[^"\n]*"|'[^'\n]+'|https?://[^\s]+"#) else { return text }
        let ns = text as NSString
        let blocked = protectedRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
        let candidates = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .filter { candidate in !blocked.contains { NSIntersectionRange($0, candidate.range).length > 0 } }
        let budget = min(max(1, words / 250), candidates.count)
        guard !candidates.isEmpty else { return text }
        var result = text
        for slot in (0..<budget).reversed() {
            let index = min(candidates.count - 1, slot * candidates.count / budget)
            let match = candidates[index]
            // The first whitespace inside this short function-word phrase is the only edit.
            let phrase = ns.substring(with: match.range) as NSString
            let localGap = phrase.rangeOfCharacter(from: .whitespacesAndNewlines).location
            guard localGap != NSNotFound else { continue }
            let absolute = match.range.location + localGap
            result = (result as NSString).replacingCharacters(in: NSRange(location: absolute, length: 1), with: "")
        }
        return result
    }
}
