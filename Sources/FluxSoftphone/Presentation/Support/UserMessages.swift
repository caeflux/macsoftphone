import Foundation
import FluxDomain

/// Microcopy de erro para o usuário final (docs/04_UI_UX_GUIDELINES.md).
/// Nada de "SIP 403" ou jargão de transporte na UI principal.
enum UserMessages {
    static let genericError = "Ocorreu um erro inesperado. Tente novamente."

    static func message(for error: SIPClientError) -> String {
        switch error {
        case .notConfigured:
            return "Configure uma conta SIP para continuar."
        case .notRegistered:
            return "Conta não registrada. Registre-se para fazer chamadas."
        case .alreadyInCall:
            return "Já existe uma chamada em andamento."
        case .authenticationFailed:
            return "Falha de autenticação. Verifique usuário e senha."
        case .networkUnavailable:
            return "Sem conexão com a internet."
        case .serverUnreachable:
            return "Não foi possível conectar ao servidor SIP."
        case .invalidDestination:
            return "Número inválido. Verifique o destino digitado."
        case .callNotFound:
            return "A chamada não está mais disponível."
        case .notSupported:
            return "Este recurso ainda não está disponível na engine SIP atual."
        case .serverRejected(let code, let reason):
            // Texto do servidor (ex.: "Mobile DDI calls blocked") — indica
            // política/rota do PABX, informação que o usuário precisa ver.
            return "O servidor recusou (\(code)): \(reason)"
        case .engineFailure:
            return "O servidor SIP recusou a operação. Tente novamente."
        }
    }

    static func message(for error: SIPAccountValidator.ValidationError) -> String {
        switch error {
        case .emptyUsername:
            return "Informe o usuário SIP."
        case .emptyPassword:
            return "Informe a senha."
        case .emptyDomain:
            return "Informe o domínio SIP."
        case .invalidDomain:
            return "Domínio SIP inválido. Use um endereço como sip.exemplo.com."
        case .invalidPort:
            return "Porta inválida. Use um número entre 1 e 65535."
        }
    }
}
