import Foundation
import Network
import FluxDomain

/// Engine SIP nativa (Network.framework) — Ciclo 5.
///
/// Etapa 1: REGISTER com digest auth, re-registro e desregistro.
/// Etapa 2: chamadas com áudio real — INVITE/SDP, ACK, BYE, CANCEL, chamadas
/// de entrada, e mídia RTP G.711 via `MediaSessionProtocol`.
///
/// Um loop de recepção contínuo roteia respostas para transações em aberto
/// (chave `branch|método`) e trata requisições do servidor (INVITE, BYE,
/// CANCEL, OPTIONS). Como no mock, `events` tem consumidor único (AppState).
public actor NativeSIPClient: SIPClientProtocol {
    public typealias MediaFactory = @Sendable () throws -> any MediaSessionProtocol

    public nonisolated let events: AsyncStream<SIPEvent>
    private let continuation: AsyncStream<SIPEvent>.Continuation

    private let userAgent: String
    private let registrationExpiry: Int
    private let requestTimeout: Duration
    /// Janela para o destino atender depois do primeiro provisional (180).
    private let answerTimeout: Duration
    private let mediaFactory: MediaFactory

    private var account: SIPAccount?
    private var connection: NWConnection?
    private var localEndpoint: (host: String, port: Int) = ("0.0.0.0", 0)
    private var receiveTask: Task<Void, Never>?

    private var registrationState: RegistrationState = .idle
    private var registrationCallId = ""
    private var registrationFromTag = ""
    private var registrationCSeq = 0
    /// Geração de comando — configure/register/unregister invalidam
    /// operações antigas ainda em voo.
    private var attempt = 0
    private var reregisterTask: Task<Void, Never>?

    // Transações em aberto: respostas roteadas por "branch|método".
    private var transactions: [String: AsyncStream<SIPResponse>.Continuation] = [:]
    private var transactionWatchdogs: [String: Task<Void, Never>] = [:]

    // Chamada única em andamento (MVP: uma por vez, como o mock).
    private struct CallContext {
        var session: CallSession
        var dialog: SIPDialog
        var media: (any MediaSessionProtocol)?
        var negotiatedCodec: G711Codec?
        var remoteMedia: SDP.RemoteMedia?
        /// Branch do INVITE de saída (para CANCEL) ou o request de entrada
        /// (para responder 200/486/487).
        var outgoingInviteBranch: String?
        var incomingInvite: SIPRequest?
        var cancelRequested = false
        /// Último 200 OK enviado a um INVITE (atendimento ou re-INVITE) —
        /// retransmitido se o INVITE for reenviado (ACK perdido em UDP).
        var incomingOkResponse: String?
        /// CSeq do último INVITE respondido — distingue retransmissão
        /// (mesmo CSeq) de um novo re-INVITE (CSeq maior).
        var lastHandledInviteCSeq: Int?
    }

    private struct SIPDialog {
        let callId: String
        let localTag: String
        var remoteTag: String?
        let localURI: String
        let remoteURI: String
        var remoteTarget: String?
        var cseq: Int
        /// Route-set do diálogo (RFC 3261 §12): Record-Route do 200 OK
        /// invertido (quando originamos) ou do INVITE na ordem (quando
        /// atendemos). ACK/BYE sem ele não atravessam proxies record-routing.
        var routeSet: [String] = []
    }

    private var call: CallContext?

    /// Narração sanitizada para a tela de Diagnóstico (nunca senha/token;
    /// números mascarados). Evidencia o tráfego real com o servidor.
    private let diagnostics: (@Sendable (String) -> Void)?

    public init(
        userAgent: String,
        registrationExpiry: Int = 300,
        requestTimeout: Duration = .seconds(6),
        answerTimeout: Duration = .seconds(120),
        mediaFactory: @escaping MediaFactory = { try RTPMediaSession() },
        diagnostics: (@Sendable (String) -> Void)? = nil
    ) {
        self.userAgent = userAgent
        self.registrationExpiry = max(60, registrationExpiry)
        self.requestTimeout = requestTimeout
        self.answerTimeout = answerTimeout
        self.mediaFactory = mediaFactory
        self.diagnostics = diagnostics
        (events, continuation) = AsyncStream.makeStream(of: SIPEvent.self)
    }

    private func log(_ message: String) {
        diagnostics?("SIP real — \(message)")
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Registro

    public func configure(account: SIPAccount) async throws {
        attempt += 1
        reregisterTask?.cancel()
        await endActiveCallQuietly()
        self.account = account
        registrationCallId = UUID().uuidString
        registrationFromTag = String(UUID().uuidString.prefix(10)).lowercased()
        registrationCSeq = 0
        closeConnection()
        transition(.idle)
    }

    public func register() async throws {
        guard let account else { throw SIPClientError.notConfigured }
        attempt += 1
        let myAttempt = attempt
        reregisterTask?.cancel()
        transition(.registering)

        do {
            try await performRegister(account: account, expires: registrationExpiry)
            guard myAttempt == attempt else { return }
            transition(.registered)
            scheduleReregistration(account: account)
        } catch let error as SIPClientError {
            guard myAttempt == attempt else { return }
            transition(.failed(failureReason(for: error)))
            throw error
        } catch {
            guard myAttempt == attempt else { return }
            transition(.failed(.unknown))
            throw SIPClientError.engineFailure(code: -1)
        }
    }

    public func unregister() async {
        attempt += 1
        reregisterTask?.cancel()
        await endActiveCallQuietly()
        if let account, registrationState == .registered {
            try? await performRegister(account: account, expires: 0)
        }
        account = nil
        closeConnection()
        transition(.disconnected)
    }

    // MARK: - Chamada de saída

    @discardableResult
    public func makeCall(to destination: String) async throws -> CallSession {
        guard let account else { throw SIPClientError.notConfigured }
        guard registrationState == .registered else { throw SIPClientError.notRegistered }
        guard call?.session.state.isLive != true else { throw SIPClientError.alreadyInCall }
        let target = destination.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { throw SIPClientError.invalidDestination }

        let media: any MediaSessionProtocol
        do {
            media = try mediaFactory()
        } catch {
            throw SIPClientError.engineFailure(code: -2)
        }

        let dialog = SIPDialog(
            callId: UUID().uuidString,
            localTag: String(UUID().uuidString.prefix(10)).lowercased(),
            remoteTag: nil,
            localURI: "sip:\(account.username)@\(account.domain)",
            remoteURI: "sip:\(target)@\(account.domain)",
            remoteTarget: nil,
            cseq: 1
        )
        let session = CallSession(
            id: dialog.callId,
            direction: .outgoing,
            remoteNumber: target,
            state: .dialing,
            createdAt: Date()
        )
        call = CallContext(session: session, dialog: dialog, media: media)
        yieldCall(session)
        log("INVITE → \(LogSanitizer.maskNumber(target)) via \(account.domain) (RTP local \(media.localRTPPort))")

        Task { await self.runOutgoingInvite(account: account) }
        return session
    }

    /// PT que oferecemos para telephone-event (DTMF) nas nossas ofertas.
    private static let offeredTelephoneEventPT = 101

    private func runOutgoingInvite(account: SIPAccount) async {
        guard let context = call else { return }
        let sdp = SDP.audioDescription(
            sessionId: sdpSessionId(),
            host: localEndpoint.host,
            rtpPort: context.media?.localRTPPort ?? 0,
            codecs: [.pcmu, .pcma],
            telephoneEventPayloadType: Self.offeredTelephoneEventPT
        )
        do {
            let response = try await sendInvite(account: account, sdp: sdp, authorization: nil)
            await handleInviteFinalResponse(response, account: account, sdp: sdp, isRetry: false)
        } catch {
            failCall(reason: .networkUnavailable)
        }
    }

    private func sendInvite(
        account: SIPAccount,
        sdp: String,
        authorization: (name: String, value: String)?
    ) async throws -> SIPResponse {
        guard var context = call else { throw SIPClientError.callNotFound(id: "") }
        let branch = newBranch()
        context.outgoingInviteBranch = branch
        context.dialog.cseq = authorization == nil ? context.dialog.cseq : context.dialog.cseq + 1
        call = context

        var headers = [
            ("From", "<\(context.dialog.localURI)>;tag=\(context.dialog.localTag)"),
            ("To", "<\(context.dialog.remoteURI)>"),
            ("Call-ID", context.dialog.callId),
            ("CSeq", "\(context.dialog.cseq) INVITE"),
            ("Contact", SIPRequestBuilder.contact(account: account, host: localEndpoint.host, port: localEndpoint.port)),
            ("User-Agent", userAgent)
        ]
        if let authorization {
            headers.append((authorization.name, authorization.value))
        }
        let invite = SIPRequestBuilder.request(
            method: "INVITE",
            uri: context.dialog.remoteURI,
            via: SIPRequestBuilder.via(account: account, host: localEndpoint.host, port: localEndpoint.port, branch: branch),
            headers: headers,
            body: sdp,
            contentType: "application/sdp"
        )
        return try await performTransaction(
            message: invite,
            branch: branch,
            method: "INVITE",
            provisionalHandler: { [weak self] response in
                Task { await self?.handleInviteProvisional(response) }
            }
        )
    }

    private func handleInviteProvisional(_ response: SIPResponse) {
        guard var context = call, context.session.direction == .outgoing else { return }
        guard response.statusCode == 180 || response.statusCode == 183 else { return }

        // Usuário desistiu antes do primeiro provisional: o CANCEL foi adiado
        // (RFC 3261 proíbe CANCEL antes de 1xx). Agora que o 1xx chegou, envia.
        if context.cancelRequested {
            if let account { Task { await self.sendCancel(account: account) } }
            return
        }
        guard context.session.state == .dialing else { return }
        context.session = context.session.with(state: .ringing)
        call = context
        yieldCall(context.session)
    }

    private func handleInviteFinalResponse(
        _ response: SIPResponse,
        account: SIPAccount,
        sdp: String,
        isRetry: Bool
    ) async {
        guard var context = call, context.session.direction == .outgoing else { return }

        // Tag remota da resposta final compõe o diálogo (necessária no ACK).
        if let toHeader = response.firstHeader("To"),
           let tag = SIPHeaderTools.tag(fromHeaderValue: toHeader) {
            context.dialog.remoteTag = tag
        }
        if let contactHeader = response.firstHeader("Contact"),
           let target = SIPHeaderTools.uri(fromHeaderValue: contactHeader) {
            context.dialog.remoteTarget = target
        }
        // Route-set: Record-Route da resposta, invertido para o originador
        // (RFC 3261 §12.1.2). Sem isso o ACK não atravessa o proxy.
        let recordRoutes = SIPHeaderTools.routeEntries(
            fromHeaderValues: response.headers(named: "Record-Route")
        )
        if !recordRoutes.isEmpty {
            context.dialog.routeSet = recordRoutes.reversed()
            log("route-set do diálogo: \(context.dialog.routeSet.joined(separator: " , "))")
        }
        call = context

        switch response.statusCode {
        case 200:
            await sendAck(for: response, account: account, within: context.dialog)
            if context.cancelRequested {
                // Atendeu depois do usuário desistir: encerra educadamente.
                await sendBye(account: account)
                endCall(reason: .localHangup)
                return
            }
            guard let remote = SDP.parseRemoteMedia(response.body),
                  let codec = remote.negotiatedCodec else {
                log("← 200 OK mas SDP sem codec compatível — encerrando com BYE")
                await sendBye(account: account)
                failCall(reason: .serverError)
                return
            }
            do {
                try await call?.media?.start(
                    remoteHost: remote.connectionAddress,
                    remotePort: remote.audioPort,
                    codec: codec
                )
            } catch {
                AppLog.sip.error("Falha ao iniciar mídia: \(String(describing: error), privacy: .public)")
                log("falha ao iniciar mídia RTP: \(error)")
                await sendBye(account: account)
                failCall(reason: .unknown)
                return
            }
            if var active = call {
                active.negotiatedCodec = codec
                active.remoteMedia = remote
                active.session = active.session.with(state: .active, connectedAt: Date())
                call = active
                yieldCall(active.session)
                await active.media?.setTelephoneEventPayloadType(remote.telephoneEventPayloadType)
                let dtmfNote = remote.telephoneEventPayloadType.map { "; DTMF RFC2833 PT \($0)" } ?? "; sem DTMF fora de banda"
                log("← 200 OK; ACK enviado; áudio RTP \(codec.sdpName) com \(remote.connectionAddress):\(remote.audioPort)\(dtmfNote)")
            }

        case 401, 407:
            await sendAckForFailure(response, account: account, within: context.dialog)
            guard !isRetry,
                  let challengeHeader = response.firstHeader(response.statusCode == 401 ? "WWW-Authenticate" : "Proxy-Authenticate"),
                  let challenge = SIPDigestChallenge.parse(fromHeader: challengeHeader)
            else {
                failCall(reason: .serverError)
                return
            }
            let authorization = SIPDigestAuthenticator.authorizationHeaderValue(
                username: account.authUsername ?? account.username,
                password: account.password,
                method: "INVITE",
                uri: context.dialog.remoteURI,
                challenge: challenge,
                cnonce: String(UUID().uuidString.prefix(16)).lowercased(),
                nonceCount: 1
            )
            do {
                let retry = try await sendInvite(
                    account: account,
                    sdp: sdp,
                    authorization: (response.statusCode == 401 ? "Authorization" : "Proxy-Authorization", authorization)
                )
                await handleInviteFinalResponse(retry, account: account, sdp: sdp, isRetry: true)
            } catch {
                failCall(reason: .networkUnavailable)
            }

        case 486, 600, 603:
            log("← \(response.statusCode) \(response.reasonPhrase) — destino ocupado/recusou")
            await sendAckForFailure(response, account: account, within: context.dialog)
            endCall(reason: .rejected)

        case 487:
            await sendAckForFailure(response, account: account, within: context.dialog)
            endCall(reason: .cancelled)

        case 404, 484, 485:
            log("← \(response.statusCode) \(response.reasonPhrase) — destino inválido/não encontrado")
            await sendAckForFailure(response, account: account, within: context.dialog)
            failCall(reason: .invalidDestination)

        default:
            log("← \(response.statusCode) \(response.reasonPhrase)")
            await sendAckForFailure(response, account: account, within: context.dialog)
            // O motivo do servidor chega ao usuário (ex.: rota bloqueada
            // no PABX) — "falha" genérica esconderia um problema de
            // configuração do servidor, não do app.
            continuation.yield(.error(.serverRejected(
                code: response.statusCode,
                reason: response.reasonPhrase
            )))
            failCall(reason: .serverError)
        }
    }

    /// ACK para resposta 2xx: nova transação, roteado ao Contact remoto
    /// através do route-set do diálogo.
    private func sendAck(for response: SIPResponse, account: SIPAccount, within dialog: SIPDialog) async {
        let uri = dialog.remoteTarget ?? dialog.remoteURI
        let toHeader = response.firstHeader("To") ?? "<\(dialog.remoteURI)>"
        let ack = SIPRequestBuilder.request(
            method: "ACK",
            uri: uri,
            via: SIPRequestBuilder.via(account: account, host: localEndpoint.host, port: localEndpoint.port, branch: newBranch()),
            routes: dialog.routeSet,
            headers: [
                ("From", "<\(dialog.localURI)>;tag=\(dialog.localTag)"),
                ("To", toHeader),
                ("Call-ID", dialog.callId),
                ("CSeq", "\(dialog.cseq) ACK"),
                ("User-Agent", userAgent)
            ],
            body: nil
        )
        try? await sendRaw(ack)
    }

    /// ACK para resposta final não-2xx: mesmo branch do INVITE.
    private func sendAckForFailure(_ response: SIPResponse, account: SIPAccount, within dialog: SIPDialog) async {
        guard let branch = call?.outgoingInviteBranch else { return }
        let toHeader = response.firstHeader("To") ?? "<\(dialog.remoteURI)>"
        let ack = SIPRequestBuilder.request(
            method: "ACK",
            uri: dialog.remoteURI,
            via: SIPRequestBuilder.via(account: account, host: localEndpoint.host, port: localEndpoint.port, branch: branch),
            headers: [
                ("From", "<\(dialog.localURI)>;tag=\(dialog.localTag)"),
                ("To", toHeader),
                ("Call-ID", dialog.callId),
                ("CSeq", "\(dialog.cseq) ACK"),
                ("User-Agent", userAgent)
            ],
            body: nil
        )
        try? await sendRaw(ack)
    }

    // MARK: - Atender / recusar / encerrar

    public func answer(callId: String) async throws {
        guard let account else { throw SIPClientError.notConfigured }
        guard var context = call, context.session.id == callId, context.session.state == .incoming,
              let invite = context.incomingInvite
        else { throw SIPClientError.callNotFound(id: callId) }

        guard let remote = SDP.parseRemoteMedia(invite.body),
              let codec = remote.negotiatedCodec else {
            try? await sendRaw(SIPRequestBuilder.response(
                status: 488, reason: "Not Acceptable Here",
                to: invite,
                toHeader: incomingToHeader(invite: invite, dialog: context.dialog)
            ))
            failCall(reason: .serverError)
            throw SIPClientError.engineFailure(code: 488)
        }

        let media: any MediaSessionProtocol
        do {
            media = try mediaFactory()
        } catch {
            try? await sendRaw(SIPRequestBuilder.response(
                status: 500, reason: "Server Internal Error",
                to: invite,
                toHeader: incomingToHeader(invite: invite, dialog: context.dialog)
            ))
            failCall(reason: .unknown)
            throw SIPClientError.engineFailure(code: -2)
        }

        let answerSDP = SDP.audioDescription(
            sessionId: sdpSessionId(),
            host: localEndpoint.host,
            rtpPort: media.localRTPPort,
            codecs: [codec],
            // Espelha o PT de telephone-event ofertado pelo chamador.
            telephoneEventPayloadType: remote.telephoneEventPayloadType
        )
        let ok = SIPRequestBuilder.response(
            status: 200, reason: "OK",
            to: invite,
            toHeader: incomingToHeader(invite: invite, dialog: context.dialog),
            extraHeaders: [
                ("Contact", SIPRequestBuilder.contact(account: account, host: localEndpoint.host, port: localEndpoint.port))
            ],
            body: answerSDP,
            contentType: "application/sdp"
        )
        try await sendRaw(ok)

        do {
            try await media.start(
                remoteHost: remote.connectionAddress,
                remotePort: remote.audioPort,
                codec: codec
            )
        } catch {
            AppLog.sip.error("Falha ao iniciar mídia: \(String(describing: error), privacy: .public)")
            await sendBye(account: account)
            failCall(reason: .unknown)
            throw SIPClientError.engineFailure(code: -2)
        }

        context.media = media
        context.negotiatedCodec = codec
        context.remoteMedia = remote
        context.incomingOkResponse = ok // para retransmitir se o ACK se perder
        context.lastHandledInviteCSeq = SIPHeaderTools.cseq(
            fromHeaderValue: invite.firstHeader("CSeq") ?? ""
        )?.number
        context.session = context.session.with(state: .active, connectedAt: Date())
        call = context
        yieldCall(context.session)
        await media.setTelephoneEventPayloadType(remote.telephoneEventPayloadType)
        log("chamada de entrada atendida; áudio RTP \(codec.sdpName) com \(remote.connectionAddress):\(remote.audioPort)")
    }

    public func reject(callId: String) async throws {
        guard let context = call, context.session.id == callId, context.session.state == .incoming,
              let invite = context.incomingInvite
        else { throw SIPClientError.callNotFound(id: callId) }

        try? await sendRaw(SIPRequestBuilder.response(
            status: 486, reason: "Busy Here",
            to: invite,
            toHeader: incomingToHeader(invite: invite, dialog: context.dialog)
        ))
        endCall(reason: .rejected)
    }

    public func hangup(callId: String) async throws {
        guard let account else { throw SIPClientError.notConfigured }
        guard var context = call, context.session.id == callId, context.session.state.isLive
        else { throw SIPClientError.callNotFound(id: callId) }

        switch context.session.state {
        case .incoming:
            try await reject(callId: callId)

        case .dialing, .ringing:
            // Saída ainda não atendida: CANCEL; o 487 encerra a chamada.
            // Mas só se já recebemos um provisional (RFC 3261: CANCEL exige
            // 1xx). Em .dialing (sem 1xx), marca e o provisional handler envia.
            let hadProvisional = context.session.state == .ringing
            context.cancelRequested = true
            context.session = context.session.with(state: .ending)
            call = context
            yieldCall(context.session)
            if hadProvisional {
                await sendCancel(account: account)
            }

        default:
            context.session = context.session.with(state: .ending)
            call = context
            yieldCall(context.session)
            log("BYE → encerrando a chamada")
            await sendBye(account: account)
            endCall(reason: .localHangup)
        }
    }

    public func sendDTMF(callId: String, digit: Character) async throws {
        guard let context = call, context.session.id == callId,
              context.session.state == .active,
              let media = context.media
        else { throw SIPClientError.callNotFound(id: callId) }

        do {
            try await media.sendDTMF(digit: digit)
            log("DTMF '\(digit)' enviado (RFC 2833)")
        } catch {
            // telephone-event não negociado nesta chamada.
            log("DTMF indisponível: \(error)")
            throw SIPClientError.notSupported
        }
    }

    public func setMuted(_ muted: Bool) async {
        await call?.media?.setMuted(muted)
        continuation.yield(.audioRouteChanged)
    }

    private func sendCancel(account: SIPAccount) async {
        guard let context = call, let branch = context.outgoingInviteBranch else { return }
        let cancel = SIPRequestBuilder.request(
            method: "CANCEL",
            uri: context.dialog.remoteURI,
            via: SIPRequestBuilder.via(account: account, host: localEndpoint.host, port: localEndpoint.port, branch: branch),
            headers: [
                ("From", "<\(context.dialog.localURI)>;tag=\(context.dialog.localTag)"),
                ("To", "<\(context.dialog.remoteURI)>"),
                ("Call-ID", context.dialog.callId),
                ("CSeq", "\(context.dialog.cseq) CANCEL"),
                ("User-Agent", userAgent)
            ],
            body: nil
        )
        _ = try? await performTransaction(message: cancel, branch: branch, method: "CANCEL", provisionalHandler: nil)
    }

    private func sendBye(account: SIPAccount) async {
        guard var context = call else { return }
        context.dialog.cseq += 1
        call = context
        let dialog = context.dialog

        var toValue = "<\(dialog.remoteURI)>"
        if let remoteTag = dialog.remoteTag {
            toValue += ";tag=\(remoteTag)"
        }
        let branch = newBranch()
        let bye = SIPRequestBuilder.request(
            method: "BYE",
            uri: dialog.remoteTarget ?? dialog.remoteURI,
            via: SIPRequestBuilder.via(account: account, host: localEndpoint.host, port: localEndpoint.port, branch: branch),
            routes: dialog.routeSet,
            headers: [
                ("From", "<\(dialog.localURI)>;tag=\(dialog.localTag)"),
                ("To", toValue),
                ("Call-ID", dialog.callId),
                ("CSeq", "\(dialog.cseq) BYE"),
                ("User-Agent", userAgent)
            ],
            body: nil
        )
        _ = try? await performTransaction(message: bye, branch: branch, method: "BYE", provisionalHandler: nil)
    }

    // MARK: - Requisições recebidas do servidor

    private func handleIncomingRequest(_ request: SIPRequest) async {
        let isForActiveCall = call?.dialog.callId == request.firstHeader("Call-ID")

        switch request.method {
        case "OPTIONS":
            try? await sendRaw(SIPRequestBuilder.response(
                status: 200, reason: "OK",
                to: request,
                toHeader: request.firstHeader("To") ?? "<sip:unknown>"
            ))

        case "INVITE":
            await handleIncomingInvite(request)

        case "CANCEL":
            log("← CANCEL")
            try? await sendRaw(SIPRequestBuilder.response(
                status: 200, reason: "OK",
                to: request,
                toHeader: request.firstHeader("To") ?? "<sip:unknown>"
            ))
            if let context = call, context.session.state == .incoming,
               context.dialog.callId == request.firstHeader("Call-ID"),
               let invite = context.incomingInvite {
                try? await sendRaw(SIPRequestBuilder.response(
                    status: 487, reason: "Request Terminated",
                    to: invite,
                    toHeader: incomingToHeader(invite: invite, dialog: context.dialog)
                ))
                endCall(reason: .missed)
            }

        case "BYE":
            // O motivo do desligamento (quando o servidor informa) é ouro
            // para diagnóstico — ex.: "Q.850;cause=16" ou causa do PABX.
            let reason = request.firstHeader("Reason")
                ?? request.firstHeader("X-Asterisk-HangupCause")
                ?? request.firstHeader("X-HangupCause")
            try? await sendRaw(SIPRequestBuilder.response(
                status: 200, reason: "OK",
                to: request,
                toHeader: request.firstHeader("To") ?? "<sip:unknown>"
            ))
            if isForActiveCall, call?.session.state.isLive == true {
                log("← BYE do interlocutor\(reason.map { " — motivo: \($0)" } ?? "") — chamada encerrada pelo outro lado")
                endCall(reason: .remoteHangup)
            }

        case "ACK":
            break // 200 do atendimento confirmado; mídia já está ativa.

        case "UPDATE":
            // Session-timer/renegociação em diálogo: precisa de 200 — sem
            // resposta o servidor derruba a chamada.
            log("← UPDATE\(isForActiveCall ? " (na chamada atual)" : "")")
            if isForActiveCall {
                await answerInDialogMediaOffer(request, method: "UPDATE")
            } else {
                try? await sendRaw(SIPRequestBuilder.response(
                    status: 481, reason: "Call/Transaction Does Not Exist",
                    to: request,
                    toHeader: request.firstHeader("To") ?? "<sip:unknown>"
                ))
            }

        case "NOTIFY", "INFO", "MESSAGE":
            // Aceitos silenciosamente (MWI, keep-alives, DTMF via INFO):
            // 200 evita que servidores estritos derrubem o diálogo por 501.
            log("← \(request.method) — respondido 200")
            try? await sendRaw(SIPRequestBuilder.response(
                status: 200, reason: "OK",
                to: request,
                toHeader: request.firstHeader("To") ?? "<sip:unknown>"
            ))

        case "REFER":
            log("← REFER (transferência) — não suportado ainda; 501")
            try? await sendRaw(SIPRequestBuilder.response(
                status: 501, reason: "Not Implemented",
                to: request,
                toHeader: request.firstHeader("To") ?? "<sip:unknown>"
            ))

        default:
            log("← \(request.method) — método desconhecido; 501")
            try? await sendRaw(SIPRequestBuilder.response(
                status: 501, reason: "Not Implemented",
                to: request,
                toHeader: request.firstHeader("To") ?? "<sip:unknown>"
            ))
        }
    }

    /// Responde 200 OK a re-INVITE/UPDATE em diálogo, renegociando a mídia
    /// quando a oferta traz SDP (destino/codec podem mudar — ex.: PABX
    /// movendo o fluxo RTP). Ignorar essas requisições derruba a chamada:
    /// o servidor desiste e envia BYE segundos após o atendimento.
    private func answerInDialogMediaOffer(_ request: SIPRequest, method: String) async {
        guard var context = call, let account else { return }

        var codec = context.negotiatedCodec ?? .pcmu
        if !request.body.isEmpty, let remote = SDP.parseRemoteMedia(request.body) {
            if let newCodec = remote.negotiatedCodec {
                codec = newCodec
            }
            let destinationChanged = context.remoteMedia?.connectionAddress != remote.connectionAddress
                || context.remoteMedia?.audioPort != remote.audioPort
                || context.negotiatedCodec != codec
            if destinationChanged {
                do {
                    try await context.media?.retarget(
                        remoteHost: remote.connectionAddress,
                        remotePort: remote.audioPort,
                        codec: codec
                    )
                    log("mídia redirecionada para \(remote.connectionAddress):\(remote.audioPort) (\(codec.sdpName))")
                } catch {
                    log("falha ao redirecionar mídia: \(error)")
                }
            }
            context.remoteMedia = remote
            context.negotiatedCodec = codec
            await context.media?.setTelephoneEventPayloadType(remote.telephoneEventPayloadType)
        }

        // Resposta: SDP espelhando nossa mídia atual quando a oferta trouxe
        // SDP; sem corpo para UPDATE de session-timer puro.
        let body: String? = request.body.isEmpty ? nil : SDP.audioDescription(
            sessionId: sdpSessionId(),
            host: localEndpoint.host,
            rtpPort: context.media?.localRTPPort ?? 0,
            codecs: [codec],
            telephoneEventPayloadType: context.remoteMedia?.telephoneEventPayloadType
        )
        let toBase = request.firstHeader("To") ?? "<\(context.dialog.localURI)>"
        let toHeader = SIPHeaderTools.tag(fromHeaderValue: toBase) != nil
            ? toBase
            : "\(toBase);tag=\(context.dialog.localTag)"
        let ok = SIPRequestBuilder.response(
            status: 200, reason: "OK",
            to: request,
            toHeader: toHeader,
            extraHeaders: [
                ("Contact", SIPRequestBuilder.contact(account: account, host: localEndpoint.host, port: localEndpoint.port))
            ],
            body: body,
            contentType: body != nil ? "application/sdp" : nil
        )
        try? await sendRaw(ok)
        log("→ 200 OK para \(method) em diálogo")

        if method == "INVITE" {
            context.incomingOkResponse = ok
            context.lastHandledInviteCSeq = SIPHeaderTools.cseq(
                fromHeaderValue: request.firstHeader("CSeq") ?? ""
            )?.number
        }
        call = context
    }

    private func handleIncomingInvite(_ request: SIPRequest) async {
        // Retransmissão UDP do MESMO INVITE (mesmo Call-ID da chamada atual):
        // reenvia a última resposta, sem criar chamada nova nem responder
        // ocupado — ACK/180/200 se perdem com frequência em UDP.
        if let context = call, context.dialog.callId == request.firstHeader("Call-ID") {
            let cseq = SIPHeaderTools.cseq(fromHeaderValue: request.firstHeader("CSeq") ?? "")?.number
            switch context.session.state {
            case .incoming:
                try? await sendRaw(SIPRequestBuilder.response(
                    status: 180, reason: "Ringing",
                    to: request,
                    toHeader: incomingToHeader(invite: request, dialog: context.dialog)
                ))
            case .active, .held:
                if let cseq, cseq == context.lastHandledInviteCSeq, let ok = context.incomingOkResponse {
                    // Mesmo CSeq = retransmissão (ACK perdido): reenvia o 200.
                    log("← INVITE retransmitido — reenviando 200 OK")
                    try? await sendRaw(ok)
                } else {
                    // CSeq novo = re-INVITE (renegociação do servidor).
                    log("← re-INVITE do servidor (renegociação em diálogo)")
                    await answerInDialogMediaOffer(request, method: "INVITE")
                }
            default:
                break // encerrando/encerrada: ignora a retransmissão.
            }
            return
        }
        // Já em OUTRA chamada: ocupado.
        guard call?.session.state.isLive != true else {
            try? await sendRaw(SIPRequestBuilder.response(
                status: 486, reason: "Busy Here",
                to: request,
                toHeader: (request.firstHeader("To") ?? "<sip:unknown>") + ";tag=\(String(UUID().uuidString.prefix(8)))"
            ))
            return
        }
        guard let fromHeader = request.firstHeader("From"),
              let remoteURI = SIPHeaderTools.uri(fromHeaderValue: fromHeader),
              let callId = request.firstHeader("Call-ID"),
              let account
        else { return }

        let localTag = String(UUID().uuidString.prefix(10)).lowercased()
        let dialog = SIPDialog(
            callId: callId,
            localTag: localTag,
            remoteTag: SIPHeaderTools.tag(fromHeaderValue: fromHeader),
            localURI: "sip:\(account.username)@\(account.domain)",
            remoteURI: remoteURI,
            remoteTarget: request.firstHeader("Contact").flatMap(SIPHeaderTools.uri(fromHeaderValue:)),
            cseq: SIPHeaderTools.cseq(fromHeaderValue: request.firstHeader("CSeq") ?? "")?.number ?? 1,
            // UAS: route-set na ordem em que veio no INVITE (RFC 3261 §12.1.1).
            routeSet: SIPHeaderTools.routeEntries(
                fromHeaderValues: request.headers(named: "Record-Route")
            )
        )
        let session = CallSession(
            id: callId,
            direction: .incoming,
            remoteNumber: SIPHeaderTools.user(fromURI: remoteURI) ?? remoteURI,
            remoteDisplayName: SIPHeaderTools.displayName(fromHeaderValue: fromHeader),
            state: .incoming,
            createdAt: Date()
        )
        call = CallContext(session: session, dialog: dialog, incomingInvite: request)

        try? await sendRaw(SIPRequestBuilder.response(
            status: 180, reason: "Ringing",
            to: request,
            toHeader: incomingToHeader(invite: request, dialog: dialog)
        ))
        continuation.yield(.incomingCall(session))
        log("← INVITE de \(LogSanitizer.maskNumber(session.remoteNumber)) — 180 Ringing enviado")
    }

    private func incomingToHeader(invite: SIPRequest, dialog: SIPDialog) -> String {
        let base = invite.firstHeader("To") ?? "<\(dialog.localURI)>"
        if SIPHeaderTools.tag(fromHeaderValue: base) != nil { return base }
        return base + ";tag=\(dialog.localTag)"
    }

    // MARK: - Encerramento e falha de chamada

    private func endCall(reason: CallEndReason) {
        guard let context = call else { return }
        let media = context.media
        Task { await media?.stop() }
        let ended = context.session.with(state: .ended(reason: reason), endedAt: Date())
        call = nil
        yieldCall(ended)
    }

    private func failCall(reason: CallFailureReason) {
        guard let context = call else { return }
        let media = context.media
        Task { await media?.stop() }
        let failed = context.session.with(state: .failed(error: reason), endedAt: Date())
        call = nil
        yieldCall(failed)
    }

    private func endActiveCallQuietly() async {
        guard let context = call else { return }
        await context.media?.stop()
        if context.session.state.isLive, let account {
            await sendBye(account: account)
        }
        call = nil
    }

    private func yieldCall(_ session: CallSession) {
        continuation.yield(.callStateChanged(session))
    }

    // MARK: - Fluxo REGISTER

    private func performRegister(account: SIPAccount, expires: Int) async throws {
        _ = try await ensureConnection(account: account)

        log("REGISTER \(expires == 0 ? "(desregistro) " : "")→ \(account.domain):\(account.port)/\(account.transport.rawValue.uppercased()) usuário \(LogSanitizer.maskUsername(account.username))")
        registrationCSeq += 1
        let branch = newBranch()
        let first = SIPRequestBuilder.register(.init(
            account: account,
            callId: registrationCallId,
            cseq: registrationCSeq,
            fromTag: registrationFromTag,
            branch: branch,
            localHost: localEndpoint.host,
            localPort: localEndpoint.port,
            expires: expires,
            userAgent: userAgent,
            authorization: nil
        ))
        let firstResponse = try await performTransaction(
            message: first, branch: branch, method: "REGISTER", provisionalHandler: nil
        )

        switch firstResponse.statusCode {
        case 200:
            // ATENÇÃO no diagnóstico: 200 sem challenge = o servidor aceitou
            // sem validar a senha (ex.: autenticação por IP/ACL no PABX).
            log("← 200 OK sem exigir autenticação — o servidor NÃO validou a senha (registro liberado por IP/ACL?)")
            return
        case 401, 407:
            let isProxy = firstResponse.statusCode == 407
            guard let challengeHeader = firstResponse.firstHeader(isProxy ? "Proxy-Authenticate" : "WWW-Authenticate"),
                  let challenge = SIPDigestChallenge.parse(fromHeader: challengeHeader) else {
                throw SIPClientError.engineFailure(code: firstResponse.statusCode)
            }
            log("← \(firstResponse.statusCode) challenge digest (realm \(challenge.realm)); reenviando com credenciais")
            let uri = "sip:\(account.domain)"
            let authorization = SIPDigestAuthenticator.authorizationHeaderValue(
                username: account.authUsername ?? account.username,
                password: account.password,
                method: "REGISTER",
                uri: uri,
                challenge: challenge,
                cnonce: String(UUID().uuidString.prefix(16)).lowercased(),
                nonceCount: 1
            )
            registrationCSeq += 1
            let retryBranch = newBranch()
            let second = SIPRequestBuilder.register(.init(
                account: account,
                callId: registrationCallId,
                cseq: registrationCSeq,
                fromTag: registrationFromTag,
                branch: retryBranch,
                localHost: localEndpoint.host,
                localPort: localEndpoint.port,
                expires: expires,
                userAgent: userAgent,
                authorization: (isProxy ? "Proxy-Authorization" : "Authorization", authorization)
            ))
            let secondResponse = try await performTransaction(
                message: second, branch: retryBranch, method: "REGISTER", provisionalHandler: nil
            )
            switch secondResponse.statusCode {
            case 200:
                log("← 200 OK — registrado com autenticação digest validada pelo servidor")
                return
            case 401, 403, 404, 407:
                log("← \(secondResponse.statusCode) — servidor recusou as credenciais")
                throw SIPClientError.authenticationFailed
            default:
                log("← \(secondResponse.statusCode) \(secondResponse.reasonPhrase)")
                throw SIPClientError.serverRejected(
                    code: secondResponse.statusCode,
                    reason: secondResponse.reasonPhrase
                )
            }
        case 403, 404:
            log("← \(firstResponse.statusCode) — servidor recusou o registro")
            throw SIPClientError.authenticationFailed
        default:
            log("← \(firstResponse.statusCode) \(firstResponse.reasonPhrase)")
            throw SIPClientError.serverRejected(
                code: firstResponse.statusCode,
                reason: firstResponse.reasonPhrase
            )
        }
    }

    private func scheduleReregistration(account: SIPAccount) {
        let myAttempt = attempt
        let interval = max(30, registrationExpiry - 30)
        reregisterTask = Task {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            await self.reregister(account: account, ifAttempt: myAttempt)
        }
    }

    private func reregister(account: SIPAccount, ifAttempt myAttempt: Int) async {
        guard myAttempt == attempt, registrationState == .registered else { return }
        do {
            try await performRegister(account: account, expires: registrationExpiry)
            guard myAttempt == attempt else { return }
            scheduleReregistration(account: account)
        } catch {
            guard myAttempt == attempt else { return }
            transition(.expired)
            continuation.yield(.error((error as? SIPClientError) ?? .serverUnreachable))
        }
    }

    // MARK: - Transações

    private func performTransaction(
        message: String,
        branch: String,
        method: String,
        provisionalHandler: (@Sendable (SIPResponse) -> Void)?
    ) async throws -> SIPResponse {
        let key = "\(branch)|\(method)"
        let (stream, streamContinuation) = AsyncStream.makeStream(of: SIPResponse.self)
        transactions[key] = streamContinuation
        defer { finishTransaction(key) }

        try await sendRaw(message)
        armWatchdog(key: key, timeout: requestTimeout)

        for await response in stream {
            if response.statusCode >= 200 {
                return response
            }
            provisionalHandler?(response)
            // Provisional recebido: o destino está tocando — espera maior.
            armWatchdog(key: key, timeout: answerTimeout)
        }
        // Stream finalizado sem resposta final = timeout ou conexão perdida.
        throw SIPClientError.serverUnreachable
    }

    private func finishTransaction(_ key: String) {
        transactionWatchdogs.removeValue(forKey: key)?.cancel()
        transactions.removeValue(forKey: key)?.finish()
    }

    private func armWatchdog(key: String, timeout: Duration) {
        transactionWatchdogs[key]?.cancel()
        transactionWatchdogs[key] = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.finishTransaction(key)
        }
    }

    private func routeResponse(_ response: SIPResponse) async {
        guard let via = response.firstHeader("Via"),
              let branch = SIPHeaderTools.branch(fromVia: via),
              let cseq = response.firstHeader("CSeq"),
              let method = SIPHeaderTools.cseq(fromHeaderValue: cseq)?.method
        else { return }
        if let transaction = transactions["\(branch)|\(method)"] {
            transaction.yield(response)
            return
        }
        // 200 OK de INVITE retransmitido (nosso ACK se perdeu): reenviar o
        // ACK (RFC 3261 §13.2.2.4) — sem isso o servidor desiste e envia BYE.
        if (200...299).contains(response.statusCode), method == "INVITE",
           let context = call, context.session.direction == .outgoing,
           context.dialog.callId == response.firstHeader("Call-ID"),
           let account {
            log("← 200 OK retransmitido — reenviando ACK")
            await sendAck(for: response, account: account, within: context.dialog)
        }
    }

    // MARK: - Rede

    private func ensureConnection(account: SIPAccount) async throws -> NWConnection {
        if let connection, connection.state == .ready { return connection }
        closeConnection()

        let hostName: String
        if let proxy = account.outboundProxy, !proxy.isEmpty {
            hostName = proxy
        } else {
            hostName = account.domain
        }
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: account.port)) else {
            throw SIPClientError.serverUnreachable
        }

        let parameters: NWParameters
        switch account.transport {
        case .udp: parameters = .udp
        case .tcp: parameters = .tcp
        case .tls: parameters = .tls
        }

        let conn = NWConnection(host: NWEndpoint.Host(hostName), port: port, using: parameters)
        try await start(conn)
        connection = conn
        localEndpoint = resolveLocalEndpoint(of: conn)
        startReceiveLoop(conn, transport: account.transport)
        return conn
    }

    private func startReceiveLoop(_ conn: NWConnection, transport: SIPTransport) {
        let myAttempt = attempt
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let text = try await self.receiveMessage(conn, transport: transport)
                    await self.dispatchIncoming(text)
                } catch {
                    self.receiveLoopEnded(ifAttempt: myAttempt)
                    return
                }
            }
        }
    }

    private func dispatchIncoming(_ text: String) async {
        if text.hasPrefix("SIP/2.0 ") {
            if let response = SIPResponse.parse(text) {
                await routeResponse(response)
            }
        } else if let request = SIPRequest.parse(text) {
            await handleIncomingRequest(request)
        }
    }

    private func receiveLoopEnded(ifAttempt myAttempt: Int) {
        // Conexão caiu sem ser por comando nosso: estado honesto.
        guard myAttempt == attempt else { return }
        log("conexão com o servidor caiu")
        for key in transactions.keys {
            finishTransaction(key)
        }
        if call != nil {
            failCall(reason: .networkUnavailable)
        }
        if registrationState == .registered || registrationState == .registering {
            transition(.disconnected)
        }
    }

    private func start(_ conn: NWConnection) async throws {
        let once = OnceFlag()
        let watchdog = Task { [requestTimeout] in
            try? await Task.sleep(for: requestTimeout)
            if once.peek() == false { conn.cancel() }
        }
        defer { watchdog.cancel() }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.tryClaim() { cont.resume() }
                case .failed, .cancelled:
                    if once.tryClaim() { cont.resume(throwing: SIPClientError.serverUnreachable) }
                case .setup, .preparing, .waiting:
                    break
                @unknown default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    private func sendRaw(_ message: String) async throws {
        guard let connection else { throw SIPClientError.serverUnreachable }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(message.utf8), completion: .contentProcessed { error in
                if error == nil {
                    cont.resume()
                } else {
                    cont.resume(throwing: SIPClientError.networkUnavailable)
                }
            })
        }
    }

    private func receiveMessage(_ conn: NWConnection, transport: SIPTransport) async throws -> String {
        switch transport {
        case .udp:
            return try await withCheckedThrowingContinuation { cont in
                conn.receiveMessage { data, _, _, error in
                    if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                        cont.resume(returning: text)
                    } else {
                        cont.resume(throwing: error ?? SIPClientError.serverUnreachable)
                    }
                }
            }
        case .tcp, .tls:
            var buffer = Data()
            while !buffer.containsCRLFCRLF() {
                let chunk: Data = try await withCheckedThrowingContinuation { cont in
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                        if let data, !data.isEmpty {
                            cont.resume(returning: data)
                        } else if isComplete {
                            cont.resume(throwing: SIPClientError.serverUnreachable)
                        } else {
                            cont.resume(throwing: error ?? SIPClientError.serverUnreachable)
                        }
                    }
                }
                buffer.append(chunk)
            }
            guard let text = String(data: buffer, encoding: .utf8) else {
                throw SIPClientError.serverUnreachable
            }
            return text
        }
    }

    private func resolveLocalEndpoint(of conn: NWConnection) -> (host: String, port: Int) {
        guard case .hostPort(let host, let port)? = conn.currentPath?.localEndpoint else {
            return ("0.0.0.0", 0)
        }
        let raw = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
        return (raw, Int(port.rawValue))
    }

    private func closeConnection() {
        receiveTask?.cancel()
        receiveTask = nil
        for key in transactions.keys {
            finishTransaction(key)
        }
        connection?.cancel()
        connection = nil
    }

    private func newBranch() -> String {
        "z9hG4bK\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    /// sess-id do SDP: RFC 4566 exige apenas dígitos — timestamp com ".0"
    /// causava "400 Bad Session Description" em servidores estritos.
    private func sdpSessionId() -> String {
        String(UInt64(Date().timeIntervalSince1970))
    }

    private func transition(_ state: RegistrationState) {
        registrationState = state
        continuation.yield(.registrationChanged(state))
    }

    private func failureReason(for error: SIPClientError) -> RegistrationFailureReason {
        switch error {
        case .authenticationFailed: return .authenticationFailed
        case .networkUnavailable: return .networkUnavailable
        case .serverUnreachable: return .serverUnreachable
        default: return .unknown
        }
    }
}

/// Flag resume-once thread-safe para pontes callback → async.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func tryClaim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }

    func peek() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return claimed
    }
}

private extension Data {
    func containsCRLFCRLF() -> Bool {
        range(of: Data("\r\n\r\n".utf8)) != nil
    }
}
