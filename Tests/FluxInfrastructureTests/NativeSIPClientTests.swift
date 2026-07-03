import Testing
import Foundation
import Network
import os
import FluxDomain
@testable import FluxInfrastructure

/// Servidor SIP fake em UDP no loopback: responde 401 com challenge digest
/// ao REGISTER sem credencial e 200 OK ao REGISTER autenticado (validando o
/// digest de verdade). Permite testar o NativeSIPClient de ponta a ponta
/// sem servidor externo.
private final class FakeSIPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-sip-server")
    private let expectedUsername: String
    private let expectedPassword: String
    private let realm = "fake.test"
    private let nonce = "nonce-12345"

    private(set) var port: UInt16 = 0

    init(username: String, password: String) throws {
        expectedUsername = username
        expectedPassword = password
        listener = try NWListener(using: .udp, on: .any)
    }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receiveLoop(connection)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.withLock({ done in defer { done = true }; return !done }) {
                        cont.resume()
                    }
                case .failed(let error), .waiting(let error):
                    if resumed.withLock({ done in defer { done = true }; return !done }) {
                        cont.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        port = listener.port?.rawValue ?? 0
    }

    func stop() {
        listener.cancel()
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            let response = self.respond(to: request)
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
            self.receiveLoop(connection)
        }
    }

    private func respond(to request: String) -> String {
        // Servidor real ecoa Via/From/To/Call-ID/CSeq — o cliente roteia
        // respostas pelo branch do Via, então isso é obrigatório.
        let echo = echoedHeaders(from: request)

        guard request.hasPrefix("REGISTER ") else {
            return status("501 Not Implemented", echo: echo)
        }
        guard let authLine = request
            .components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("authorization:") })
        else {
            return status(
                "401 Unauthorized", echo: echo,
                extra: "WWW-Authenticate: Digest realm=\"\(realm)\", nonce=\"\(nonce)\", qop=\"auth\", algorithm=MD5"
            )
        }

        // Recalcula o digest com a senha esperada e compara.
        let value = String(authLine.dropFirst("authorization:".count))
        let params = SIPDigestChallenge.parseParameters(
            value.replacingOccurrences(of: "Digest", with: "")
        )
        guard let response = params["response"],
              let uri = params["uri"],
              let cnonce = params["cnonce"],
              let nc = params["nc"]
        else {
            return status("403 Forbidden", echo: echo)
        }
        let ha1 = SIPDigestAuthenticator.md5("\(expectedUsername):\(realm):\(expectedPassword)")
        let ha2 = SIPDigestAuthenticator.md5("REGISTER:\(uri)")
        let expected = SIPDigestAuthenticator.md5("\(ha1):\(nonce):\(nc):\(cnonce):auth:\(ha2)")

        if response == expected {
            return status("200 OK", echo: echo, extra: "Expires: 300")
        }
        return status("403 Forbidden", echo: echo)
    }

    private func echoedHeaders(from request: String) -> [String] {
        let wanted = ["via:", "from:", "to:", "call-id:", "cseq:"]
        return request.components(separatedBy: "\r\n").filter { line in
            wanted.contains { line.lowercased().hasPrefix($0) }
        }
    }

    private func status(_ status: String, echo: [String], extra: String? = nil) -> String {
        var lines = ["SIP/2.0 \(status)"] + echo
        if let extra { lines.append(extra) }
        lines.append("Content-Length: 0")
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }
}

@Suite("NativeSIPClient", .serialized)
struct NativeSIPClientTests {
    @Test("registra contra servidor local com challenge digest (401 → 200)")
    func registersWithDigestChallenge() async throws {
        let server = try FakeSIPServer(username: "1001", password: "s3nh4!")
        try await server.start()
        defer { server.stop() }

        let client = NativeSIPClient(userAgent: "Test/0.1", requestTimeout: .seconds(3))
        var iterator = client.events.makeAsyncIterator()

        try await client.configure(account: SIPAccount(
            username: "1001",
            password: "s3nh4!",
            domain: "127.0.0.1",
            transport: .udp,
            port: Int(server.port)
        ))
        #expect(await iterator.next() == .registrationChanged(.idle))

        try await client.register()
        #expect(await iterator.next() == .registrationChanged(.registering))
        #expect(await iterator.next() == .registrationChanged(.registered))
    }

    @Test("senha errada termina em falha de autenticação")
    func wrongPasswordFails() async throws {
        let server = try FakeSIPServer(username: "1001", password: "correta")
        try await server.start()
        defer { server.stop() }

        let client = NativeSIPClient(userAgent: "Test/0.1", requestTimeout: .seconds(3))
        var iterator = client.events.makeAsyncIterator()

        try await client.configure(account: SIPAccount(
            username: "1001",
            password: "errada",
            domain: "127.0.0.1",
            transport: .udp,
            port: Int(server.port)
        ))
        #expect(await iterator.next() == .registrationChanged(.idle))

        await #expect(throws: SIPClientError.authenticationFailed) {
            try await client.register()
        }
        #expect(await iterator.next() == .registrationChanged(.registering))
        #expect(await iterator.next() == .registrationChanged(.failed(.authenticationFailed)))
    }

    @Test("servidor inexistente falha como inalcançável dentro do timeout")
    func unreachableServerFails() async throws {
        let client = NativeSIPClient(userAgent: "Test/0.1", requestTimeout: .milliseconds(800))
        try await client.configure(account: SIPAccount(
            username: "u",
            password: "p",
            // TLD .invalid nunca resolve (RFC 2606) — determinístico e offline.
            domain: "sip.invalid",
            transport: .udp
        ))

        await #expect(throws: SIPClientError.serverUnreachable) {
            try await client.register()
        }
    }

    @Test("register e makeCall sem configurar falham com notConfigured; DTMF sem chamada é callNotFound")
    func contractParity() async throws {
        let client = NativeSIPClient(userAgent: "Test/0.1", mediaFactory: { throw MediaSessionError.socketUnavailable })

        await #expect(throws: SIPClientError.notConfigured) {
            try await client.register()
        }
        await #expect(throws: SIPClientError.notConfigured) {
            try await client.makeCall(to: "1002")
        }
        // DTMF exige chamada ativa; sem ela, a chamada "x" não existe.
        await #expect(throws: SIPClientError.callNotFound(id: "x")) {
            try await client.sendDTMF(callId: "x", digit: "1")
        }
    }
}
