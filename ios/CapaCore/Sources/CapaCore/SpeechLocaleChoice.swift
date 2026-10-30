import Foundation

public enum SpeechLocaleChoice {
    /// Stay in the user's language while selecting an actually installed offline model.
    public static func select(preferred: String, language: String, region: String?, installed: [String]) -> String? {
        func normalized(_ value: String) -> String {
            String(value.split(separator: "@").first ?? "").replacingOccurrences(of: "_", with: "-").lowercased()
        }
        let matches = installed.filter { normalized($0).split(separator: "-").first.map(String.init) == language.lowercased() }
        if let exact = matches.first(where: { normalized($0) == normalized(preferred) }) { return exact }
        if let region, let regional = matches.first(where: { normalized($0) == normalized(language + "-" + region) }) { return regional }
        return matches.sorted().first
    }
}
