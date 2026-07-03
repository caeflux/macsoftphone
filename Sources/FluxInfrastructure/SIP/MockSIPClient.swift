import Foundation
import FluxDomain

/// Engine SIP simulada — USADA EXCLUSIVAMENTE PELA SUÍTE DE TESTES.
/// O app de produção usa apenas a engine real (decisão registrada em
/// docs/10_PROJECT_STATUS.md: simulação no app confundia QA em campo).
/// Permanece aqui como referência de contrato do SIPClientProtocol e motor
/// dos testes de AppState/fluxos que não dependem de rede.
///
/// Comportamento determinístico:
/// - `register()` percorre `registering → registered` respeitando `stepDelay`.
/// - Conta com senha vazia simula falha de autenticação, permitindo testar
///   o fluxo de erro sem credencial real.
/// - `makeCall` progride `dialing → ringing → active` em background.
/// - `simulateIncomingCall(from:)` permite exercitar o fluxo de entrada.
///
/// O fluxo `events` suporta um único consumidor (AppState), como documentado
/// em `SIPClientProtocol`.
public actor MockSIPClient: SIPClientProtocol {
    public nonisolated let events: AsyncStream<SIPEvent>
    private let continuation: AsyncStream<SIPEvent>.Continuation

    private let stepDelay: Duration
    private var account: SIPAccount?
    private var registrationState: RegistrationState = .idle
    /// Geração da tentativa de registro. configure/unregister incrementam,
    /// invalidando qualquer register() que esteja dormindo — checar só o
    /// enum de estado não basta (duas tentativas concorrentes ficam ambas
    /// em .registering).
    private var registrationAttempt = 0
    private var activeCall: CallSession?
    private var isMuted = false

    /// Narração para a tela de Diagnóstico — cada linha se declara simulação
    /// para nunca passar por tráfego real.
    private let diagnostics: (@Sendable (String) -> Void)?

    public init(
        stepDelay: Duration = .milliseconds(600),
        diagnostics: (@Sendable (String) -> Void)? = nil
    ) {
        self.stepDelay = stepDelay
        self.diagnostics = diagnostics
        (events, continuation) = AsyncStream.makeStream(of: SIPEvent.self)
    }

    private func log(_ message: String) {
        diagnostics?("SIMULAÇÃO — \(message)")
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Registro

    public func configure(account: SIPAccount) async throws {
        registrationAttempt += 1
        self.account = account
        transition(to: .idle)
    }

    public func register() async throws {
        guard let account else { throw SIPClientError.notConfigured }

        log("registro fictício de \(LogSanitizer.maskUsername(account.username))@\(account.domain) — NENHUM servidor é contactado; a senha não é validada")
        registrationAttempt += 1
        let attempt = registrationAttempt
        transition(to: .registering)
        do {
            try await Task.sleep(for: stepDelay)
        } catch {
            // Task cancelada (ex.: AppState substituiu a operação): abandona
            // sem transicionar — quem cancelou definirá o próximo estado.
            return
        }

        // O sleep libera o actor (reentrância): se configure/unregister/outro
        // register rodou nesse meio-tempo, o comando mais recente vence e
        // esta tentativa (com seu snapshot de conta) é abandonada.
        guard attempt == registrationAttempt, registrationState == .registering else { return }

        // Senha vazia simula 401/403 do servidor.
        guard !account.password.isEmpty else {
            transition(to: .failed(.authenticationFailed))
            throw SIPClientError.authenticationFailed
        }

        transition(to: .registered)
    }

    public func unregister() async {
        registrationAttempt += 1
        // A engine não retém credenciais após desregistro explícito
        // (docs/05): novo registro exige novo configure().
        account = nil
        transition(to: .disconnected)
    }

    // MARK: - Chamadas

    @discardableResult
    public func makeCall(to destination: String) async throws -> CallSession {
        guard registrationState == .registered else { throw SIPClientError.notRegistered }
        guard activeCall?.state.isLive != true else { throw SIPClientError.alreadyInCall }
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw SIPClientError.invalidDestination }

        let session = CallSession(
            id: UUID().uuidString,
            direction: .outgoing,
            remoteNumber: trimmed,
            state: .dialing,
            createdAt: Date()
        )
        activeCall = session
        continuation.yield(.callStateChanged(session))
        log("chamada fictícia para \(LogSanitizer.maskNumber(trimmed)) — sem INVITE, sem áudio real")

        Task { await self.progressOutgoingCall(id: session.id) }
        return session
    }

    public func answer(callId: String) async throws {
        // Só chamada de entrada ainda tocando pode ser atendida — impede
        // "ressuscitar" uma chamada já encerrada com o mesmo id.
        guard var call = activeCall, call.id == callId, call.state == .incoming else {
            throw SIPClientError.callNotFound(id: callId)
        }
        call = call.with(state: .active, connectedAt: Date())
        activeCall = call
        continuation.yield(.callStateChanged(call))
    }

    public func reject(callId: String) async throws {
        guard let call = activeCall, call.id == callId, call.state == .incoming else {
            throw SIPClientError.callNotFound(id: callId)
        }
        finish(call: call, reason: .rejected)
    }

    public func hangup(callId: String) async throws {
        guard let call = activeCall, call.id == callId, call.state.isLive else {
            throw SIPClientError.callNotFound(id: callId)
        }
        let ending = call.with(state: .ending)
        activeCall = ending
        continuation.yield(.callStateChanged(ending))
        finish(call: ending, reason: .localHangup)
    }

    public func sendDTMF(callId: String, digit: Character) async throws {
        guard let call = activeCall, call.id == callId, call.state == .active else {
            throw SIPClientError.callNotFound(id: callId)
        }
        // Mock: DTMF é aceito silenciosamente.
    }

    public func setMuted(_ muted: Bool) async {
        isMuted = muted
        continuation.yield(.audioRouteChanged)
    }

    // MARK: - Ferramentas de simulação (apenas mock)

    /// Injeta uma chamada de entrada, como se o servidor tivesse enviado INVITE.
    public func simulateIncomingCall(
        from number: String,
        displayName: String? = nil,
        missedAfter: Duration? = nil
    ) {
        guard activeCall?.state.isLive != true else { return }
        let session = CallSession(
            id: UUID().uuidString,
            direction: .incoming,
            remoteNumber: number,
            remoteDisplayName: displayName,
            state: .incoming,
            createdAt: Date()
        )
        activeCall = session
        continuation.yield(.incomingCall(session))

        if let missedAfter {
            Task { await self.expireIncomingCall(id: session.id, after: missedAfter) }
        }
    }

    /// Simula queda de rede derrubando o registro.
    public func simulateNetworkLoss() {
        transition(to: .failed(.networkUnavailable))
    }

    // MARK: - Internos

    /// Chamador "desistiu": entrada ainda tocando expira como perdida.
    private func expireIncomingCall(id: String, after delay: Duration) async {
        try? await Task.sleep(for: delay)
        guard let call = activeCall, call.id == id, call.state == .incoming else { return }
        finish(call: call, reason: .missed)
    }

    private func progressOutgoingCall(id: String) async {
        try? await Task.sleep(for: stepDelay)
        guard var call = activeCall, call.id == id, call.state == .dialing else { return }
        call = call.with(state: .ringing)
        activeCall = call
        continuation.yield(.callStateChanged(call))

        try? await Task.sleep(for: stepDelay)
        guard var ringing = activeCall, ringing.id == id, ringing.state == .ringing else { return }
        ringing = ringing.with(state: .active, connectedAt: Date())
        activeCall = ringing
        continuation.yield(.callStateChanged(ringing))
    }

    private func finish(call: CallSession, reason: CallEndReason) {
        let ended = call.with(state: .ended(reason: reason), endedAt: Date())
        activeCall = ended
        continuation.yield(.callStateChanged(ended))
    }

    private func transition(to state: RegistrationState) {
        registrationState = state
        continuation.yield(.registrationChanged(state))
    }
}
