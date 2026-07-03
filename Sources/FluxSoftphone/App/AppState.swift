import Foundation
import SwiftUI
import FluxDomain
import FluxInfrastructure
import FluxWhiteLabel

/// Estado observável central do app. Consome eventos da engine SIP e expõe
/// estado pronto para a UI — nenhuma view fala com a engine diretamente.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var registrationState: RegistrationState = .idle
    @Published private(set) var activeCall: CallSession?
    /// Microfone mutado na chamada atual. Reseta ao encerrar.
    @Published private(set) var isMuted = false
    /// Histórico recente (mais novo primeiro), para a lista da UI.
    @Published private(set) var callHistory: [CallHistoryEntry] = []
    /// Conta SIP persistida no Keychain, carregada na abertura.
    @Published private(set) var savedAccount: SIPAccount?
    /// Estado de áudio para a seção de Ajustes.
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var preferredInputDeviceId: String?
    @Published private(set) var preferredOutputDeviceId: String?
    @Published private(set) var microphonePermission: MicrophonePermissionStatus = .undetermined
    /// Preferências de mídia (codec, eco/ruído, AGC) — Ajustes → Áudio.
    /// Alterações valem a partir da próxima chamada.
    @Published private(set) var mediaPreferences: MediaPreferences
    /// Mensagem amigável de erro/aviso para exibição direta na UI.
    @Published private(set) var userMessage: String? {
        didSet {
            // Diagnóstico guarda o último erro mesmo depois da UI limpá-lo.
            if let userMessage {
                lastError = userMessage
                lastErrorAt = Date()
            }
        }
    }
    /// Último erro exibido e quando — para a tela de diagnóstico.
    @Published private(set) var lastError: String?
    @Published private(set) var lastErrorAt: Date?
    /// Registro de eventos SIP/mídia (sanitizado) para o Diagnóstico —
    /// evidência do que a engine realmente fez (ou simulou).
    @Published private(set) var diagnosticEntries: [DiagnosticLog.Entry] = []
    /// Seção selecionada na janela principal (navegável também por ações,
    /// ex.: "Configurar conta" na visão geral).
    @Published var selectedSection: MainSection? = .overview
    /// Número digitado no discador. Vive aqui (não na view) para sobreviver
    /// à troca de seção e permitir pré-preenchimento pelo redial.
    @Published var dialerNumber = ""

    let brand: BrandConfig

    private let sipClient: any SIPClientProtocol
    private let diagnosticLog: DiagnosticLog
    private var diagnosticLogTask: Task<Void, Never>?
    private let credentialsStore: any SecureCredentialsStoreProtocol
    private let callHistoryRepository: any CallHistoryRepositoryProtocol
    private let audioDeviceService: any AudioDeviceServiceProtocol
    private let microphonePermissionService: any MicrophonePermissionServiceProtocol
    private let mediaPreferencesStore: any MediaPreferencesStoreProtocol
    private var eventTask: Task<Void, Never>?
    /// Operação de registro/desregistro em voo. Cada nova operação cancela
    /// a anterior — sem isso, um register disparado antes de removeAccount
    /// poderia completar depois e deixar o app "Registrado" sem conta.
    private var registrationTask: Task<Void, Never>?
    /// Última chamada já gravada no histórico — evita registro duplicado
    /// se a engine emitir mais de um estado terminal para a mesma sessão.
    private var lastRecordedCallId: String?

    init(
        brand: BrandConfig,
        sipClient: any SIPClientProtocol,
        diagnosticLog: DiagnosticLog,
        credentialsStore: any SecureCredentialsStoreProtocol,
        callHistoryRepository: any CallHistoryRepositoryProtocol,
        audioDeviceService: any AudioDeviceServiceProtocol,
        microphonePermissionService: any MicrophonePermissionServiceProtocol,
        mediaPreferencesStore: any MediaPreferencesStoreProtocol
    ) {
        self.brand = brand
        self.sipClient = sipClient
        self.diagnosticLog = diagnosticLog
        self.credentialsStore = credentialsStore
        self.callHistoryRepository = callHistoryRepository
        self.audioDeviceService = audioDeviceService
        self.microphonePermissionService = microphonePermissionService
        self.mediaPreferencesStore = mediaPreferencesStore
        self.mediaPreferences = mediaPreferencesStore.load()
    }

    deinit {
        // Os Tasks capturam sipClient forte; sem cancelamento, Task e engine
        // vazariam se o AppState for recriado (logout, troca de tenant).
        eventTask?.cancel()
        registrationTask?.cancel()
        diagnosticLogTask?.cancel()
    }

    /// Inicia o consumo de eventos e restaura a conta salva. Idempotente.
    func start() {
        guard eventTask == nil else { return }
        startDiagnosticLogFeed()
        diagnosticLog.append("Engine SIP: \(engineName)")
        startEventLoop()
        restoreSavedAccount()
        refreshAudioState()
    }

    private func startDiagnosticLogFeed() {
        // O stream reproduz o histórico e segue com as novas entradas.
        diagnosticLogTask = Task { [weak self, diagnosticLog] in
            for await entry in diagnosticLog.updates() {
                guard let self else { break }
                self.diagnosticEntries.append(entry)
                if self.diagnosticEntries.count > 300 {
                    self.diagnosticEntries.removeFirst(self.diagnosticEntries.count - 300)
                }
            }
        }
    }

    private func startEventLoop() {
        eventTask?.cancel()
        eventTask = Task { [weak self, sipClient] in
            for await event in sipClient.events {
                guard let self else { break }
                self.handle(event)
            }
        }
    }

    // MARK: - Áudio (Ciclo 9)

    /// Atualiza dispositivos, preferências e permissão de microfone.
    func refreshAudioState() {
        Task { [audioDeviceService, microphonePermissionService] in
            let inputs = await audioDeviceService.listInputDevices()
            let outputs = await audioDeviceService.listOutputDevices()
            let preferredInput = await audioDeviceService.preferredInputDeviceId()
            let preferredOutput = await audioDeviceService.preferredOutputDeviceId()
            let permission = await microphonePermissionService.currentStatus()

            self.inputDevices = inputs
            self.outputDevices = outputs
            self.preferredInputDeviceId = preferredInput
            self.preferredOutputDeviceId = preferredOutput
            self.microphonePermission = permission
        }
    }

    /// Define o microfone preferido (`nil` = padrão do sistema).
    func selectInputDevice(_ id: String?) {
        Task { [audioDeviceService] in
            do {
                try await audioDeviceService.setInputDevice(id)
            } catch {
                self.userMessage = "Não foi possível selecionar o microfone."
            }
            self.refreshAudioState()
        }
    }

    /// Define a saída de áudio preferida (`nil` = padrão do sistema).
    func selectOutputDevice(_ id: String?) {
        Task { [audioDeviceService] in
            do {
                try await audioDeviceService.setOutputDevice(id)
            } catch {
                self.userMessage = "Não foi possível selecionar a saída de áudio."
            }
            self.refreshAudioState()
        }
    }

    /// Solicita a permissão de microfone quando o build permite.
    func requestMicrophoneAccess() {
        Task { [microphonePermissionService] in
            self.microphonePermission = await microphonePermissionService.requestAccess()
        }
    }

    /// Atualiza e persiste as preferências de mídia. Chamada em andamento
    /// NÃO é tocada — a engine lê as preferências ao montar cada chamada.
    func updateMediaPreferences(_ change: (inout MediaPreferences) -> Void) {
        var updated = mediaPreferences
        change(&updated)
        guard updated != mediaPreferences else { return }
        mediaPreferences = updated
        mediaPreferencesStore.save(updated)
        diagnosticLog.append(
            "Mídia: codec preferido \(updated.preferredCodec.rawValue.uppercased()), "
                + "eco \(updated.echoCancellationEnabled ? "ligado" : "desligado"), "
                + "VAD \(updated.silenceSuppressionEnabled ? "ligado" : "desligado"), "
                + "AGC \(updated.autoGainControlEnabled ? "ligado" : "desligado") — vale para a próxima chamada"
        )
    }

    // MARK: - Conta (Ciclo 3)

    /// Persiste a conta no Keychain e registra em seguida.
    /// Retorna `false` se a persistência falhou — o chamador decide se
    /// mantém o formulário aberto para o usuário não perder o que digitou.
    @discardableResult
    func saveAccount(_ account: SIPAccount) -> Bool {
        do {
            try credentialsStore.save(account: account)
            savedAccount = account
            AppLog.persistence.info("Conta salva no Keychain: \(account, privacy: .public)")
            register(account)
            return true
        } catch {
            AppLog.persistence.error(
                "Falha ao salvar conta no Keychain: \(String(describing: error), privacy: .public)"
            )
            userMessage = "Não foi possível salvar a conta com segurança."
            return false
        }
    }

    /// Remove as credenciais do Keychain e desregistra.
    func removeAccount() {
        do {
            try credentialsStore.clear()
            savedAccount = nil
            userMessage = nil
            AppLog.persistence.info("Credenciais removidas do Keychain")
            startRegistrationOperation { sipClient in
                await sipClient.unregister()
            }
        } catch {
            AppLog.persistence.error(
                "Falha ao remover credenciais: \(String(describing: error), privacy: .public)"
            )
            userMessage = "Não foi possível remover as credenciais."
        }
    }

    /// Registra a conta salva (ex.: após desconexão manual).
    func registerSavedAccount() {
        guard let savedAccount else {
            userMessage = UserMessages.message(for: SIPClientError.notConfigured)
            return
        }
        register(savedAccount)
    }

    func unregister() {
        userMessage = nil
        startRegistrationOperation { sipClient in
            await sipClient.unregister()
        }
    }

    // MARK: - Chamadas (Ciclo 6: originação; tela de chamada completa no Ciclo 7)

    /// Normaliza, valida e origina uma chamada de saída.
    func startOutgoingCall(to rawDestination: String) {
        let destination = PhoneNumberNormalizer.normalize(rawDestination)
        guard PhoneNumberNormalizer.isDiallable(destination) else {
            userMessage = UserMessages.message(for: SIPClientError.invalidDestination)
            return
        }
        userMessage = nil
        AppLog.sip.info("Originando chamada para \(LogSanitizer.maskNumber(destination), privacy: .public)")
        Task { [sipClient] in
            do {
                try await sipClient.makeCall(to: destination)
            } catch let error as SIPClientError {
                self.userMessage = UserMessages.message(for: error)
            } catch {
                self.userMessage = UserMessages.genericError
            }
        }
    }

    /// Encerra a chamada em andamento, se houver.
    func hangupActiveCall() {
        guard let call = activeCall, call.state.isLive else { return }
        Task { [sipClient] in
            try? await sipClient.hangup(callId: call.id)
        }
    }

    /// Tom local de tecla (feedback sonoro do discador e do DTMF).
    private let keyTonePlayer = DTMFTonePlayer()

    /// Toca o tom local do dígito — usado pelo discador ao teclar.
    func playKeyTone(_ digit: Character) {
        keyTonePlayer.play(digit)
    }

    /// Dígitos DTMF enviados na chamada atual (para o discador exibir).
    @Published private(set) var dtmfDigitsSent = ""

    /// Envia DTMF na chamada ativa (RFC 2833) com feedback sonoro local.
    func sendDTMF(_ digit: Character) {
        guard let call = activeCall, call.state == .active else { return }
        keyTonePlayer.play(digit)
        dtmfDigitsSent.append(digit)
        Task { [sipClient] in
            do {
                try await sipClient.sendDTMF(callId: call.id, digit: digit)
            } catch let error as SIPClientError {
                self.userMessage = UserMessages.message(for: error)
            } catch {
                self.userMessage = UserMessages.genericError
            }
        }
    }

    /// Alterna o mute do microfone na chamada atual.
    func toggleMute() {
        guard activeCall?.state.isLive == true else { return }
        isMuted.toggle()
        let muted = isMuted
        Task { [sipClient] in
            await sipClient.setMuted(muted)
        }
    }

    /// Atende a chamada de entrada em exibição.
    func answerIncomingCall() {
        guard let call = activeCall, call.state == .incoming else { return }
        Task { [sipClient] in
            do {
                try await sipClient.answer(callId: call.id)
            } catch let error as SIPClientError {
                self.userMessage = UserMessages.message(for: error)
            } catch {
                self.userMessage = UserMessages.genericError
            }
        }
    }

    /// Recusa a chamada de entrada em exibição.
    func rejectIncomingCall() {
        guard let call = activeCall, call.state == .incoming else { return }
        Task { [sipClient] in
            try? await sipClient.reject(callId: call.id)
        }
    }

    /// Nome da engine ativa, para o diagnóstico. O app usa exclusivamente a
    /// engine real — a simulada vive apenas na suíte de testes.
    var engineName: String {
        "Nativa (SIP real)"
    }

    // MARK: - Histórico

    /// Recarrega a lista exibida na seção Histórico.
    func refreshCallHistory() {
        guard brand.features.callHistory else { return }
        Task { [callHistoryRepository] in
            let entries = (try? await callHistoryRepository.recentEntries(limit: 100)) ?? []
            self.callHistory = entries
        }
    }

    /// Liga novamente para um registro do histórico. Se não for possível
    /// ligar agora (sem registro ou chamada em andamento), leva ao discador
    /// pré-preenchido — lá o motivo fica visível (docs/06: nunca discar às
    /// cegas sem dar contexto ao usuário).
    func redial(_ entry: CallHistoryEntry) {
        if registrationState == .registered, activeCall?.state.isLive != true {
            startOutgoingCall(to: entry.number)
        } else {
            dialerNumber = entry.number
            selectedSection = .dialer
        }
    }

    /// Apaga todo o histórico local.
    func clearCallHistory() {
        Task { [callHistoryRepository] in
            do {
                try await callHistoryRepository.clear()
                self.refreshCallHistory()
            } catch {
                AppLog.persistence.error(
                    "Falha ao limpar histórico: \(String(describing: error), privacy: .public)"
                )
                self.userMessage = "Não foi possível limpar o histórico."
            }
        }
    }

    private func recordInHistory(_ session: CallSession) {
        guard brand.features.callHistory,
              session.id != lastRecordedCallId,
              let entry = CallHistoryEntry(session: session, accountURI: savedAccount?.uri ?? "")
        else { return }
        lastRecordedCallId = session.id
        Task { [callHistoryRepository] in
            do {
                try await callHistoryRepository.append(entry)
                self.refreshCallHistory()
            } catch {
                AppLog.persistence.error(
                    "Falha ao gravar histórico: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func restoreSavedAccount() {
        do {
            guard let account = try credentialsStore.loadAccount() else { return }
            savedAccount = account
            AppLog.persistence.info("Conta restaurada do Keychain: \(account, privacy: .public)")
            register(account)
        } catch {
            AppLog.persistence.error(
                "Falha ao carregar conta salva: \(String(describing: error), privacy: .public)"
            )
            userMessage = "Não foi possível carregar a conta salva."
        }
    }

    private func register(_ account: SIPAccount) {
        userMessage = nil
        startRegistrationOperation { [weak self] sipClient in
            do {
                try await sipClient.configure(account: account)
                try Task.checkCancellation()
                try await sipClient.register()
            } catch is CancellationError {
                // Operação substituída por outra mais recente — silencioso.
            } catch let error as SIPClientError {
                self?.userMessage = UserMessages.message(for: error)
            } catch {
                self?.userMessage = UserMessages.genericError
            }
        }
    }

    /// Substitui a operação de registro em voo: cancela a anterior antes de
    /// iniciar a nova, garantindo que o comando mais recente do usuário vence.
    private func startRegistrationOperation(
        _ operation: @escaping @MainActor (any SIPClientProtocol) async -> Void
    ) {
        registrationTask?.cancel()
        registrationTask = Task { [sipClient] in
            await operation(sipClient)
        }
    }

    // MARK: - Eventos

    private func handle(_ event: SIPEvent) {
        switch event {
        case .registrationChanged(let state):
            registrationState = state
            AppLog.sip.info("Registro: \(String(describing: state), privacy: .public)")
        case .incomingCall(let session), .callStateChanged(let session):
            if session.state.isLive {
                activeCall = session
            } else {
                activeCall = nil
                isMuted = false
                dtmfDigitsSent = ""
                recordInHistory(session)
            }
        case .audioRouteChanged:
            refreshAudioState()
        case .error(let error):
            userMessage = UserMessages.message(for: error)
        }
    }
}
