import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en", spanish = "es"
    public static let preferenceKey = "mantisLanguage"
    public var id: String { rawValue }
    public var name: String { self == .english ? "English" : "Español" }
    public var locale: Locale { Locale(identifier: self == .english ? "en_US" : "es_CL") }
    public static func selected(defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .english
    }
}

public enum AppLocalization {
    public static var language: AppLanguage { .selected() }
    public static let english: [String: String] = {
        guard let url = Bundle.main.url(forResource: "English", withExtension: "json") ?? Bundle.module.url(forResource: "English", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }()

    public static func text(_ key: String, language: AppLanguage? = nil) -> String {
        (language ?? self.language) == .spanish ? key : english[key] ?? key
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: language.locale, arguments: arguments)
    }

    public static func byteCount(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file).locale(language.locale))
    }

    /// Localize known application messages, including errors saved by older builds.
    /// Never use this for recording titles, transcripts, paths, or other user content.
    public static func message(_ value: String, language: AppLanguage? = nil) -> String {
        let selected = language ?? self.language
        if let translated = english[value] { return selected == .english ? translated : value }
        if let original = english.first(where: { $0.value == value })?.key { return selected == .spanish ? original : value }
        for entry in templates {
            for source in [entry.source, entry.translation] {
                guard let match = source.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
                let arguments: [String] = (1..<match.numberOfRanges).compactMap { index in
                    Range(match.range(at: index), in: value).map { String(value[$0]) }
                }
                let target = selected == .spanish ? entry.key : entry.value
                let parts = target.replacingOccurrences(of: "%lld", with: "%@").components(separatedBy: "%@")
                guard parts.count == arguments.count + 1 else { continue }
                return arguments.enumerated().reduce(parts[0]) { result, pair in result + pair.element + parts[pair.offset + 1] }
            }
        }
        return value
    }

    private struct Template {
        let key: String, value: String
        let source: NSRegularExpression, translation: NSRegularExpression
    }
    private static let templates: [Template] = english.compactMap { key, value in
        guard key.contains("%@") || key.contains("%lld") else { return nil }
        func expression(_ text: String) -> NSRegularExpression? {
            let escaped = NSRegularExpression.escapedPattern(for: text)
                .replacingOccurrences(of: "%@", with: "(.*?)")
                .replacingOccurrences(of: "%lld", with: "(.*?)")
            return try? NSRegularExpression(pattern: "^" + escaped + "$", options: .dotMatchesLineSeparators)
        }
        guard let source = expression(key), let translation = expression(value) else { return nil }
        return Template(key: key, value: value, source: source, translation: translation)
    }
}
