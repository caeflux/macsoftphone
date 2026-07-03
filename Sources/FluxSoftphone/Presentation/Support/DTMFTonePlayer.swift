import Foundation
import AVFoundation

/// Feedback audível local dos dígitos (tom DTMF dual-tone de ~120 ms) —
/// tocado ao teclar no discador e ao enviar DTMF em chamada. Local apenas:
/// o DTMF que o servidor recebe vai fora de banda (RFC 2833), não por aqui.
///
/// Engine própria e leve, criada no primeiro uso; falha de áudio é silenciosa
/// (feedback sonoro nunca pode quebrar o fluxo de discagem).
final class DTMFTonePlayer: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?

    // Estado do tom corrente (protegido por lock; lido no callback de áudio).
    private var lowFrequency = 0.0
    private var highFrequency = 0.0
    private var remainingSamples = 0
    private var lowPhase = 0.0
    private var highPhase = 0.0

    private let sampleRate = 44_100.0
    private let toneDuration = 0.12
    private let amplitude: Float = 0.12

    /// Frequências DTMF padrão (linhas × colunas).
    private static func frequencies(for digit: Character) -> (low: Double, high: Double)? {
        let rows: [Double] = [697, 770, 852, 941]
        let columns: [Double] = [1209, 1336, 1477]
        let layout: [[Character]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["*", "0", "#"]
        ]
        for (rowIndex, row) in layout.enumerated() {
            if let columnIndex = row.firstIndex(of: digit) {
                return (rows[rowIndex], columns[columnIndex])
            }
        }
        return nil
    }

    func play(_ digit: Character) {
        guard let frequencies = Self.frequencies(for: digit) else { return }
        ensureEngine()
        lock.lock()
        lowFrequency = frequencies.low
        highFrequency = frequencies.high
        remainingSamples = Int(toneDuration * sampleRate)
        lock.unlock()
    }

    private func ensureEngine() {
        lock.lock()
        let hasEngine = engine != nil
        lock.unlock()
        guard !hasEngine else { return }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let newEngine = AVAudioEngine()
        let source = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, bufferList in
            self?.render(frameCount: frameCount, into: bufferList) ?? noErr
        }
        newEngine.attach(source)
        newEngine.connect(source, to: newEngine.mainMixerNode, format: format)
        newEngine.prepare()
        do {
            try newEngine.start()
        } catch {
            return // sem saída de áudio: segue mudo, sem quebrar a discagem
        }
        lock.lock()
        engine = newEngine
        sourceNode = source
        lock.unlock()
    }

    private func render(frameCount: AVAudioFrameCount, into bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let target = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }

        lock.lock()
        defer { lock.unlock() }

        let lowStep = 2.0 * .pi * lowFrequency / sampleRate
        let highStep = 2.0 * .pi * highFrequency / sampleRate
        let fadeSamples = 400.0

        for frame in 0..<Int(frameCount) {
            if remainingSamples > 0 {
                // Fade-out curto no fim evita "clique" audível.
                let envelope = Float(min(1.0, Double(remainingSamples) / fadeSamples))
                target[frame] = amplitude * envelope
                    * Float(sin(lowPhase) + sin(highPhase)) * 0.5
                lowPhase += lowStep
                highPhase += highStep
                remainingSamples -= 1
            } else {
                target[frame] = 0
            }
        }
        return noErr
    }
}
