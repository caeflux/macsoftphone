import Testing
import Foundation
@testable import FluxDomain

@Suite("SIPAccount")
struct SIPAccountTests {
    @Test("description nunca expõe a senha")
    func descriptionMasksPassword() {
        let secret = "senha-super-secreta-\(UUID().uuidString)"
        let account = SIPAccount(username: "usuario1001", password: secret, domain: "sip.example.com")

        #expect(!account.description.contains(secret))
        #expect(!account.debugDescription.contains(secret))
        #expect(!String(describing: account).contains(secret))
    }

    @Test("description mascara o usuário")
    func descriptionMasksUsername() {
        let account = SIPAccount(username: "usuario1001", password: "x", domain: "sip.example.com")
        #expect(account.description.contains("us***"))
        #expect(!account.description.contains("usuario1001"))
    }

    @Test("porta padrão segue o transporte")
    func defaultPortFollowsTransport() {
        let udp = SIPAccount(username: "u", password: "p", domain: "d.com", transport: .udp)
        let tls = SIPAccount(username: "u", password: "p", domain: "d.com", transport: .tls)
        let custom = SIPAccount(username: "u", password: "p", domain: "d.com", transport: .tls, port: 15061)

        #expect(udp.port == 5060)
        #expect(tls.port == 5061)
        #expect(custom.port == 15061)
    }

    @Test("uri não contém credenciais")
    func uriHasNoCredentials() {
        let account = SIPAccount(username: "1001", password: "segredo", domain: "sip.example.com")
        #expect(account.uri == "sip:1001@sip.example.com")
    }
}
