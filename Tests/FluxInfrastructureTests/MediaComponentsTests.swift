import Testing
import Foundation
import FluxDomain
@testable import FluxInfrastructure

@Suite("G.711")
struct G711Tests {
    @Test("µ-law: silêncio e roundtrip preservam o sinal aproximadamente")
    func muLawRoundtrip() {
        let samples: [Int16] = [0, 100, -100, 1000, -1000, 8000, -8000, 32000, -32000]
        let encoded = G711.encodeMuLaw(samples)
        let decoded = G711.decodeMuLaw(encoded)

        #expect(encoded.count == samples.count)
        for (original, result) in zip(samples, decoded) {
            // G.711 é com perdas; erro relativo pequeno + sinal preservado.
            let tolerance = Int16(max(256, abs(Int(original)) / 8))
            #expect(abs(Int(original) - Int(result)) <= Int(tolerance))
        }
    }

    @Test("A-law: roundtrip preserva sinal e magnitude aproximada")
    func aLawRoundtrip() {
        let samples: [Int16] = [0, 500, -500, 4000, -4000, 20000, -20000]
        let decoded = G711.decodeALaw(G711.encodeALaw(samples))
        for (original, result) in zip(samples, decoded) {
            #expect((original >= 0) == (result >= 0) || abs(original) < 16)
            let tolerance = Int16(max(256, abs(Int(original)) / 8))
            #expect(abs(Int(original) - Int(result)) <= Int(tolerance))
        }
    }

    @Test("silêncio codifica para o byte padrão G.711")
    func silenceEncoding() {
        #expect(G711.linearToMuLaw(0) == 0xFF)
        #expect(G711.linearToALaw(0) == 0xD5)
    }

    @Test("byte de payload → dispatch por codec")
    func codecDispatch() {
        let samples: [Int16] = [1234, -5678]
        #expect(G711.encode(samples, codec: .pcmu) == G711.encodeMuLaw(samples))
        #expect(G711.encode(samples, codec: .pcma) == G711.encodeALaw(samples))
    }
}

@Suite("RTPPacket")
struct RTPPacketTests {
    @Test("build produz header de 12 bytes com campos big-endian corretos")
    func buildHeader() {
        let payload: [UInt8] = Array(0..<160)
        let data = RTPPacket.build(
            payloadType: 0, sequenceNumber: 0x1234, timestamp: 0xAABBCCDD,
            ssrc: 0x11223344, payload: payload
        )
        #expect(data.count == 12 + 160)
        #expect(data[0] == 0x80) // versão 2
        #expect(data[1] == 0x00) // PT=0, sem marker
        #expect(data[2] == 0x12 && data[3] == 0x34) // sequence
    }

    @Test("build + parse é roundtrip")
    func roundtrip() {
        let payload: [UInt8] = [1, 2, 3, 4, 5]
        let data = RTPPacket.build(
            payloadType: 8, sequenceNumber: 42, timestamp: 160, ssrc: 999,
            payload: payload, marker: true
        )
        let parsed = RTPPacket.parse(data)

        #expect(parsed?.payloadType == 8)
        #expect(parsed?.sequenceNumber == 42)
        #expect(parsed?.timestamp == 160)
        #expect(parsed?.ssrc == 999)
        #expect(parsed.map { Array($0.payload) } == payload)
    }

    @Test("pacotes curtos demais ou versão inválida são rejeitados")
    func rejectsInvalid() {
        #expect(RTPPacket.parse(Data([0x80, 0x00])) == nil)
        var bad = RTPPacket.build(payloadType: 0, sequenceNumber: 1, timestamp: 0, ssrc: 0, payload: [1, 2, 3])
        bad[0] = 0x40 // versão 1
        #expect(RTPPacket.parse(bad) == nil)
    }
}

@Suite("SDP")
struct SDPTests {
    @Test("oferta com PCMU+PCMA contém rtpmap e porta")
    func buildOffer() {
        let sdp = SDP.audioDescription(sessionId: "123", host: "192.168.0.5", rtpPort: 40000, codecs: [.pcmu, .pcma])
        #expect(sdp.contains("m=audio 40000 RTP/AVP 0 8"))
        #expect(sdp.contains("a=rtpmap:0 PCMU/8000"))
        #expect(sdp.contains("a=rtpmap:8 PCMA/8000"))
        #expect(sdp.contains("c=IN IP4 192.168.0.5"))
        #expect(sdp.contains("a=ptime:20"))
    }

    @Test("parse extrai endereço, porta e codec negociado")
    func parseRemote() {
        let sdp = """
        v=0\r
        o=- 1 1 IN IP4 10.0.0.1\r
        s=-\r
        c=IN IP4 10.0.0.1\r
        t=0 0\r
        m=audio 5004 RTP/AVP 8 0 101\r
        a=rtpmap:8 PCMA/8000\r
        a=rtpmap:0 PCMU/8000\r
        """
        let remote = SDP.parseRemoteMedia(sdp)
        #expect(remote?.connectionAddress == "10.0.0.1")
        #expect(remote?.audioPort == 5004)
        #expect(remote?.negotiatedCodec == .pcma) // primeiro da lista remota
    }

    @Test("negotiatedCodec(preferring:) honra nossa preferência quando ofertada")
    func negotiatedCodecHonorsLocalPreference() {
        let sdp = "v=0\r\nc=IN IP4 10.0.0.1\r\nm=audio 5004 RTP/AVP 8 0\r\n"
        let remote = SDP.parseRemoteMedia(sdp)
        // Remoto prefere PCMA, mas oferece ambos: nossa preferência vence.
        #expect(remote?.negotiatedCodec(preferring: .pcmu) == .pcmu)
        #expect(remote?.negotiatedCodec(preferring: .pcma) == .pcma)
    }

    @Test("negotiatedCodec(preferring:) cai na ordem remota quando o nosso não é ofertado")
    func negotiatedCodecFallsBackToRemoteOrder() {
        let sdp = "v=0\r\nc=IN IP4 10.0.0.1\r\nm=audio 5004 RTP/AVP 0 101\r\n"
        let remote = SDP.parseRemoteMedia(sdp)
        #expect(remote?.negotiatedCodec(preferring: .pcma) == .pcmu)
    }

    @Test("offerOrder põe o codec preferido primeiro, sempre com os dois G.711")
    func offerOrderFollowsPreference() {
        #expect(G711Codec.offerOrder(preferring: .pcma) == [.pcma, .pcmu])
        #expect(G711Codec.offerOrder(preferring: .pcmu) == [.pcmu, .pcma])

        let sdp = SDP.audioDescription(
            sessionId: "1",
            host: "10.0.0.9",
            rtpPort: 40000,
            codecs: G711Codec.offerOrder(preferring: .pcma)
        )
        #expect(sdp.contains("m=audio 40000 RTP/AVP 8 0"))
    }

    @Test("c= de mídia sobrepõe c= de sessão")
    func mediaLevelConnectionWins() {
        let sdp = "v=0\r\nc=IN IP4 1.1.1.1\r\nm=audio 6000 RTP/AVP 0\r\nc=IN IP4 2.2.2.2\r\na=rtpmap:0 PCMU/8000\r\n"
        #expect(SDP.parseRemoteMedia(sdp)?.connectionAddress == "2.2.2.2")
    }

    @Test("SDP sem áudio ou sem porta é rejeitado")
    func rejectsInvalid() {
        #expect(SDP.parseRemoteMedia("v=0\r\nm=video 5000 RTP/AVP 96\r\n") == nil)
        #expect(SDP.parseRemoteMedia("") == nil)
    }

    @Test("oferta com telephone-event inclui PT, rtpmap e fmtp")
    func offerWithTelephoneEvent() {
        let sdp = SDP.audioDescription(
            sessionId: "1", host: "10.0.0.2", rtpPort: 40000,
            codecs: [.pcmu, .pcma], telephoneEventPayloadType: 101
        )
        #expect(sdp.contains("m=audio 40000 RTP/AVP 0 8 101"))
        #expect(sdp.contains("a=rtpmap:101 telephone-event/8000"))
        #expect(sdp.contains("a=fmtp:101 0-16"))
    }

    @Test("parse extrai o PT do telephone-event remoto (mesmo não sendo 101)")
    func parseTelephoneEventPT() {
        let sdp = "v=0\r\nc=IN IP4 10.0.0.1\r\nm=audio 5004 RTP/AVP 8 96\r\n" +
            "a=rtpmap:8 PCMA/8000\r\na=rtpmap:96 telephone-event/8000\r\na=fmtp:96 0-16\r\n"
        let remote = SDP.parseRemoteMedia(sdp)
        #expect(remote?.telephoneEventPayloadType == 96)
        #expect(remote?.negotiatedCodec == .pcma)
    }
}

@Suite("RTP DTMF (RFC 4733)")
struct RTPDTMFTests {
    @Test("mapeamento de dígitos para códigos de evento")
    func digitCodes() {
        #expect(RTPPacket.DTMF.code(for: "0") == 0)
        #expect(RTPPacket.DTMF.code(for: "9") == 9)
        #expect(RTPPacket.DTMF.code(for: "*") == 10)
        #expect(RTPPacket.DTMF.code(for: "#") == 11)
        #expect(RTPPacket.DTMF.code(for: "x") == nil)
    }

    @Test("payload de evento: E-bit, volume e duração big-endian")
    func eventPayload() {
        let running = RTPPacket.DTMF.payload(event: 5, endOfEvent: false, duration: 320)
        #expect(running == [5, 0x0A, 0x01, 0x40])

        let ended = RTPPacket.DTMF.payload(event: 11, endOfEvent: true, duration: 1120)
        #expect(ended == [11, 0x8A, 0x04, 0x60])
    }
}
