import XCTest
@testable import CapaCore

final class DeliveryTests: XCTestCase {
    func testOptOutPreventsAutomaticSpeechAndDoesNotAcknowledge() {
        var policy = DeliveryPolicy(available: false)
        XCTAssertFalse(policy.begin("event-1"))
        XCTAssertFalse(policy.acknowledged.contains("event-1"))
        policy.available = true
        XCTAssertTrue(policy.begin("event-1"))
    }

    func testDuplicatePushCannotSpeakTwiceAndInterruptedSpeechCanRetry() {
        var policy = DeliveryPolicy(available: true)
        XCTAssertTrue(policy.begin("event-1"))
        XCTAssertFalse(policy.begin("event-1"))
        policy.interrupted()
        XCTAssertTrue(policy.begin("event-1"))
        policy.finished("event-1")
        XCTAssertFalse(policy.begin("event-1"))
    }

    func testOnlyOneIncomingUtteranceCanBeActive() {
        var policy = DeliveryPolicy(available: true)
        XCTAssertTrue(policy.begin("a"))
        XCTAssertFalse(policy.begin("b"))
        policy.finished("a")
        XCTAssertTrue(policy.begin("b"))
    }

    func testAmbiguousSubmissionRetainsItsOriginalRequestID() throws {
        var memo = PendingMemo(text: "Research battery recycling")
        let originalID = memo.requestID
        memo.markSending()
        memo.markUnconfirmed()
        let restored = try JSONDecoder().decode(PendingMemo.self, from: JSONEncoder().encode(memo))
        XCTAssertEqual(restored.requestID, originalID)
        XCTAssertEqual(restored.phase, .unconfirmed)
        XCTAssertFalse(restored.canDiscard)
    }

    func testAcceptanceRequiresHermesRunID() {
        var memo = PendingMemo(text: "Research batteries")
        memo.accept(runID: nil)
        XCTAssertEqual(memo.phase, .unconfirmed)
        memo.accept(runID: "run-1")
        XCTAssertEqual(memo.phase, .accepted)
    }
}
