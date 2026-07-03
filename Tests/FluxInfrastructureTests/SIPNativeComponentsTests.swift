import Testing
import Foundation
import FluxDomain
@testable import FluxInfrastructure

@Suite("SIPDigestAuthenticator")
struct SIPDigestAuthenticatorTests {
    @Test("vetor conhecido da RFC 2617 (qop=auth) produz o response correto")
    func rfc2617KnownVector() {
        // Exemplo canônico da RFC 2617 §3.5 — mesmo algoritmo usado no SIP.
        let challenge = SIPDigestChallenge(
            realm: "testrealm@host.com",
            nonce: "dcd98b7102dd2f0e8b11d0f600bfb0c093",
            qop: "auth",
            opaque: "5ccc069c403ebaf9f0171e9517f40e41",
            algorithm: "MD5"
        )
        let header = SIPDigestAuthenticator.authorizationHeaderValue(
            username: "Mufasa",
            password: "Circle Of Life",
            method: "GET",
            uri: "/dir/index.html",
            challenge: challenge,
            cnonce: "0a4f113b",
            nonceCount: 1
        )

        #expect(header.contains(#"response="6629fae49393a05397450978507c4ef1""#))
        #expect(header.contains("qop=auth"))
        #expect(header.contains("nc=00000001"))
        #expect(header.contains(#"opaque="5ccc069c403ebaf9f0171e9517f40e41""#))
        #expect(!header.contains("Circle Of Life"))
    }

    @Test("sem qop usa o cálculo RFC 2069")
    func withoutQop() {
        let challenge = SIPDigestChallenge(
            realm: "asterisk", nonce: "abc123", qop: nil, opaque: nil, algorithm: "MD5"
        )
        let header = SIPDigestAuthenticator.authorizationHeaderValue(
            username: "1001", password: "s3nh4", method: "REGISTER",
            uri: "sip:sip.test.local", challenge: challenge,
            cnonce: "ignored", nonceCount: 1
        )

        // response = MD5(HA1:nonce:HA2), verificado manualmente.
        let ha1 = SIPDigestAuthenticator.md5("1001:asterisk:s3nh4")
        let ha2 = SIPDigestAuthenticator.md5("REGISTER:sip:sip.test.local")
        let expected = SIPDigestAuthenticator.md5("\(ha1):abc123:\(ha2)")
        #expect(header.contains(#"response="\#(expected)""#))
        #expect(!header.contains("qop"))
        #expect(!header.contains("cnonce"))
    }

    @Test("challenge típico de Asterisk/PABX é parseado")
    func parsesChallengeHeader() {
        let header = #"Digest realm="sip.flux.net.br", nonce="1a2b3c4d", qop="auth", algorithm=MD5, opaque="xyz""#
        let challenge = SIPDigestChallenge.parse(fromHeader: header)

        #expect(challenge?.realm == "sip.flux.net.br")
        #expect(challenge?.nonce == "1a2b3c4d")
        #expect(challenge?.qop == "auth")
        #expect(challenge?.algorithm == "MD5")
        #expect(challenge?.opaque == "xyz")
    }

    @Test("valores com vírgula dentro de aspas não quebram o parser")
    func quotedCommaSafe() {
        let params = SIPDigestChallenge.parseParameters(#"realm="a, b", nonce="n""#)
        #expect(params["realm"] == "a, b")
        #expect(params["nonce"] == "n")
    }

    @Test("challenge sem realm ou nonce é rejeitado")
    func rejectsIncompleteChallenge() {
        #expect(SIPDigestChallenge.parse(fromHeader: #"Digest nonce="n""#) == nil)
        #expect(SIPDigestChallenge.parse(fromHeader: "Basic abc") == nil)
    }
}

@Suite("SIPRequestBuilder e SIPResponse")
struct SIPMessageTests {
    private var account: SIPAccount {
        SIPAccount(username: "1001", password: "segredo", domain: "sip.test.local", transport: .udp)
    }

    private func buildRegister(expires: Int = 300, auth: (String, String)? = nil) -> String {
        SIPRequestBuilder.register(.init(
            account: account,
            callId: "call-id-1",
            cseq: 2,
            fromTag: "tag1",
            branch: "z9hG4bKbranch1",
            localHost: "192.168.0.10",
            localPort: 5060,
            expires: expires,
            userAgent: "TestPhone/0.1",
            authorization: auth
        ))
    }

    @Test("REGISTER contém os headers obrigatórios e termina com linha vazia")
    func registerHasMandatoryHeaders() {
        let message = buildRegister()

        #expect(message.hasPrefix("REGISTER sip:sip.test.local SIP/2.0\r\n"))
        #expect(message.contains("Via: SIP/2.0/UDP 192.168.0.10:5060;branch=z9hG4bKbranch1;rport\r\n"))
        #expect(message.contains("From: <sip:1001@sip.test.local>;tag=tag1\r\n"))
        #expect(message.contains("To: <sip:1001@sip.test.local>\r\n"))
        #expect(message.contains("Call-ID: call-id-1\r\n"))
        #expect(message.contains("CSeq: 2 REGISTER\r\n"))
        #expect(message.contains("Expires: 300\r\n"))
        #expect(message.contains("Content-Length: 0\r\n"))
        #expect(message.hasSuffix("\r\n\r\n"))
        // A senha jamais aparece na mensagem.
        #expect(!message.contains("segredo"))
    }

    @Test("header de autorização entra com o nome correto")
    func authorizationHeaderIncluded() {
        let message = buildRegister(auth: ("Authorization", "Digest username=\"1001\""))
        #expect(message.contains("Authorization: Digest username=\"1001\"\r\n"))
    }

    @Test("desregistro usa Expires: 0")
    func unregisterUsesExpiresZero() {
        #expect(buildRegister(expires: 0).contains("Expires: 0\r\n"))
    }

    @Test("resposta 401 com headers é parseada (case-insensitive)")
    func parses401() throws {
        let raw = "SIP/2.0 401 Unauthorized\r\n" +
            "Via: SIP/2.0/UDP 192.168.0.10:5060;branch=z9hG4bKbranch1\r\n" +
            "WWW-AUTHENTICATE: Digest realm=\"sip.test.local\", nonce=\"n1\"\r\n" +
            "Content-Length: 0\r\n\r\n"
        let response = try #require(SIPResponse.parse(raw))

        #expect(response.statusCode == 401)
        #expect(response.reasonPhrase == "Unauthorized")
        #expect(response.firstHeader("www-authenticate")?.contains("realm=\"sip.test.local\"") == true)
    }

    @Test("200 OK e lixo não-SIP")
    func parses200AndRejectsGarbage() throws {
        let ok = try #require(SIPResponse.parse("SIP/2.0 200 OK\r\nExpires: 300\r\n\r\n"))
        #expect(ok.statusCode == 200)
        #expect(ok.firstHeader("Expires") == "300")

        #expect(SIPResponse.parse("HTTP/1.1 200 OK\r\n\r\n") == nil)
        #expect(SIPResponse.parse("") == nil)
    }
}
