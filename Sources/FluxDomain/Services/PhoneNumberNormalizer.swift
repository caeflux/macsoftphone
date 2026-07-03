import Foundation

/// Normalização básica de destino discável (docs/04_UI_UX_GUIDELINES.md):
/// remove separadores visuais sem destruir ramais curtos, códigos de serviço
/// (`*142#`) ou prefixo internacional (`+`).
public enum PhoneNumberNormalizer {
    /// Caracteres que sobrevivem à normalização (além de dígitos).
    private static let serviceChars: Set<Character> = ["*", "#"]
    /// Separadores visuais comuns em números colados de outras fontes.
    private static let separators: Set<Character> = [" ", "-", "(", ")", ".", "/", "\u{00A0}"]

    /// Remove separadores preservando dígitos, `*`, `#` e um `+` inicial.
    /// Caracteres desconhecidos (letras etc.) são mantidos — a validação
    /// em `isDiallable` os rejeita, em vez de "consertar" silenciosamente
    /// uma entrada que o usuário precisa revisar.
    public static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        for character in trimmed {
            if separators.contains(character) { continue }
            if character == "+" {
                // `+` só é significativo como prefixo internacional.
                if result.isEmpty { result.append(character) }
                continue
            }
            result.append(character)
        }
        return result
    }

    /// Um destino é discável se, normalizado, tiver ao menos um dígito ou
    /// código de serviço e nenhum caractere estranho.
    public static func isDiallable(_ normalized: String) -> Bool {
        var candidate = Substring(normalized)
        if candidate.first == "+" {
            candidate = candidate.dropFirst()
            // `+` exige número em formato internacional: só dígitos após ele.
            return !candidate.isEmpty && candidate.allSatisfy(\.isNumber)
        }
        guard !candidate.isEmpty else { return false }
        return candidate.allSatisfy { $0.isNumber || serviceChars.contains($0) }
    }
}
