import Testing
import Foundation
import FluxDomain
@testable import FluxInfrastructure

@Suite("MockSIPClient")
struct MockSIPClientTests {
    private func makeAccount(password: String = "ok") -> SIPAccount {
        SIPAccount(username: "1001", password: password, domain: "sip.test.local")
    }

    @Test("registro percorre registering → registered")
    func successfulRegistration() async throws {
        let client = MockSIPClient(stepDelay: .zero)

        let collector = Task {
            var states: [RegistrationState] = []
            for await event in client.events {
                if case .registrationChanged(let state) = event {
                    states.append(state)
                    if state == .registered { break }
                }
            }
            return states
        }

        try await client.configure(account: makeAccount())
        try await client.register()

        let states = await collector.value
        #expect(states.suffix(2) == [.registering, .registered])
    }

    @Test("senha vazia simula falha de autenticação")
    func authFailure() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        try await client.configure(account: makeAccount(password: ""))

        await #expect(throws: SIPClientError.authenticationFailed) {
            try await client.register()
        }
    }

    @Test("registrar sem configurar falha com notConfigured")
    func registerWithoutConfigure() async {
        let client = MockSIPClient(stepDelay: .zero)
        await #expect(throws: SIPClientError.notConfigured) {
            try await client.register()
        }
    }

    @Test("chamada de saída progride até active e encerra com hangup")
    func outgoingCallLifecycle() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        try await client.configure(account: makeAccount())
        try await client.register()

        let session = try await client.makeCall(to: "51999998888")
        #expect(session.state == .dialing)
        #expect(session.direction == .outgoing)

        // Aguarda a progressão automática dialing → ringing → active.
        var sawActive = false
        for await event in client.events {
            if case .callStateChanged(let call) = event, call.id == session.id, call.state == .active {
                sawActive = true
                break
            }
        }
        #expect(sawActive)

        try await client.hangup(callId: session.id)
    }

    @Test("chamada sem registro é recusada")
    func callRequiresRegistration() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        try await client.configure(account: makeAccount())

        await #expect(throws: SIPClientError.notRegistered) {
            try await client.makeCall(to: "1002")
        }
    }

    @Test("destino vazio é recusado")
    func emptyDestinationRejected() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        try await client.configure(account: makeAccount())
        try await client.register()

        await #expect(throws: SIPClientError.invalidDestination) {
            try await client.makeCall(to: "   ")
        }
    }

    @Test("unregister durante registro em andamento vence o registro")
    func unregisterDuringRegistrationWins() async throws {
        // Delay largo: entre observar .registering e chamar unregister()
        // passam microssegundos, então o unregister cai dentro do sleep.
        let client = MockSIPClient(stepDelay: .milliseconds(500))
        var iterator = client.events.makeAsyncIterator()

        try await client.configure(account: makeAccount())
        #expect(await iterator.next() == .registrationChanged(.idle))

        let registration = Task { try await client.register() }
        #expect(await iterator.next() == .registrationChanged(.registering))

        await client.unregister()
        #expect(await iterator.next() == .registrationChanged(.disconnected))

        // register() retoma do sleep e deve abandonar o fluxo sem emitir
        // .registered. O unregister sentinela abaixo destrava o iterator:
        // se o bug existisse, o próximo evento seria .registered.
        try? await registration.value
        await client.unregister()
        #expect(await iterator.next() == .registrationChanged(.disconnected))
    }

    @Test("configure durante registro em voo abandona a tentativa antiga")
    func configureDuringRegistrationInvalidatesOldAttempt() async throws {
        let client = MockSIPClient(stepDelay: .milliseconds(400))
        var iterator = client.events.makeAsyncIterator()

        // Tentativa 1: conta A válida, fica dormindo.
        try await client.configure(account: makeAccount())
        #expect(await iterator.next() == .registrationChanged(.idle))
        let firstAttempt = Task { try await client.register() }
        #expect(await iterator.next() == .registrationChanged(.registering))

        // Tentativa 2 no meio do sleep: conta B inválida (senha vazia).
        try await client.configure(account: makeAccount(password: ""))
        #expect(await iterator.next() == .registrationChanged(.idle))
        await #expect(throws: SIPClientError.authenticationFailed) {
            try await client.register()
        }
        try? await firstAttempt.value

        // A tentativa 1 (snapshot da conta A) foi abandonada: o resultado
        // final é a FALHA da conta B, nunca .registered da conta A.
        #expect(await iterator.next() == .registrationChanged(.registering))
        #expect(await iterator.next() == .registrationChanged(.failed(.authenticationFailed)))
    }

    @Test("unregister limpa a conta configurada na engine")
    func unregisterClearsConfiguredAccount() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        try await client.configure(account: makeAccount())
        try await client.register()
        await client.unregister()

        // Sem novo configure(), a engine não retém credenciais removidas.
        await #expect(throws: SIPClientError.notConfigured) {
            try await client.register()
        }
    }

    @Test("chamada encerrada não pode ser atendida nem encerrada de novo")
    func endedCallCannotBeReused() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        try await client.configure(account: makeAccount())
        try await client.register()

        let session = try await client.makeCall(to: "1002")
        try await client.hangup(callId: session.id)

        await #expect(throws: SIPClientError.callNotFound(id: session.id)) {
            try await client.answer(callId: session.id)
        }
        await #expect(throws: SIPClientError.callNotFound(id: session.id)) {
            try await client.hangup(callId: session.id)
        }
        await #expect(throws: SIPClientError.callNotFound(id: session.id)) {
            try await client.reject(callId: session.id)
        }
    }

    @Test("chamada de saída ativa não pode ser 'atendida' localmente")
    func outgoingCallCannotBeAnswered() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        try await client.configure(account: makeAccount())
        try await client.register()

        let session = try await client.makeCall(to: "1003")
        await #expect(throws: SIPClientError.callNotFound(id: session.id)) {
            try await client.answer(callId: session.id)
        }
    }

    @Test("entrada não atendida expira como perdida")
    func unansweredIncomingCallExpiresAsMissed() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        var iterator = client.events.makeAsyncIterator()
        try await client.configure(account: makeAccount())
        try await client.register()

        await client.simulateIncomingCall(
            from: "51988887777",
            displayName: nil,
            missedAfter: .milliseconds(50)
        )

        // Consome eventos de registro até chegar na chamada.
        var incoming: CallSession?
        while incoming == nil, let event = await iterator.next() {
            if case .incomingCall(let call) = event { incoming = call }
        }
        let call = try #require(incoming)

        // Sem atender: o próximo evento da chamada é o encerramento como perdida.
        #expect(isEnded(await iterator.next(), callId: call.id, reason: .missed))

        // Depois de expirada, atender falha.
        await #expect(throws: SIPClientError.callNotFound(id: call.id)) {
            try await client.answer(callId: call.id)
        }
    }

    @Test("atender antes da expiração cancela a chamada perdida")
    func answeringPreventsMissedExpiry() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        var iterator = client.events.makeAsyncIterator()
        try await client.configure(account: makeAccount())
        try await client.register()

        await client.simulateIncomingCall(
            from: "51988887777",
            displayName: nil,
            missedAfter: .milliseconds(80)
        )
        var incoming: CallSession?
        while incoming == nil, let event = await iterator.next() {
            if case .incomingCall(let call) = event { incoming = call }
        }
        let call = try #require(incoming)

        try await client.answer(callId: call.id)
        #expect(isState(await iterator.next(), callId: call.id, state: .active))

        // Espera o prazo de expiração passar: nada deve acontecer.
        try await Task.sleep(for: .milliseconds(150))
        try await client.hangup(callId: call.id)

        // Os próximos eventos são do hangup — nunca .ended(.missed).
        #expect(isState(await iterator.next(), callId: call.id, state: .ending))
        #expect(isEnded(await iterator.next(), callId: call.id, reason: .localHangup))
    }

    @Test("recusar entrada encerra como rejeitada")
    func rejectEndsAsRejected() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        var iterator = client.events.makeAsyncIterator()
        try await client.configure(account: makeAccount())
        try await client.register()

        await client.simulateIncomingCall(from: "51977776666")
        var incoming: CallSession?
        while incoming == nil, let event = await iterator.next() {
            if case .incomingCall(let call) = event { incoming = call }
        }
        let call = try #require(incoming)

        try await client.reject(callId: call.id)
        #expect(isEnded(await iterator.next(), callId: call.id, reason: .rejected))
    }

    // MARK: - Helpers de asserção

    private func isState(_ event: SIPEvent?, callId: String, state: CallState) -> Bool {
        guard case .callStateChanged(let call) = event else { return false }
        return call.id == callId && call.state == state
    }

    private func isEnded(_ event: SIPEvent?, callId: String, reason: CallEndReason) -> Bool {
        guard case .callStateChanged(let call) = event else { return false }
        return call.id == callId && call.state == .ended(reason: reason)
    }

    @Test("chamada de entrada simulada é publicada e pode ser atendida")
    func incomingCallSimulation() async throws {
        let client = MockSIPClient(stepDelay: .zero)
        try await client.configure(account: makeAccount())
        try await client.register()

        await client.simulateIncomingCall(from: "51988887777", displayName: "Teste")

        var incoming: CallSession?
        for await event in client.events {
            if case .incomingCall(let call) = event {
                incoming = call
                break
            }
        }

        let call = try #require(incoming)
        #expect(call.direction == .incoming)
        #expect(call.state == .incoming)

        try await client.answer(callId: call.id)
    }
}
