import Foundation

/// Validação mínima de conta SIP antes de tentar registro
/// (usada pelo formulário manual no Ciclo 3 e por provisionamento futuro).
public enum SIPAccountValidator {
    public enum ValidationError: Error, Equatable, Sendable {
        case emptyUsername
        case emptyPassword
        case emptyDomain
        case invalidDomain
        case invalidPort
    }

    /// Valida os campos essenciais. Retorna a lista completa de problemas
    /// para o formulário exibir tudo de uma vez.
    public static func validate(
        username: String,
        password: String,
        domain: String,
        port: Int? = nil
    ) -> [ValidationError] {
        var errors: [ValidationError] = []

        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyUsername)
        }
        if password.isEmpty {
            errors.append(.emptyPassword)
        }

        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDomain.isEmpty {
            errors.append(.emptyDomain)
        } else if !isPlausibleDomain(trimmedDomain) {
            errors.append(.invalidDomain)
        }

        if let port, !(1...65535).contains(port) {
            errors.append(.invalidPort)
        }

        return errors
    }

    /// Aceita hostname/FQDN ou IPv4. Não tenta ser um parser RFC completo —
    /// só barra entradas claramente inválidas sem bloquear ambientes de teste.
    static func isPlausibleDomain(_ domain: String) -> Bool {
        guard !domain.contains(" "), !domain.contains("@") else { return false }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return labels.allSatisfy { label in
            label.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }
}
