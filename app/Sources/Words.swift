import Foundation

// What a person reads, in the Mac's language. The English text is the key:
// app/Resources/<language>.lproj/Localizable.strings says it in the others,
// and a line missing there stays English. The `wham` command, the journal and
// the tests speak English only (`english`); the evals launch the app in English.
enum Words {
    static var english = false

    static func say(_ text: String, _ args: CVarArg...) -> String { say(text, arguments: args) }

    static func say(_ text: String, arguments args: [CVarArg], english: Bool = Words.english) -> String {
        let format = english ? text : Bundle.main.localizedString(forKey: text, value: text, table: nil)
        return args.isEmpty ? format : String(format: format, locale: locale(english: english), arguments: args)
    }

    // Dates as the Mac writes them. macOS gives the app a locale in the
    // language it speaks, with the Mac's region ("ja_FR"); in English, the
    // region's English ("en_FR": "Wed 12:58"), whatever the Mac speaks.
    static var locale: Locale { locale(english: english) }

    private static func locale(english: Bool) -> Locale {
        let current = Locale.current as NSLocale
        guard english, current.languageCode != "en" else { return .current }
        return Locale(identifier: "en_" + (current.countryCode ?? "US"))
    }

    // "20%", or "20 %" in French and German: as the language writes it.
    static func percent(_ value: Int) -> String {
        let format = NumberFormatter()
        format.numberStyle = .percent
        format.locale = Locale(identifier: language)
        return format.string(from: NSNumber(value: Double(value) / 100)) ?? "\(value)%"
    }

    // The language the app speaks: "en", "fr", "zh-Hans".
    static var language: String { english ? "en" : Bundle.main.preferredLocalizations.first ?? "en" }
}
