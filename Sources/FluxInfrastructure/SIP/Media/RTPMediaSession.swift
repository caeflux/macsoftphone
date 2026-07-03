import Foundation
import AVFoundation
import Darwin

/// Sessão de mídia real: socket UDP (BSD) para RTP simétrico + AVAudioEngine
/// para microfone e alto-falante, com G.711 a 8 kHz.
///
/// Pipeline de envio: tap no inputNode → AVAudioConverter (para 8 kHz Int16
/// mono) → ring buffer → timer de 20 ms → G.711 → RTP → socket.
/// Pipeline de recepção: socket → RTP parse → G.711 decode → buffer de
/// reprodução → AVAudioSourceNode (silêncio em underrun).
///
/// Estado interno protegido por lock — callbacks de áudio e rede chegam em
/// threads próprias. Cancelamento de eco/supressão de ruído via Voice
/// Processing I/O quando habilitados em `AudioProcessingOptions`.
public final class RTPMediaSession: MediaSessionProtocol, @unchecked Sendable {
    public let localRTPPort: Int

    /// Definido na criação (por chamada) — nunca muda com a mídia rodando.
    private let processing: AudioProcessingOptions

    private let socketFD: Int32
    private let lock = NSLock()

    // Protegido por `lock`:
    private var sendBuffer: AudioRingBuffer
    private var playoutBuffer: AudioRingBuffer
    private var muted = false
    private var codec: G711Codec = .pcmu
    private var sequenceNumber: UInt16
    private var timestamp: UInt32
    private let ssrc: UInt32
    private var running = false
    /// Scratch reutilizado no envio — evita alocar 160 amostras a cada 20 ms.
    private var sendScratch = [Int16](repeating: 0, count: RTPPacket.samplesPerPacket)
    /// DTMF fora de banda: PT negociado + fila de pacotes de evento a enviar
    /// no lugar do áudio (o tom substitui a voz durante o evento).
    private var telephoneEventPT: Int?
    private var pendingDTMF: [(payload: [UInt8], marker: Bool)] = []
    private var dtmfStartTimestamp: UInt32 = 0

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var sendTimer: DispatchSourceTimer?
    private var receiveSource: DispatchSourceRead?

    private let mediaQueue = DispatchQueue(label: "rtp-media", qos: .userInteractive)

    /// Limites dos buffers (em amostras de 8 kHz): 600 ms de fala.
    private static let bufferCap = 4800

    /// Acesso ao estado protegido — síncrono, seguro de chamar de contexto
    /// async (NSLock.lock() direto é proibido em função `async`).
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public init(processing: AudioProcessingOptions = .disabled) throws {
        self.processing = processing
        // Cópia local: os closures abaixo não podem capturar `self.socketFD`
        // antes de todos os membros estarem inicializados.
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw MediaSessionError.socketUnavailable }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_ANY
        address.sin_port = 0
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw MediaSessionError.socketUnavailable
        }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &length)
            }
        }
        guard nameResult == 0 else {
            close(fd)
            throw MediaSessionError.socketUnavailable
        }
        socketFD = fd
        localRTPPort = Int(UInt16(bigEndian: boundAddress.sin_port))
        sequenceNumber = UInt16.random(in: 0...UInt16.max)
        timestamp = UInt32.random(in: 0...UInt32.max)
        ssrc = UInt32.random(in: 0...UInt32.max)
        sendBuffer = AudioRingBuffer(capacity: Self.bufferCap)
        playoutBuffer = AudioRingBuffer(capacity: Self.bufferCap)
    }

    deinit {
        if running { teardown() }
        close(socketFD)
    }

    // MARK: - MediaSessionProtocol

    public func start(remoteHost: String, remotePort: Int, codec: G711Codec) async throws {
        var remote = sockaddr_in()
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = UInt16(remotePort).bigEndian
        guard inet_pton(AF_INET, remoteHost, &remote.sin_addr) == 1 else {
            throw MediaSessionError.invalidRemoteAddress(remoteHost)
        }
        // `connect` fixa o destino: send() simples e filtro de origem no receive.
        let connectResult = withUnsafePointer(to: &remote) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else { throw MediaSessionError.socketUnavailable }

        locked {
            self.codec = codec
            running = true
        }

        try startAudioEngine()
        startReceiving()
        startSending()
        AppLog.audio.info("Mídia RTP iniciada (porta local \(self.localRTPPort, privacy: .public))")
    }

    public func retarget(remoteHost: String, remotePort: Int, codec: G711Codec) async throws {
        var remote = sockaddr_in()
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = UInt16(remotePort).bigEndian
        guard inet_pton(AF_INET, remoteHost, &remote.sin_addr) == 1 else {
            throw MediaSessionError.invalidRemoteAddress(remoteHost)
        }
        // UDP permite re-connect: troca o destino sem recriar o socket
        // (mantém a porta local anunciada no SDP).
        let connectResult = withUnsafePointer(to: &remote) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else { throw MediaSessionError.socketUnavailable }
        locked { self.codec = codec }
    }

    public func setTelephoneEventPayloadType(_ payloadType: Int?) async {
        locked { telephoneEventPT = payloadType }
    }

    public func sendDTMF(digit: Character) async throws {
        guard let code = RTPPacket.DTMF.code(for: digit) else {
            throw MediaSessionError.invalidDTMFDigit(digit)
        }
        let negotiated: Bool = locked { telephoneEventPT != nil }
        guard negotiated else { throw MediaSessionError.dtmfNotNegotiated }

        locked {
            // Se é o primeiro evento da fila, o timestamp do tom é o atual.
            if pendingDTMF.isEmpty {
                dtmfStartTimestamp = timestamp
            }
            // ~120 ms de tom (6 pacotes com duração crescente) + fim
            // retransmitido 3x (RFC 4733 §2.5.1.4 — E-bit pode se perder).
            let samplesPerPacket = UInt16(RTPPacket.samplesPerPacket)
            for index in 1...6 {
                pendingDTMF.append((
                    RTPPacket.DTMF.payload(
                        event: code,
                        endOfEvent: false,
                        duration: samplesPerPacket * UInt16(index)
                    ),
                    index == 1
                ))
            }
            for _ in 0..<3 {
                pendingDTMF.append((
                    RTPPacket.DTMF.payload(
                        event: code,
                        endOfEvent: true,
                        duration: samplesPerPacket * 7
                    ),
                    false
                ))
            }
        }
    }

    public func setMuted(_ isMuted: Bool) async {
        locked { muted = isMuted }
    }

    public func stop() async {
        teardown()
        AppLog.audio.info("Mídia RTP encerrada")
    }

    private func teardown() {
        // Idempotente: só o primeiro teardown (stop() ou deinit) faz o trabalho.
        // `running` é lido/escrito sob lock; os callbacks de áudio/rede o
        // consultam antes de tocar nos buffers, então após isto eles no-opam.
        let shouldTeardown: Bool = locked {
            guard running else { return false }
            running = false
            return true
        }
        guard shouldTeardown else { return }

        sendTimer?.cancel()
        sendTimer = nil
        receiveSource?.cancel()
        receiveSource = nil

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        sourceNode = nil
    }

    // MARK: - Áudio

    private func startAudioEngine() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode

        // Voice Processing I/O (cancelamento de eco + supressão de ruído):
        // precisa ser habilitado ANTES de ler formatos/instalar taps — o
        // sistema troca a unidade de I/O e os formatos mudam. Entrada e saída
        // habilitadas em par (o AEC referencia o áudio reproduzido). Falha
        // aqui NÃO derruba a chamada: segue sem processamento, com log — o
        // áudio validado em campo é o plano B, nunca o silêncio.
        if processing.voiceProcessing {
            do {
                try input.setVoiceProcessingEnabled(true)
                try engine.outputNode.setVoiceProcessingEnabled(true)
                input.isVoiceProcessingAGCEnabled = processing.autoGainControl
                AppLog.audio.info(
                    "Voice processing ativo (AEC+NS; AGC \(self.processing.autoGainControl ? "on" : "off", privacy: .public))"
                )
            } catch {
                AppLog.audio.error(
                    "Voice processing indisponível; seguindo sem AEC/NS: \(String(describing: error), privacy: .public)"
                )
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0,
              let codecFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: 8000,
                  channels: 1,
                  interleaved: true
              ),
              let converter = AVAudioConverter(from: inputFormat, to: codecFormat),
              let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)
        else {
            throw MediaSessionError.audioEngineFailure("formato de áudio indisponível")
        }

        // Captura: microfone → 8 kHz Int16 → ring buffer de envio.
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.captureAndConvert(buffer: buffer, converter: converter, format: codecFormat)
        }

        // Reprodução: buffer de recepção → alto-falante (mixer faz o SRC).
        let source = AVAudioSourceNode(format: playbackFormat) { [weak self] _, _, frameCount, audioBufferList in
            self?.render(frameCount: frameCount, into: audioBufferList) ?? noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: playbackFormat)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw MediaSessionError.audioEngineFailure(String(describing: error))
        }
        self.engine = engine
        self.sourceNode = source
    }

    private func captureAndConvert(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        format: AVAudioFormat
    ) {
        let ratio = 8000.0 / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil,
              output.frameLength > 0,
              let channel = output.int16ChannelData?[0]
        else { return }

        // Escreve direto do ponteiro no ring buffer — sem alocar array.
        let frames = Int(output.frameLength)
        lock.lock()
        sendBuffer.write(UnsafeBufferPointer(start: channel, count: frames))
        lock.unlock()
    }

    private func render(frameCount: AVAudioFrameCount, into bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let target = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }

        // Thread de tempo real: lock curto, cópia O(frameCount), sem alocação.
        lock.lock()
        playoutBuffer.readNormalized(into: target, frameCount: Int(frameCount))
        lock.unlock()
        return noErr
    }

    // MARK: - RTP

    private func startSending() {
        let timer = DispatchSource.makeTimerSource(queue: mediaQueue)
        timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.sendNextPacket()
        }
        timer.resume()
        sendTimer = timer
    }

    private func sendNextPacket() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }

        // Evento DTMF pendente tem prioridade: substitui o pacote de áudio
        // deste tick (o tom toma o lugar da voz), com o timestamp do início
        // do tom e o PT do telephone-event.
        if let eventPT = telephoneEventPT, !pendingDTMF.isEmpty {
            let event = pendingDTMF.removeFirst()
            sequenceNumber &+= 1
            timestamp &+= UInt32(RTPPacket.samplesPerPacket)
            // Consome o áudio capturado para não acumular atraso.
            sendBuffer.read(into: &sendScratch, frameCount: RTPPacket.samplesPerPacket)
            let currentSeq = sequenceNumber
            let toneTs = dtmfStartTimestamp
            lock.unlock()

            let packet = RTPPacket.build(
                payloadType: UInt8(eventPT),
                sequenceNumber: currentSeq,
                timestamp: toneTs,
                ssrc: ssrc,
                payload: event.payload,
                marker: event.marker
            )
            packet.withUnsafeBytes { raw in
                _ = send(socketFD, raw.baseAddress, raw.count, 0)
            }
            return
        }

        // Lê 160 amostras para o scratch (silêncio no que faltar). Sem captura
        // suficiente ou mutado: envia silêncio (mantém NAT/fluxo vivos).
        if muted {
            for index in sendScratch.indices { sendScratch[index] = 0 }
            sendBuffer.removeAll()
        } else {
            sendBuffer.read(into: &sendScratch, frameCount: RTPPacket.samplesPerPacket)
        }
        sequenceNumber &+= 1
        timestamp &+= UInt32(RTPPacket.samplesPerPacket)
        let currentSeq = sequenceNumber
        let currentTs = timestamp
        let currentCodec = codec
        let payload = G711.encode(sendScratch, codec: currentCodec)
        lock.unlock()

        let packet = RTPPacket.build(
            payloadType: UInt8(currentCodec.rawValue),
            sequenceNumber: currentSeq,
            timestamp: currentTs,
            ssrc: ssrc,
            payload: payload
        )
        packet.withUnsafeBytes { raw in
            _ = send(socketFD, raw.baseAddress, raw.count, 0)
        }
    }

    private func startReceiving() {
        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: mediaQueue)
        source.setEventHandler { [weak self] in
            self?.receivePacket()
        }
        source.resume()
        receiveSource = source
    }

    private func receivePacket() {
        var buffer = [UInt8](repeating: 0, count: 2048)
        let received = recv(socketFD, &buffer, buffer.count, 0)
        guard received > 12 else { return }

        let data = Data(buffer[0..<received])
        guard let packet = RTPPacket.parse(data) else { return }

        lock.lock()
        defer { lock.unlock() }
        guard running, Int(packet.payloadType) == codec.rawValue else { return }
        let samples = G711.decode(packet.payload, codec: codec)
        playoutBuffer.write(samples)
    }
}
