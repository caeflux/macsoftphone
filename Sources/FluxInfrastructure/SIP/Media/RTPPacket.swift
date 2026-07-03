import Foundation

/// Montagem e leitura de pacotes RTP (RFC 3550) — puro e testável.
/// Áudio G.711: 20 ms por pacote = 160 amostras = 160 bytes de payload.
enum RTPPacket {
    static let samplesPerPacket = 160

    struct Parsed: Equatable {
        let payloadType: UInt8
        let sequenceNumber: UInt16
        let timestamp: UInt32
        let ssrc: UInt32
        let payload: Data
    }

    static func build(
        payloadType: UInt8,
        sequenceNumber: UInt16,
        timestamp: UInt32,
        ssrc: UInt32,
        payload: [UInt8],
        marker: Bool = false
    ) -> Data {
        var data = Data(capacity: 12 + payload.count)
        data.append(0x80) // V=2, sem padding/extension/CSRC
        data.append((marker ? 0x80 : 0x00) | (payloadType & 0x7F))
        data.append(UInt8(sequenceNumber >> 8))
        data.append(UInt8(sequenceNumber & 0xFF))
        appendUInt32(&data, timestamp)
        appendUInt32(&data, ssrc)
        data.append(contentsOf: payload)
        return data
    }

    static func parse(_ data: Data) -> Parsed? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] >> 6 == 2 else { return nil } // versão RTP 2

        let csrcCount = Int(bytes[0] & 0x0F)
        let hasExtension = (bytes[0] & 0x10) != 0
        var headerLength = 12 + csrcCount * 4

        if hasExtension {
            guard bytes.count >= headerLength + 4 else { return nil }
            let extensionWords = Int(bytes[headerLength + 2]) << 8 | Int(bytes[headerLength + 3])
            headerLength += 4 + extensionWords * 4
        }
        guard bytes.count >= headerLength else { return nil }

        return Parsed(
            payloadType: bytes[1] & 0x7F,
            sequenceNumber: UInt16(bytes[2]) << 8 | UInt16(bytes[3]),
            timestamp: readUInt32(bytes, at: 4),
            ssrc: readUInt32(bytes, at: 8),
            payload: data.dropFirst(headerLength)
        )
    }

    /// Eventos DTMF fora de banda (RFC 4733/2833).
    enum DTMF {
        /// Código do evento: 0-9 = dígitos, 10 = `*`, 11 = `#`.
        static func code(for digit: Character) -> UInt8? {
            switch digit {
            case "0"..."9": return UInt8(String(digit))
            case "*": return 10
            case "#": return 11
            case "A", "a": return 12
            case "B", "b": return 13
            case "C", "c": return 14
            case "D", "d": return 15
            default: return nil
            }
        }

        /// Payload de 4 bytes: evento, E-bit+volume, duração (BE, em amostras).
        static func payload(
            event: UInt8,
            endOfEvent: Bool,
            duration: UInt16,
            volume: UInt8 = 10
        ) -> [UInt8] {
            [
                event,
                (endOfEvent ? 0x80 : 0x00) | (volume & 0x3F),
                UInt8(duration >> 8),
                UInt8(duration & 0xFF)
            ]
        }
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }
}
