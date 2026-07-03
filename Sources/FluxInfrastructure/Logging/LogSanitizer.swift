import Foundation

/// Máscaras para dados sensíveis em logs e diagnóstico
/// (docs/05_SECURITY_PRIVACY.md). Funções puras, testáveis.
public enum LogSanitizer {
    /// Mantém os 2 primeiros caracteres do usuário: `joao.silva` → `jo***`.
    public static func maskUsername(_ username: String) -> String {
        guard username.count > 2 else { return "***" }
        return "\(username.prefix(2))***"
    }

    /// Mantém apenas os 4 últimos dígitos: `51999998888` → `•••8888`.
    /// Números curtos (ramais de até 4 dígitos) não são considerados sensíveis.
    public static func maskNumber(_ number: String) -> String {
        let digits = number.filter(\.isNumber)
        guard digits.count > 4 else { return number }
        return "•••\(digits.suffix(4))"
    }

    /// Chaves cujo valor é sempre segredo. Inclui variantes em português —
    /// o produto e seus servidores logam em pt-BR.
    private static let secretKeys =
        #"(?:proxy-)?authorization|password|passwd|pwd|senha|secret|token|pin|api[-_]?key|apikey|auth"#

    /// Remove valores de chaves sensíveis em texto livre — última linha de
    /// defesa antes de copiar diagnóstico ou gravar log.
    /// Cobre `password=x`, `senha: x`, `Authorization: Bearer x`,
    /// `"token": "x"` (JSON) e valores com espaços.
    ///
    /// Política: sob-redação nunca; sobre-redação é aceitável. Fora de JSON,
    /// o valor consome o resto da linha (senhas podem conter espaços).
    public static func redactSecrets(in text: String) -> String {
        // 1. JSON/chaves entre aspas: redige só o valor entre aspas,
        //    preservando a estrutura do documento.
        var result = replacing(
            pattern: #"(?i)("(?:\#(secretKeys))")(\s*[:=]\s*)"[^"]*""#,
            in: text,
            template: "$1$2\"[REDACTED]\""
        )
        // 2. Texto livre/headers: tudo após a chave até o fim da linha é
        //    considerado segredo (cobre "Bearer xyz" e senhas com espaço).
        result = replacing(
            pattern: #"(?i)\b(\#(secretKeys))(\s*[:=]\s*)([^\r\n]+)"#,
            in: result,
            template: "$1$2[REDACTED]"
        )
        return result
    }

    private static func replacing(pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: template
        )
    }
}
