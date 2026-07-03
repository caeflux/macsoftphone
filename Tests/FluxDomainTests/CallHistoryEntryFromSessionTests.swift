import Testing
import Foundation
@testable import FluxDomain

@Suite("CallHistoryEntry a partir de CallSession")
struct CallHistoryEntryFromSessionTests {
    private let start = Date(timeIntervalSince1970: 1_750_000_000)

    private func session(
        direction: CallDirection = .outgoing,
        state: CallState,
        connectedAt: Date? = nil,
        endedAt: Date? = nil
    ) -> CallSession {
        CallSession(
            id: "call-1",
            direction: direction,
            remoteNumber: "51999998888",
            state: state,
            createdAt: start,
            connectedAt: connectedAt,
            endedAt: endedAt
        )
    }

    @Test("chamada atendida e encerrada vira 'completed' com duração")
    func completedCall() throws {
        let call = session(
            state: .ended(reason: .localHangup),
            connectedAt: start.addingTimeInterval(5),
            endedAt: start.addingTimeInterval(65)
        )
        let entry = try #require(CallHistoryEntry(session: call, accountURI: "sip:1001@d"))

        #expect(entry.outcome == .completed)
        #expect(entry.duration == 60)
        #expect(entry.startedAt == start)
        #expect(entry.accountURI == "sip:1001@d")
    }

    @Test("saída encerrada antes de atender vira 'cancelled' com duração zero")
    func cancelledOutgoing() throws {
        let call = session(
            state: .ended(reason: .localHangup),
            endedAt: start.addingTimeInterval(8)
        )
        let entry = try #require(CallHistoryEntry(session: call, accountURI: ""))

        #expect(entry.outcome == .cancelled)
        #expect(entry.duration == 0)
    }

    @Test("entrada não atendida vira 'missed'")
    func missedIncoming() throws {
        let call = session(
            direction: .incoming,
            state: .ended(reason: .remoteHangup),
            endedAt: start.addingTimeInterval(10)
        )
        let entry = try #require(CallHistoryEntry(session: call, accountURI: ""))
        #expect(entry.outcome == .missed)
    }

    @Test("entrada recusada vira 'rejected'; falha vira 'failed'")
    func rejectedAndFailed() throws {
        let rejected = session(direction: .incoming, state: .ended(reason: .rejected))
        #expect(try #require(CallHistoryEntry(session: rejected, accountURI: "")).outcome == .rejected)

        let failed = session(state: .failed(error: .serverError))
        #expect(try #require(CallHistoryEntry(session: failed, accountURI: "")).outcome == .failed)
    }

    @Test("sessão ainda viva não gera registro")
    func liveSessionsProduceNothing() {
        for state in [CallState.dialing, .ringing, .active, .incoming, .held, .ending] {
            #expect(CallHistoryEntry(session: session(state: state), accountURI: "") == nil)
        }
    }
}
