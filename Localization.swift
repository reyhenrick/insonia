import Foundation

/// A small Foundation-only catalog shared by the app, guardian and tests.
/// Messages are persisted as keys and arguments, never as translated sentences.
struct LocalizationCatalog {
    static let supported = ["en", "pt", "es", "fr", "de", "it"]
    let language: String
    let tables: [String: [String: String]]

    static func language(for preferences: [String]) -> String {
        for preference in preferences {
            let code = preference.replacingOccurrences(of: "_", with: "-")
                .split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if supported.contains(code) { return code }
        }
        return "en"
    }

    init(resources: URL, preferences: [String]) {
        language = Self.language(for: preferences)
        var loaded: [String: [String: String]] = [:]
        for code in Self.supported {
            let url = resources.appendingPathComponent("\(code).lproj/Localizable.strings")
            if let data = try? Data(contentsOf: url),
               let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] {
                loaded[code] = table
            }
        }
        tables = loaded
    }

    func text(_ key: String, arguments: [String] = []) -> String {
        let template = tables[language]?[key] ?? tables["en"]?[key] ?? key
        // One pass prevents a placeholder inside a technical error argument
        // from being interpreted as another catalog placeholder.
        let pattern = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        let matches = pattern.matches(in: template, range: NSRange(template.startIndex..., in: template))
        var result = template
        for match in matches.reversed() {
            guard let numberRange = Range(match.range(at: 1), in: template),
                  let index = Int(template[numberRange]), arguments.indices.contains(index),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index])
        }
        return result
    }

    // Persisted messages from before keyed notices must survive copy changes.
    private static let legacyPortugueseMessages: [String: String] = [
        "Atualize a proteção do sistema para ativar o Insonia.": "error.helperRequired",
        "O monitor de recuperação está iniciando. Tente novamente em instantes.": "error.guardianStarting",
        "O sistema ainda não confirmou o repouso normal. Verifique a proteção do sistema.": "error.sleepUnconfirmed",
        "A sessão foi encerrada pelo monitor de recuperação.": "error.sessionRecovered",
        "A proteção do sistema deixou de responder. Atualize o helper antes de reativar.": "error.helperUnavailable",
        "O monitor de recuperação não está respondendo. O Insonia foi desativado.": "error.guardianUnavailable",
        "O helper não confirmou a ativação. Atualize a proteção do sistema.": "error.helperUnconfirmed",
        "A proteção não foi atualizada. O macOS precisa da autorização de um administrador.": "error.authorization",
        "O monitor de recuperação foi encerrado. O repouso normal foi solicitado.": "recovery.guardianExit",
        "O monitor de recuperação não está instalado neste aplicativo.": "error.guardianMissing",
        "Não foi possível iniciar o monitor de recuperação.": "error.guardianInstall",
        "Não foi possível salvar a proteção. Libere espaço no disco e tente novamente.": "error.storage",
        "Mova o Insonia para Aplicativos e abra-o de lá para instalar a proteção.": "error.installLocation",
        "Aguarde a proteção do sistema concluir a operação antes de atualizar.": "error.updateBusy",
    ]

    func legacyMessage(_ source: String) -> InsoniaFailure {
        let normalized = source.replacingOccurrences(of: "Insônia", with: "Insonia")
        if let key = Self.legacyPortugueseMessages[normalized] { return InsoniaFailure(key) }
        for (key, value) in tables["pt"] ?? [:] where value == normalized {
            return InsoniaFailure(key)
        }
        let pattern = #"^Pausado: bateria em (\d+)%. Conecte o carregador antes de reativar\.$"#
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
           let range = Range(match.range(at: 1), in: normalized) {
            return InsoniaFailure("safety.battery", String(normalized[range]))
        }
        return InsoniaFailure(normalized)
    }
}

enum L10n {
    static let resources: URL = {
        // Bundle.main for the standalone guardian is not always the outer app.
        var candidate = Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL
        for _ in 0..<5 {
            if candidate.pathExtension == "app" {
                return candidate.appendingPathComponent("Contents/Resources")
            }
            candidate.deleteLastPathComponent()
        }
        return (Bundle.main.executableURL?.deletingLastPathComponent() ?? Bundle.main.bundleURL)
            .appendingPathComponent("Resources")
    }()
    static let catalog = LocalizationCatalog(resources: resources,
        preferences: UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages)
    static var language: String { catalog.language }
    static func text(_ key: String, _ arguments: String...) -> String {
        catalog.text(key, arguments: arguments)
    }
    static var languageName: String {
        Locale(identifier: language).localizedString(forLanguageCode: language) ?? language
    }
}

struct InsoniaFailure: LocalizedError, Codable, Equatable, ExpressibleByStringLiteral {
    let key: String
    let arguments: [String]
    init(_ key: String, _ arguments: String...) { self.key = key; self.arguments = arguments }
    init(stringLiteral value: String) { self.init(value) }
    var message: String { L10n.catalog.text(key, arguments: arguments) }
    var errorDescription: String? { message }

    static func wrapping(_ error: Error) -> InsoniaFailure {
        if let failure = error as? InsoniaFailure { return failure }
        let nsError = error as NSError
        if (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == 28) {
            return InsoniaFailure("error.storage")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, underlying.code == 28 {
            return InsoniaFailure("error.storage")
        }
        return InsoniaFailure(error.localizedDescription.replacingOccurrences(of: "Insônia", with: "Insonia"))
    }
}
