import XCTest
import SwiftUI
@testable import AndromedaUI

/// Regression tests for TypingLog timing — hostile `charactersPerSecond` /
/// `holdSeconds` values must never reach arithmetic that feeds `String.prefix`
/// or `Int.init(_:)` with negative or NaN operands.
@MainActor
final class TypingLogTimingTests: XCTestCase {

    // MARK: init clamps

    func testNegativeCharactersPerSecondClampsToFloor() {
        let log = TypingLog("hello", tint: .andromedaTeal, charactersPerSecond: -42, holdSeconds: 2.4)
        XCTAssertGreaterThanOrEqual(log.charactersPerSecond, 1)
    }

    func testZeroCharactersPerSecondClampsToFloor() {
        let log = TypingLog("hello", tint: .andromedaTeal, charactersPerSecond: 0, holdSeconds: 2.4)
        XCTAssertGreaterThanOrEqual(log.charactersPerSecond, 1)
    }

    func testNonFiniteCharactersPerSecondFallsBackToDefault() {
        let nan = TypingLog("x", tint: .andromedaTeal, charactersPerSecond: .nan, holdSeconds: 1)
        XCTAssertEqual(nan.charactersPerSecond, 42)
        let inf = TypingLog("x", tint: .andromedaTeal, charactersPerSecond: .infinity, holdSeconds: 1)
        XCTAssertEqual(inf.charactersPerSecond, 42)
    }

    func testNegativeHoldSecondsClampsToZero() {
        let log = TypingLog("x", tint: .andromedaTeal, charactersPerSecond: 42, holdSeconds: -10)
        XCTAssertGreaterThanOrEqual(log.holdSeconds, 0)
    }

    func testNonFiniteHoldSecondsFallsBackToDefault() {
        let log = TypingLog("x", tint: .andromedaTeal, charactersPerSecond: 42, holdSeconds: .nan)
        XCTAssertEqual(log.holdSeconds, 2.4)
    }

    // MARK: loop math — degenerate inputs stay in range

    func testFrameNeverReturnsNegativeShownForHostileTiming() {
        // The exact trap Codex flagged: negative rate through the old math
        // produced negative `shown` and trapped `String.prefix`.
        let f = TypingLog.frame(textLength: 12, charactersPerSecond: -40, holdSeconds: -3, at: 7.7)
        XCTAssertGreaterThanOrEqual(f.shown, 0)
        XCTAssertLessThanOrEqual(f.shown, 12)
        XCTAssertGreaterThanOrEqual(f.loop, 0)
        XCTAssertTrue(f.loop.isFinite)
    }

    func testFrameSurvivesZeroPeriod() {
        // Old math: typing + hold == 0 ⇒ division by zero ⇒ NaN ⇒ Int(NaN) trap.
        let f = TypingLog.frame(textLength: 0, charactersPerSecond: 1, holdSeconds: 0, at: 1234)
        XCTAssertEqual(f.shown, 0)
    }

    func testFrameSurvivesExtremeFiniteRates() {
        // Rates large enough that loop * cps overflows Double or Int64.
        let f = TypingLog.frame(textLength: 5, charactersPerSecond: 1e308, holdSeconds: 1e308, at: 99)
        XCTAssertEqual(f.shown, 5, "Overflow typing speed reads as fully typed")
        XCTAssertTrue(f.loop.isFinite)
    }

    func testFrameClampsShownToTextLength() {
        let f = TypingLog.frame(textLength: 3, charactersPerSecond: 1_000_000, holdSeconds: 10, at: 0.5)
        XCTAssertLessThanOrEqual(f.shown, 3)
    }

    func testFrameProgressesNormallyWithValidTiming() {
        // 10 chars at 10 cps ⇒ fully typed at t = 1, then holds.
        XCTAssertEqual(TypingLog.frame(textLength: 10, charactersPerSecond: 10, holdSeconds: 2, at: 0).shown, 0)
        XCTAssertEqual(TypingLog.frame(textLength: 10, charactersPerSecond: 10, holdSeconds: 2, at: 0.5).shown, 5)
        XCTAssertEqual(TypingLog.frame(textLength: 10, charactersPerSecond: 10, holdSeconds: 2, at: 1.5).shown, 10)
    }
}
