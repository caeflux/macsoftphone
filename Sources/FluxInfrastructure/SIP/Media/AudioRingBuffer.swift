import Foundation

/// Ring buffer de amostras de áudio com capacidade fixa. Push/pop O(1) e
/// SEM alocação no caminho quente — essencial porque `render()` roda na
/// thread de áudio de tempo real do AVAudioEngine, onde alocar ou fazer
/// `Array.removeFirst` (O(n)) causa glitches e inversão de prioridade.
///
/// Não é thread-safe por si: o chamador (RTPMediaSession) serializa o acesso
/// com um lock, mas as operações são curtas e de custo constante.
struct AudioRingBuffer {
    private var storage: [Int16]
    private let capacity: Int
    private var head = 0   // próxima posição de leitura
    private var count = 0  // amostras disponíveis

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = [Int16](repeating: 0, count: self.capacity)
    }

    var available: Int { count }

    /// Escreve amostras; ao encher, descarta as mais antigas (o áudio ao vivo
    /// prefere perder o passado a acumular latência).
    mutating func write(_ samples: UnsafeBufferPointer<Int16>) {
        for sample in samples {
            let tail = (head + count) % capacity
            storage[tail] = sample
            if count == capacity {
                head = (head + 1) % capacity // sobrescreve o mais antigo
            } else {
                count += 1
            }
        }
    }

    mutating func write(_ samples: [Int16]) {
        samples.withUnsafeBufferPointer { write($0) }
    }

    /// Lê até `frameCount` amostras para o ponteiro (Float normalizado),
    /// preenchendo o resto com silêncio. Retorna quantas amostras reais leu.
    /// O(frameCount), sem alocação.
    @discardableResult
    mutating func readNormalized(into target: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
        let toRead = Swift.min(frameCount, count)
        for index in 0..<toRead {
            target[index] = Float(storage[(head + index) % capacity]) / 32768.0
        }
        for index in toRead..<frameCount {
            target[index] = 0
        }
        head = (head + toRead) % capacity
        count -= toRead
        return toRead
    }

    /// Lê exatamente `frameCount` amostras Int16 para o destino, preenchendo
    /// com silêncio no que faltar. O(frameCount), sem alocação.
    mutating func read(into target: inout [Int16], frameCount: Int) {
        let toRead = Swift.min(frameCount, count)
        for index in 0..<toRead {
            target[index] = storage[(head + index) % capacity]
        }
        for index in toRead..<frameCount {
            target[index] = 0
        }
        head = (head + toRead) % capacity
        count -= toRead
    }

    mutating func removeAll() {
        head = 0
        count = 0
    }
}
