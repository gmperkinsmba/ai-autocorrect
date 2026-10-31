import Foundation

public struct AppSettings: Codable, Equatable {
    public var enabled = true
    public var paused = false
    public var validWords: [String] = []
    public var corrections: [String: String] = [:]
    public var excludedBundleIDs: [String] = []
    public var apiBaseURL = "http://127.0.0.1:1234/v1"
    public var model = ""
    public var humanizeHotkey = "command+shift+h"
    public var tinySlipEnabled = true
    public init() {}
}

public enum SettingsStore {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AI Autocorrect", isDirectory: true)
    }
    public static var file: URL { directory.appendingPathComponent("settings.json") }

    public static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return sanitized(value)
    }

    public static func save(_ value: AppSettings) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(sanitized(value))
        try data.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    public static func sanitized(_ input: AppSettings) -> AppSettings {
        var value = input
        value.validWords = Array(Set(value.validWords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.range(of: #"^[A-Za-z][A-Za-z'-]{0,39}$"#, options: .regularExpression) != nil })).sorted()
        var clean: [String: String] = [:]
        for (from, to) in value.corrections {
            let key = from.lowercased()
            if key.range(of: #"^[A-Za-z]{1,32}$"#, options: .regularExpression) != nil,
               to.range(of: #"^[A-Za-z]{1,32}$"#, options: .regularExpression) != nil { clean[key] = to }
        }
        value.corrections = clean
        value.excludedBundleIDs = Array(Set(value.excludedBundleIDs.filter { $0.count <= 200 && !$0.isEmpty })).sorted()
        value.model = String(value.model.prefix(160))
        value.humanizeHotkey = String(value.humanizeHotkey.prefix(80))
        if !LocalModelClient.isAllowedBaseURL(value.apiBaseURL) { value.apiBaseURL = AppSettings().apiBaseURL }
        return value
    }
}
