import Testing
@testable import FluxInfrastructure

@Suite("LogSanitizer")
struct LogSanitizerTests {
    @Test("usuário é mascarado preservando prefixo")
    func maskUsername() {
        #expect(LogSanitizer.maskUsername("joao.silva") == "jo***")
        #expect(LogSanitizer.maskUsername("ab") == "***")
        #expect(LogSanitizer.maskUsername("") == "***")
    }

    @Test("número longo mantém só os 4 últimos dígitos")
    func maskNumber() {
        #expect(LogSanitizer.maskNumber("51999998888") == "•••8888")
        #expect(!LogSanitizer.maskNumber("51999998888").contains("5199999"))
    }

    @Test("ramal curto não é mascarado")
    func shortExtensionKept() {
        #expect(LogSanitizer.maskNumber("1001") == "1001")
    }

    @Test("segredos em texto livre são redigidos")
    func redactSecrets() {
        let input = "user=1001 password=SuperSecreta123 token: abc.def.ghi Authorization: Bearer xyz"
        let output = LogSanitizer.redactSecrets(in: input)

        #expect(!output.contains("SuperSecreta123"))
        #expect(!output.contains("abc.def.ghi"))
        #expect(!output.contains("xyz"))
        #expect(output.contains("user=1001"))
        #expect(output.contains("[REDACTED]"))
    }

    @Test("segredos em JSON são redigidos preservando a estrutura")
    func redactSecretsInJSON() {
        let input = #"{"user": "1001", "password": "hunter2", "token": "abc123"}"#
        let output = LogSanitizer.redactSecrets(in: input)

        #expect(!output.contains("hunter2"))
        #expect(!output.contains("abc123"))
        #expect(output.contains(#""user": "1001""#))
        #expect(output.contains(#""password": "[REDACTED]""#))
    }

    @Test("chaves em português e de API são redigidas")
    func redactLocalizedAndAPIKeys() {
        let cases = [
            "senha: minhasenha123",
            "api_key=abc123",
            "x-api-key: def456",
            "apikey: ghi789",
            "pin=1234",
        ]
        for input in cases {
            let output = LogSanitizer.redactSecrets(in: input)
            #expect(output.contains("[REDACTED]"), "não redigiu: \(input)")
            #expect(!output.contains(input.split(separator: input.contains("=") ? "=" : ":").last!.trimmingCharacters(in: .whitespaces)), "vazou valor em: \(input)")
        }
    }

    @Test("senha com espaços é redigida por inteiro")
    func redactPasswordWithSpaces() {
        let output = LogSanitizer.redactSecrets(in: "password: correct horse battery staple")
        #expect(!output.contains("horse"))
        #expect(!output.contains("staple"))
        #expect(output == "password: [REDACTED]")
    }

    @Test("linhas seguintes a um segredo são preservadas")
    func redactStopsAtLineBreak() {
        let input = "senha: segredo123\nstatus: registrado"
        let output = LogSanitizer.redactSecrets(in: input)
        #expect(!output.contains("segredo123"))
        #expect(output.contains("status: registrado"))
    }

    @Test("palavras que apenas contêm chaves sensíveis não são afetadas")
    func noFalsePositives() {
        let input = "author=Fulano oauth_flow=iniciado mapping=ok"
        #expect(LogSanitizer.redactSecrets(in: input) == input)
    }
}
