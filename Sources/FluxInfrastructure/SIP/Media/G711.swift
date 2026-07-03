import Foundation
import FluxDomain

/// Codec negociado para a mídia da chamada. Payload types estáticos do RTP.
public enum G711Codec: Int, Sendable, Equatable {
    case pcmu = 0 // µ-law
    case pcma = 8 // A-law

    var sdpName: String {
        switch self {
        case .pcmu: return "PCMU"
        case .pcma: return "PCMA"
        }
    }
}

public extension G711Codec {
    /// Ponte da preferência de domínio para o codec RTP concreto.
    init(preference: AudioCodecPreference) {
        switch preference {
        case .pcma: self = .pcma
        case .pcmu: self = .pcmu
        }
    }

    /// Ordem da oferta SDP: o preferido primeiro, o outro em seguida —
    /// ambos sempre ofertados (interoperabilidade acima de preferência).
    static func offerOrder(preferring preference: AudioCodecPreference) -> [G711Codec] {
        let preferred = G711Codec(preference: preference)
        return preferred == .pcma ? [.pcma, .pcmu] : [.pcmu, .pcma]
    }
}

/// G.711 µ-law/A-law — implementação clássica, pura e testável.
/// 8 kHz mono, 1 byte por amostra; universal em PABX (docs/03).
enum G711 {
    // MARK: - µ-law

    static func encodeMuLaw(_ samples: [Int16]) -> [UInt8] {
        samples.map(linearToMuLaw)
    }

    static func decodeMuLaw<S: Sequence>(_ bytes: S) -> [Int16] where S.Element == UInt8 {
        bytes.map(muLawToLinear)
    }

    static func linearToMuLaw(_ sample: Int16) -> UInt8 {
        let bias: Int32 = 0x84
        let clip: Int32 = 32635
        var value = Int32(sample)
        let sign: Int32 = (value >> 8) & 0x80
        if sign != 0 { value = -value }
        if value > clip { value = clip }
        value += bias

        var exponent: Int32 = 7
        var mask: Int32 = 0x4000
        while exponent > 0, (value & mask) == 0 {
            exponent -= 1
            mask >>= 1
        }
        let mantissa = (value >> (exponent + 3)) & 0x0F
        let encoded = ~(sign | (exponent << 4) | mantissa)
        return UInt8(truncatingIfNeeded: encoded)
    }

    static func muLawToLinear(_ byte: UInt8) -> Int16 {
        let value = ~Int32(byte) & 0xFF
        let sign = value & 0x80
        let exponent = (value >> 4) & 0x07
        let mantissa = value & 0x0F
        var sample = (((mantissa << 3) + 0x84) << exponent) - 0x84
        if sign != 0 { sample = -sample }
        return Int16(truncatingIfNeeded: sample)
    }

    // MARK: - A-law

    static func encodeALaw(_ samples: [Int16]) -> [UInt8] {
        samples.map(linearToALaw)
    }

    static func decodeALaw<S: Sequence>(_ bytes: S) -> [Int16] where S.Element == UInt8 {
        bytes.map(aLawToLinear)
    }

    static func linearToALaw(_ sample: Int16) -> UInt8 {
        var value = Int32(sample)
        let sign: Int32 = value >= 0 ? 0x80 : 0x00
        if value < 0 { value = -value }
        if value > 32635 { value = 32635 }

        let result: Int32
        if value >= 256 {
            var exponent: Int32 = 1
            var temp = value >> 8
            while temp > 1 {
                temp >>= 1
                exponent += 1
            }
            let mantissa = (value >> (exponent + 3)) & 0x0F
            result = (exponent << 4) | mantissa
        } else {
            result = value >> 4
        }
        return UInt8(truncatingIfNeeded: (sign | result) ^ 0x55)
    }

    static func aLawToLinear(_ byte: UInt8) -> Int16 {
        let value = Int32(byte) ^ 0x55
        let sign = value & 0x80
        let exponent = (value >> 4) & 0x07
        let mantissa = value & 0x0F

        var sample: Int32
        if exponent == 0 {
            sample = (mantissa << 4) + 8
        } else {
            sample = ((mantissa << 4) + 0x108) << (exponent - 1)
        }
        // Em A-law, bit de sinal 1 = amostra positiva.
        if sign == 0 { sample = -sample }
        return Int16(truncatingIfNeeded: sample)
    }

    static func encode(_ samples: [Int16], codec: G711Codec) -> [UInt8] {
        switch codec {
        case .pcmu: return encodeMuLaw(samples)
        case .pcma: return encodeALaw(samples)
        }
    }

    static func decode(_ bytes: Data, codec: G711Codec) -> [Int16] {
        switch codec {
        case .pcmu: return decodeMuLaw(bytes)
        case .pcma: return decodeALaw(bytes)
        }
    }
}
