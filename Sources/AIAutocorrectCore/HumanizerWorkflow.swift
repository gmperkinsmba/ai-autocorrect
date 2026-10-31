import Foundation

public struct HumanizerResult: Equatable {
    public let text: String
    public let signal: StyleSignal
    public init(text: String, signal: StyleSignal) { self.text = text; self.signal = signal }
}

public enum HumanizerWorkflow {
    public static func rewrite(_ input: String, endpoint: String, model: String, tinySlip: Bool) async throws -> HumanizerResult {
        let (text, signal) = try await LocalModelClient.rewrite(input, baseURL: endpoint, model: model, tinySlip: tinySlip)
        return HumanizerResult(text: text, signal: signal)
    }
}
