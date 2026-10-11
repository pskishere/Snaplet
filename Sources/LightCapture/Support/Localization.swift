import Foundation
import Combine

final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()
    static let supported: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"),
        ("ja", "日本語"), ("ko", "한국어"), ("fr", "Français"),
        ("de", "Deutsch"), ("es", "Español"), ("pt", "Português"),
        ("it", "Italiano"), ("ru", "Русский")
    ]
    static func resolve(_ preferred: [String]) -> String {
        for identifier in preferred {
            let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
            guard let base = parts.first else { continue }
            if base == "zh" {
                if parts.contains("hant") { return "zh-Hant" }
                if parts.contains("hans") { return "zh-Hans" }
                return parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? "zh-Hant" : "zh-Hans"
            }
            if supported.contains(where: { $0.code == base }) { return base }
        }
        return "en"
    }
    @Published var selection: String {
        didSet { UserDefaults.standard.set(selection, forKey: "SnapletLanguage") }
    }
    private init() { selection = UserDefaults.standard.string(forKey: "SnapletLanguage") ?? "system" }
    static var code: String {
        let selected = UserDefaults.standard.string(forKey: "SnapletLanguage") ?? "system"
        if supported.contains(where: { $0.code == selected }) { return selected }
        return resolve(Locale.preferredLanguages)
    }
}
func L(_ key: String, _ arguments: String...) -> String {
    let code = AppLanguage.code
    let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
    let translated = bundle.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? translated : String(format: translated, locale: Locale(identifier: code), arguments: arguments.map { $0 as CVarArg })
}
