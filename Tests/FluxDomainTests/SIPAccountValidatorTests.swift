import Testing
@testable import FluxDomain

@Suite("SIPAccountValidator")
struct SIPAccountValidatorTests {
    @Test("conta válida não gera erros")
    func validAccount() {
        let errors = SIPAccountValidator.validate(
            username: "1001",
            password: "s3nh4",
            domain: "sip.example.com",
            port: 5060
        )
        #expect(errors.isEmpty)
    }

    @Test("campos vazios são todos reportados de uma vez")
    func emptyFieldsReportedTogether() {
        let errors = SIPAccountValidator.validate(username: "  ", password: "", domain: "")
        #expect(errors.contains(.emptyUsername))
        #expect(errors.contains(.emptyPassword))
        #expect(errors.contains(.emptyDomain))
    }

    @Test("domínio com espaço ou arroba é inválido")
    func invalidDomains() {
        #expect(SIPAccountValidator.validate(username: "u", password: "p", domain: "sip example.com") == [.invalidDomain])
        #expect(SIPAccountValidator.validate(username: "u", password: "p", domain: "user@sip.com") == [.invalidDomain])
        #expect(SIPAccountValidator.validate(username: "u", password: "p", domain: "sip..com") == [.invalidDomain])
    }

    @Test("hostname simples e IPv4 são aceitos (ambientes de teste)")
    func plausibleDomains() {
        #expect(SIPAccountValidator.validate(username: "u", password: "p", domain: "pbx-interno").isEmpty)
        #expect(SIPAccountValidator.validate(username: "u", password: "p", domain: "10.0.0.10").isEmpty)
    }

    @Test("porta fora do intervalo é inválida")
    func invalidPort() {
        #expect(SIPAccountValidator.validate(username: "u", password: "p", domain: "d.com", port: 0) == [.invalidPort])
        #expect(SIPAccountValidator.validate(username: "u", password: "p", domain: "d.com", port: 70000) == [.invalidPort])
    }
}
