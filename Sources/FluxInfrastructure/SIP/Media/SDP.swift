import Foundation

/// SDP mínimo para áudio G.711 (RFC 4566/3264) — puro e testável.
enum SDP {
    /// Lado remoto extraído de um SDP recebido.
    struct RemoteMedia: Equatable {
        let connectionAddress: String
        let audioPort: Int
        let payloadTypes: [Int]
        /// Payload type do telephone-event (DTMF RFC 2833/4733), se ofertado.
        let telephoneEventPayloadType: Int?

        /// Primeiro codec G.711 em comum, na preferência do remoto.
        var negotiatedCodec: G711Codec? {
            for payloadType in payloadTypes {
                if let codec = G711Codec(rawValue: payloadType) { return codec }
            }
            return nil
        }

        /// Codec comum honrando a NOSSA preferência quando o remoto também a
        /// oferece; senão, cai na ordem do remoto (RFC 3264 permite ambos —
        /// escolher o nosso evita transcodificação do lado que controlamos).
        func negotiatedCodec(preferring preferred: G711Codec) -> G711Codec? {
            if payloadTypes.contains(preferred.rawValue) { return preferred }
            return negotiatedCodec
        }
    }

    /// Oferta/resposta de áudio com PCMU+PCMA (oferta) ou codec único
    /// (resposta), opcionalmente com telephone-event (DTMF fora de banda).
    static func audioDescription(
        sessionId: String,
        host: String,
        rtpPort: Int,
        codecs: [G711Codec],
        telephoneEventPayloadType: Int? = nil
    ) -> String {
        var payloads = codecs.map { String($0.rawValue) }
        if let telephoneEventPayloadType {
            payloads.append(String(telephoneEventPayloadType))
        }
        var lines = [
            "v=0",
            "o=- \(sessionId) 1 IN IP4 \(host)",
            "s=-",
            "c=IN IP4 \(host)",
            "t=0 0",
            "m=audio \(rtpPort) RTP/AVP \(payloads.joined(separator: " "))"
        ]
        for codec in codecs {
            lines.append("a=rtpmap:\(codec.rawValue) \(codec.sdpName)/8000")
        }
        if let telephoneEventPayloadType {
            lines.append("a=rtpmap:\(telephoneEventPayloadType) telephone-event/8000")
            lines.append("a=fmtp:\(telephoneEventPayloadType) 0-16")
        }
        lines.append("a=ptime:20")
        lines.append("a=sendrecv")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Extrai endereço, porta de áudio e payloads de um SDP remoto.
    /// `c=` em nível de mídia sobrepõe o de sessão.
    static func parseRemoteMedia(_ text: String) -> RemoteMedia? {
        var sessionAddress: String?
        var mediaAddress: String?
        var audioPort: Int?
        var payloadTypes: [Int] = []
        var telephoneEventPT: Int?
        var inAudioSection = false

        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines {
            if line.hasPrefix("m=") {
                if line.hasPrefix("m=audio ") {
                    inAudioSection = true
                    let parts = line.dropFirst("m=audio ".count).split(separator: " ")
                    guard parts.count >= 2, let port = Int(parts[0]) else { return nil }
                    audioPort = port
                    payloadTypes = parts.dropFirst(2).compactMap { Int($0) }
                } else {
                    inAudioSection = false
                }
            } else if line.hasPrefix("c=IN IP4 ") {
                let address = String(line.dropFirst("c=IN IP4 ".count))
                    .split(separator: "/").first.map(String.init) ?? ""
                if inAudioSection {
                    mediaAddress = address
                } else if sessionAddress == nil {
                    sessionAddress = address
                }
            } else if inAudioSection, line.hasPrefix("a=rtpmap:") {
                // `a=rtpmap:101 telephone-event/8000` → PT do DTMF remoto.
                let value = line.dropFirst("a=rtpmap:".count)
                let parts = value.split(separator: " ", maxSplits: 1)
                if parts.count == 2,
                   parts[1].lowercased().hasPrefix("telephone-event"),
                   let payloadType = Int(parts[0]) {
                    telephoneEventPT = payloadType
                }
            }
        }

        guard let audioPort, audioPort > 0,
              let address = mediaAddress ?? sessionAddress, !address.isEmpty
        else { return nil }
        return RemoteMedia(
            connectionAddress: address,
            audioPort: audioPort,
            payloadTypes: payloadTypes,
            telephoneEventPayloadType: telephoneEventPT
        )
    }
}
