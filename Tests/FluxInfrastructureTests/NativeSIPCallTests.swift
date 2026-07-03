import Testing
import Foundation
import Network
import os
import FluxDomain
@testable import FluxInfrastructure

/// MediaSession falsa: porta fixa, registra chamadas de start/stop.
/// Permite testar o fluxo de chamada da engine sem hardware de áudio.
private final class FakeMediaSession: MediaSessionProtocol, @unchecked Sendable {
    let localRTPPort: Int
    private let state = OSAllocatedUnfairLock(initialState: State())
    struct State {
        var started = false
        var stopped = false
        var muted = false
        var codec: G711Codec?
        var retargets: [(host: String, port: Int)] = []
        var telephoneEventPT: Int?
        var dtmfDigits: [Character] = []
    }

    init(port: Int = 41234) { localRTPPort = port }

    func start(remoteHost: String, remotePort: Int, codec: G711Codec) async throws {
        state.withLock { $0.started = true; $0.codec = codec }
    }
    func retarget(remoteHost: String, remotePort: Int, codec: G711Codec) async throws {
        state.withLock { $0.retargets.append((remoteHost, remotePort)); $0.codec = codec }
    }
    func setTelephoneEventPayloadType(_ payloadType: Int?) async {
        state.withLock { $0.telephoneEventPT = payloadType }
    }
    func sendDTMF(digit: Character) async throws {
        let negotiated = state.withLock { $0.telephoneEventPT != nil }
        guard negotiated else { throw MediaSessionError.dtmfNotNegotiated }
        state.withLock { $0.dtmfDigits.append(digit) }
    }
    func setMuted(_ muted: Bool) async { state.withLock { $0.muted = muted } }
    func stop() async { state.withLock { $0.stopped = true } }

    var didStart: Bool { state.withLock { $0.started } }
    var didStop: Bool { state.withLock { $0.stopped } }
    var retargets: [(host: String, port: Int)] { state.withLock { $0.retargets } }
    var telephoneEventPT: Int? { state.withLock { $0.telephoneEventPT } }
    var dtmfDigits: [Character] { state.withLock { $0.dtmfDigits } }
}

/// Servidor SIP fake em UDP: registra (401→200) e aceita um INVITE,
/// respondendo 100 → 180 → 200 OK com SDP, e 200 OK ao BYE.
private final class FakeSIPCallServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-sip-call-server")
    private let realm = "fake.test"
    private let nonce = "n-call-1"
    private let username: String
    private let password: String
    private var lastConnection: NWConnection?

    private(set) var port: UInt16 = 0

    init(username: String, password: String) throws {
        self.username = username
        self.password = password
        listener = try NWListener(using: .udp, on: .any)
    }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lastConnection = connection
            connection.start(queue: self.queue)
            self.receiveLoop(connection)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                if case .ready = state {
                    if resumed.withLock({ d in defer { d = true }; return !d }) { cont.resume() }
                } else if case .failed(let e) = state {
                    if resumed.withLock({ d in defer { d = true }; return !d }) { cont.resume(throwing: e) }
                }
            }
            listener.start(queue: queue)
        }
        port = listener.port?.rawValue ?? 0
    }

    func stop() { listener.cancel() }

    /// Conta ACKs recebidos (para o teste checar que o atendimento fechou).
    private let ackCount = OSAllocatedUnfairLock(initialState: 0)
    var receivedAcks: Int { ackCount.withLock { $0 } }

    /// Tudo que o cliente enviou (para asserções sobre respostas dele).
    private let inbox = OSAllocatedUnfairLock(initialState: [String]())
    var receivedMessages: [String] { inbox.withLock { $0 } }

    /// Dados do diálogo capturados do INVITE do cliente, para o servidor
    /// poder originar requisições em diálogo (re-INVITE/UPDATE).
    private struct DialogInfo {
        var callId = ""
        var clientFrom = ""    // From do cliente, com tag
        var clientTo = ""      // To original (sem tag; servidor põe srvtag)
        var clientContact = "" // URI do Contact do cliente
    }
    private let dialogInfo = OSAllocatedUnfairLock(initialState: DialogInfo())

    /// Headers Record-Route a incluir nas respostas ao INVITE (simula proxy
    /// que faz record-routing, como o do PABX que causava "ACK Timeout").
    let recordRoutes = OSAllocatedUnfairLock(initialState: [String]())

    /// O servidor origina um INVITE para o cliente (chamada de entrada),
    /// pela mesma conexão UDP usada no registro.
    func sendIncomingInvite(callId: String) {
        guard let connection = lastConnection else { return }
        let sdp = SDP.audioDescription(sessionId: "srvin", host: "127.0.0.1", rtpPort: 5006, codecs: [.pcmu])
        let invite = [
            "INVITE sip:1001@127.0.0.1 SIP/2.0",
            "Via: SIP/2.0/UDP 127.0.0.1:\(port);branch=z9hG4bKsrv\(callId)",
            "Max-Forwards: 70",
            "From: \"Fulano\" <sip:5551234@127.0.0.1>;tag=srvfrom",
            "To: <sip:1001@127.0.0.1>",
            "Call-ID: \(callId)",
            "CSeq: 1 INVITE",
            "Contact: <sip:5551234@127.0.0.1:\(port)>",
            "Content-Type: application/sdp",
            "Content-Length: \(sdp.utf8.count)"
        ].joined(separator: "\r\n") + "\r\n\r\n" + sdp
        connection.send(content: Data(invite.utf8), completion: .contentProcessed { _ in })
    }

    /// Servidor origina uma requisição em diálogo (papéis invertidos:
    /// From = servidor com srvtag, To = cliente com a tag dele).
    func sendInDialogRequest(method: String, cseq: Int, body: String = "") {
        guard let connection = lastConnection else { return }
        let dialog = dialogInfo.withLock { $0 }
        var serverFrom = dialog.clientTo
        if !serverFrom.contains("tag=") { serverFrom += ";tag=srvtag" }
        var lines = [
            "\(method) \(dialog.clientContact) SIP/2.0",
            "Via: SIP/2.0/UDP 127.0.0.1:\(port);branch=z9hG4bKsrvdlg\(cseq)",
            "Max-Forwards: 70",
            "From: \(serverFrom)",
            "To: \(dialog.clientFrom)",
            "Call-ID: \(dialog.callId)",
            "CSeq: \(cseq) \(method)"
        ]
        if !body.isEmpty { lines.append("Content-Type: application/sdp") }
        lines.append("Content-Length: \(body.utf8.count)")
        let message = lines.joined(separator: "\r\n") + "\r\n\r\n" + body
        connection.send(content: Data(message.utf8), completion: .contentProcessed { _ in })
    }

    func sendReInvite(cseq: Int, rtpPort: Int) {
        let sdp = SDP.audioDescription(sessionId: "srv2", host: "127.0.0.1", rtpPort: rtpPort, codecs: [.pcmu])
        sendInDialogRequest(method: "INVITE", cseq: cseq, body: sdp)
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            self.inbox.withLock { $0.append(request) }
            for reply in self.replies(to: request) {
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in })
            }
            self.receiveLoop(connection)
        }
    }

    private func replies(to request: String) -> [String] {
        let firstLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        // Respostas do cliente (ex.: 200 OK ao nosso re-INVITE) não geram réplica.
        if firstLine.hasPrefix("SIP/2.0") { return [] }
        let via = headerValue("Via", in: request) ?? ""
        let from = headerValue("From", in: request) ?? ""
        let to = headerValue("To", in: request) ?? ""
        let callId = headerValue("Call-ID", in: request) ?? ""
        let cseq = headerValue("CSeq", in: request) ?? ""

        func base(_ status: String, toTag: String? = nil, extra: String = "", body: String = "") -> String {
            var toLine = to
            if let toTag, !to.contains("tag=") { toLine = "\(to);tag=\(toTag)" }
            var lines = [
                "SIP/2.0 \(status)",
                "Via: \(via)",
                "From: \(from)",
                "To: \(toLine)",
                "Call-ID: \(callId)",
                "CSeq: \(cseq)"
            ]
            if !extra.isEmpty { lines.append(extra) }
            if !body.isEmpty { lines.append("Content-Type: application/sdp") }
            lines.append("Content-Length: \(body.utf8.count)")
            return lines.joined(separator: "\r\n") + "\r\n\r\n" + body
        }

        if firstLine.hasPrefix("REGISTER") {
            if request.range(of: "Authorization:", options: .caseInsensitive) == nil {
                return [base("401 Unauthorized",
                             extra: "WWW-Authenticate: Digest realm=\"\(realm)\", nonce=\"\(nonce)\", qop=\"auth\", algorithm=MD5")]
            }
            return [base("200 OK", extra: "Expires: 300")]
        }

        if firstLine.hasPrefix("INVITE") {
            // Captura o diálogo para requisições em diálogo futuras.
            let contactURI = headerValue("Contact", in: request).flatMap { value -> String? in
                guard let open = value.firstIndex(of: "<"),
                      let close = value.firstIndex(of: ">"), open < close else { return value }
                return String(value[value.index(after: open)..<close])
            } ?? ""
            dialogInfo.withLock {
                $0.callId = callId
                $0.clientFrom = from
                $0.clientTo = to
                $0.clientContact = contactURI
            }
            let sdp = SDP.audioDescription(
                sessionId: "srv", host: "127.0.0.1", rtpPort: 5004,
                codecs: [.pcmu], telephoneEventPayloadType: 101
            )
            let routeLines = recordRoutes.withLock { $0 }
                .map { "Record-Route: \($0)" }
                .joined(separator: "\r\n")
            var okExtra = "Contact: <sip:server@127.0.0.1>"
            if !routeLines.isEmpty { okExtra = routeLines + "\r\n" + okExtra }
            return [
                base("100 Trying"),
                base("180 Ringing", toTag: "srvtag"),
                base("200 OK", toTag: "srvtag", extra: okExtra, body: sdp)
            ]
        }

        if firstLine.hasPrefix("ACK") { ackCount.withLock { $0 += 1 }; return [] }
        if firstLine.hasPrefix("BYE") { return [base("200 OK", toTag: "srvtag")] }
        if firstLine.hasPrefix("CANCEL") {
            return [base("200 OK"), base("487 Request Terminated", toTag: "srvtag")]
        }
        return [base("200 OK")]
    }

    private func headerValue(_ name: String, in request: String) -> String? {
        for line in request.components(separatedBy: "\r\n") where line.lowercased().hasPrefix(name.lowercased() + ":") {
            return String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}

@Suite("NativeSIPClient — chamadas", .serialized)
struct NativeSIPCallTests {
    private func registered(server: FakeSIPCallServer, media: FakeMediaSession) async throws -> NativeSIPClient {
        let client = NativeSIPClient(
            userAgent: "Test/0.1",
            requestTimeout: .seconds(3),
            answerTimeout: .seconds(3),
            mediaFactory: { media }
        )
        try await client.configure(account: SIPAccount(
            username: "1001", password: "s3nh4!", domain: "127.0.0.1",
            transport: .udp, port: Int(server.port)
        ))
        try await client.register()
        return client
    }

    @Test("chamada de saída: INVITE → 180 → 200 estabelece mídia e BYE encerra")
    func outgoingCallEstablishesAndHangsUp() async throws {
        let server = try FakeSIPCallServer(username: "1001", password: "s3nh4!")
        try await server.start()
        defer { server.stop() }
        let media = FakeMediaSession()

        let client = try await registered(server: server, media: media)
        var iterator = client.events.makeAsyncIterator()

        let session = try await client.makeCall(to: "2002")
        #expect(session.state == .dialing)

        // Aguarda a chamada ficar ativa (dialing → ringing → active).
        var becameActive = false
        var activeCallId: String?
        for _ in 0..<40 {
            guard let event = await iterator.next() else { break }
            if case .callStateChanged(let call) = event, call.state == .active {
                becameActive = true
                activeCallId = call.id
                break
            }
        }
        #expect(becameActive)
        #expect(media.didStart)

        try await client.hangup(callId: try #require(activeCallId))
        // O encerramento para a mídia.
        var stopped = false
        for _ in 0..<20 {
            if media.didStop { stopped = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(stopped)
    }

    @Test("makeCall sem registro é recusada; destino vazio idem")
    func makeCallGuards() async throws {
        let client = NativeSIPClient(userAgent: "Test/0.1", mediaFactory: { FakeMediaSession() })
        await #expect(throws: SIPClientError.notConfigured) {
            try await client.makeCall(to: "2002")
        }
    }

    @Test("chamada de entrada: INVITE do servidor → atender estabelece mídia")
    func incomingCallAnswered() async throws {
        let server = try FakeSIPCallServer(username: "1001", password: "s3nh4!")
        try await server.start()
        defer { server.stop() }
        let media = FakeMediaSession()

        let client = try await registered(server: server, media: media)
        var iterator = client.events.makeAsyncIterator()

        server.sendIncomingInvite(callId: "incoming-call-1")

        // Espera o evento de chamada recebida.
        var incoming: CallSession?
        for _ in 0..<40 {
            guard let event = await iterator.next() else { break }
            if case .incomingCall(let call) = event { incoming = call; break }
        }
        let call = try #require(incoming)
        #expect(call.direction == .incoming)
        #expect(call.remoteNumber == "5551234")
        #expect(call.remoteDisplayName == "Fulano")

        try await client.answer(callId: call.id)

        // Aguarda a chamada ficar ativa e a mídia iniciar.
        var active = false
        for _ in 0..<40 {
            guard let event = await iterator.next() else { break }
            if case .callStateChanged(let c) = event, c.state == .active { active = true; break }
        }
        #expect(active)
        #expect(media.didStart)

        try await client.hangup(callId: call.id)
    }

    @Test("INVITE retransmitido após atender reenvia 200 OK (não derruba a chamada)")
    func retransmittedInviteAfterAnswer() async throws {
        let server = try FakeSIPCallServer(username: "1001", password: "s3nh4!")
        try await server.start()
        defer { server.stop() }
        let media = FakeMediaSession()

        let client = try await registered(server: server, media: media)
        var iterator = client.events.makeAsyncIterator()

        server.sendIncomingInvite(callId: "retx-1")
        var incoming: CallSession?
        for _ in 0..<40 {
            guard let event = await iterator.next() else { break }
            if case .incomingCall(let c) = event { incoming = c; break }
        }
        let call = try #require(incoming)
        try await client.answer(callId: call.id)

        // Espera ativa.
        for _ in 0..<40 {
            guard let event = await iterator.next() else { break }
            if case .callStateChanged(let c) = event, c.state == .active { break }
        }

        // Servidor retransmite o MESMO INVITE (ACK se perdeu). Antes da
        // correção, isto respondia 486 e derrubava a chamada.
        server.sendIncomingInvite(callId: "retx-1")
        try await Task.sleep(for: .milliseconds(300))

        // Asserção real: a chamada ainda está viva, então hangup NÃO lança
        // callNotFound. Se a retransmissão a tivesse derrubado, lançaria.
        try await client.hangup(callId: call.id)

        // A parada da mídia é assíncrona (Task interno do endCall): polling.
        var stopped = false
        for _ in 0..<20 {
            if media.didStop { stopped = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(stopped)
    }

    /// Estabelece uma chamada de saída e retorna (client, sessão ativa).
    private func establishOutgoingCall(
        server: FakeSIPCallServer,
        media: FakeMediaSession
    ) async throws -> (NativeSIPClient, CallSession) {
        let client = try await registered(server: server, media: media)
        var iterator = client.events.makeAsyncIterator()
        _ = try await client.makeCall(to: "2002")
        for _ in 0..<40 {
            guard let event = await iterator.next() else { break }
            if case .callStateChanged(let call) = event, call.state == .active {
                return (client, call)
            }
        }
        throw SIPClientError.serverUnreachable
    }

    @Test("re-INVITE do servidor é respondido com 200+SDP e redireciona a mídia — a chamada NÃO cai")
    func reInviteIsAnsweredAndCallSurvives() async throws {
        let server = try FakeSIPCallServer(username: "1001", password: "s3nh4!")
        try await server.start()
        defer { server.stop() }
        let media = FakeMediaSession()
        let (client, call) = try await establishOutgoingCall(server: server, media: media)

        // Servidor renegocia a mídia para outra porta (comportamento comum
        // de PABX/SBC logo após o atendimento).
        server.sendReInvite(cseq: 10, rtpPort: 5010)

        // O cliente deve responder 200 OK com SDP e redirecionar o RTP.
        var answered = false
        for _ in 0..<40 {
            let messages = server.receivedMessages
            if messages.contains(where: { $0.hasPrefix("SIP/2.0 200 OK") && $0.contains("10 INVITE") && $0.contains("m=audio") }) {
                answered = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(answered, "re-INVITE deveria receber 200 OK com SDP")
        #expect(media.retargets.contains { $0.port == 5010 })

        // A chamada continua viva: hangup não lança.
        try await client.hangup(callId: call.id)
    }

    @Test("UPDATE em diálogo (session-timer) recebe 200 OK e a chamada continua")
    func updateIsAnsweredAndCallSurvives() async throws {
        let server = try FakeSIPCallServer(username: "1001", password: "s3nh4!")
        try await server.start()
        defer { server.stop() }
        let media = FakeMediaSession()
        let (client, call) = try await establishOutgoingCall(server: server, media: media)

        server.sendInDialogRequest(method: "UPDATE", cseq: 11)

        var answered = false
        for _ in 0..<40 {
            if server.receivedMessages.contains(where: { $0.hasPrefix("SIP/2.0 200 OK") && $0.contains("11 UPDATE") }) {
                answered = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(answered, "UPDATE deveria receber 200 OK")

        try await client.hangup(callId: call.id)
    }

    @Test("DTMF: PT negociado do SDP chega à mídia e o dígito é enviado")
    func dtmfIsNegotiatedAndSent() async throws {
        let server = try FakeSIPCallServer(username: "1001", password: "s3nh4!")
        try await server.start()
        defer { server.stop() }
        let media = FakeMediaSession()
        let (client, call) = try await establishOutgoingCall(server: server, media: media)

        // O 200 OK do servidor oferta telephone-event PT 101.
        var negotiated = false
        for _ in 0..<40 {
            if media.telephoneEventPT == 101 { negotiated = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(negotiated, "PT do telephone-event deveria chegar à sessão de mídia")

        try await client.sendDTMF(callId: call.id, digit: "5")
        try await client.sendDTMF(callId: call.id, digit: "#")
        #expect(media.dtmfDigits == ["5", "#"])

        try await client.hangup(callId: call.id)
    }

    @Test("ACK e BYE carregam o route-set do Record-Route (na ordem invertida)")
    func ackAndByeFollowRecordRoute() async throws {
        let server = try FakeSIPCallServer(username: "1001", password: "s3nh4!")
        // Proxy record-routing com dois saltos: A (mais próximo do UAS)
        // vem primeiro na resposta → o cliente deve usar [B, A] invertido
        // e emitir "Route: B" antes de "Route: A".
        server.recordRoutes.withLock { $0 = ["<sip:rr-a.test;lr>", "<sip:rr-b.test;lr>"] }
        try await server.start()
        defer { server.stop() }
        let media = FakeMediaSession()
        let (client, call) = try await establishOutgoingCall(server: server, media: media)

        // ACK do 200 deve conter os dois Route, com rr-b antes de rr-a.
        var ackOk = false
        for _ in 0..<40 {
            if let ack = server.receivedMessages.first(where: { $0.hasPrefix("ACK ") }),
               let posB = ack.range(of: "Route: <sip:rr-b.test;lr>"),
               let posA = ack.range(of: "Route: <sip:rr-a.test;lr>"),
               posB.lowerBound < posA.lowerBound {
                ackOk = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(ackOk, "ACK deveria carregar Route invertido do Record-Route")

        try await client.hangup(callId: call.id)

        var byeOk = false
        for _ in 0..<40 {
            if let bye = server.receivedMessages.first(where: { $0.hasPrefix("BYE ") }),
               bye.contains("Route: <sip:rr-b.test;lr>"),
               bye.contains("Route: <sip:rr-a.test;lr>") {
                byeOk = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(byeOk, "BYE deveria carregar o route-set do diálogo")
    }
}
