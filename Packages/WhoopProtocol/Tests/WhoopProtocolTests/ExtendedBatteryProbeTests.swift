import XCTest
@testable import WhoopProtocol

/// #592: the pure formatter for the GET_EXTENDED_BATTERY_INFO probe result. Byte-parity twin of the Kotlin
/// `ExtendedBatteryProbeFormatTest` (same fixtures, same expectations) — including the REAL WHOOP 4.0
/// capture that resolved the issue (opcode 98 accepted, 29-byte payload, mV=3970 → 3.97 V).
final class ExtendedBatteryProbeTests: XCTestCase {
    func testSyntheticLivePacketCannotOpenBatteryProbeEvenWhileWaiting() {
        // Construct the opcode collision without embedding a device capture.
        let frame = frameFromPayload([UInt8](repeating: 0, count: 17), type: 40, seq: 1, cmd: 98)
        XCTAssertTrue(verifyFrame(frame, family: .whoop4).ok)
        XCTAssertEqual(frame[6], 98,
                       "the former opcode-only dispatch mistook this timestamp byte for a response")
        XCTAssertEqual(parseFrame(frame, family: .whoop4).typeName, "REALTIME_DATA")
        for waiting in [false, true] {
            XCTAssertFalse(ExtendedBatteryProbe.acceptsResponse(frame, family: .whoop4, waitingForReply: waiting))
        }
    }

    func testProbeNeedsAnExplicitOutstandingRequestOnBothFamilies() {
        for family: DeviceFamily in [.whoop4, .whoop5] {
            let frame = probeResponse(family: family)
            XCTAssertTrue(ExtendedBatteryProbe.acceptsResponse(frame, family: family, waitingForReply: true))
            XCTAssertFalse(ExtendedBatteryProbe.acceptsResponse(frame, family: family, waitingForReply: false),
                           "cancelled, completed or never-requested probes must remain silent")
        }
    }

    func testCorruptOrTruncatedRepliesNeverPublishAReport() {
        for family: DeviceFamily in [.whoop4, .whoop5] {
            let frame = probeResponse(family: family)
            for count in 0..<frame.count {
                XCTAssertFalse(ExtendedBatteryProbe.acceptsResponse(Array(frame.prefix(count)), family: family,
                                                                    waitingForReply: true))
            }
            for index in frame.indices {
                var corrupt = frame
                corrupt[index] ^= 1
                XCTAssertFalse(ExtendedBatteryProbe.acceptsResponse(corrupt, family: family, waitingForReply: true))
            }
        }
    }

    func testOtherPacketsAndPendingAcknowledgementsCannotCompleteProbe() {
        for family: DeviceFamily in [.whoop4, .whoop5] {
            for type: UInt8 in [35, 40, 43, 47, 48, 49, 50] {
                XCTAssertFalse(ExtendedBatteryProbe.acceptsResponse(probeResponse(family: family, type: type),
                                                                    family: family, waitingForReply: true))
            }
            XCTAssertFalse(ExtendedBatteryProbe.acceptsResponse(probeResponse(family: family, result: 2),
                                                                family: family, waitingForReply: true))
        }
    }

    private func probeResponse(family: DeviceFamily, type: UInt8 = 36, result: UInt8 = 1) -> [UInt8] {
        let payload: [UInt8] = [7, result, 1, 2, 3]
        if family == .whoop5 {
            return puffinCommandFrame(cmd: 98, seq: 8, payload: payload, type: type)
        }
        return frameFromPayload(payload, type: type, seq: 8, cmd: 98)
    }


    private func hexToBytes(_ h: String) -> [UInt8] {
        let c = Array(h)
        return stride(from: 0, to: c.count, by: 2).map {
            UInt8((Int(String(c[$0]), radix: 16)! << 4) | Int(String(c[$0 + 1]), radix: 16)!)
        }
    }

    // The exact frame captured on a real WHOOP 4.0 (cmd byte 0x62=98 @6; total 40 B, len field 0x24=36).
    private let realFrame = "aa2400fa24c6620d010165006bff820f0c0128000f05e90321120200010100001a0000004675fe58"

    func testWhoop4RealCapture_acceptedWithVoltageAndGrid() {
        let (text, payHex) = ExtendedBatteryProbe.format(frame: hexToBytes(realFrame), cmdOff: 6, isWhoop5: false, prevPayloadHex: nil)
        XCTAssertTrue(text.contains("WHOOP 4.0"))
        XCTAssertTrue(text.contains("opcode 98 ACCEPTED — 29-byte payload"))
        XCTAssertTrue(text.contains(realFrame))                  // full raw hex on one copyable line
        XCTAssertTrue(text.contains("Voltage: 3.97 V"))          // pay[7..8] = 0x0f82 = 3970 mV
        XCTAssertTrue(text.contains("(mV=3970 @07)"))
        XCTAssertTrue(text.contains("  @00  0d 01 01 65 00 6b ff 82"))  // offset-labelled hex grid, 8/row
        XCTAssertTrue(text.contains("first capture"))            // no previous payload to diff
        XCTAssertEqual(payHex?.count, 29 * 2)                    // 29-byte payload persisted for the next diff
    }

    func testDiff_flagsTheChangedBytes() {
        let first = hexToBytes(realFrame)
        let (_, prev) = ExtendedBatteryProbe.format(frame: first, cmdOff: 6, isWhoop5: false, prevPayloadHex: nil)
        // Flip one payload byte (frame[10] = payload offset 3) to simulate a second capture at another state.
        var second = first
        second[10] = 0x40
        let (text, _) = ExtendedBatteryProbe.format(frame: second, cmdOff: 6, isWhoop5: false, prevPayloadHex: prev)
        XCTAssertTrue(text.contains("Δ vs previous capture:"))
        XCTAssertTrue(text.contains("@03:65→40"))                // payload offset 3 moved 0x65→0x40
        XCTAssertTrue(text.contains("SoC/capacity"))
    }

    func testBareStub_isCalledOut() {
        // 11-byte frame: cmd@6=0x62 then ONLY the 4-byte CRC tail, so payEnd(7) == payStart(7) ⇒ no payload.
        let (text, payHex) = ExtendedBatteryProbe.format(frame: hexToBytes("aa0700fa24006246758858"), cmdOff: 6, isWhoop5: false, prevPayloadHex: nil)
        XCTAssertTrue(text.contains("bare stub"))
        XCTAssertNil(payHex)
    }

    func testWhoop5Unsupported_isDecisiveVerdict() {
        // 5/MG frame with the command byte 0x62 @10 and result code 3 (UNSUPPORTED) @12.
        let (text, _) = ExtendedBatteryProbe.format(frame: hexToBytes("aa000c000000000000006200030046758858"), cmdOff: 10, isWhoop5: true, prevPayloadHex: nil)
        XCTAssertTrue(text.contains("REJECTED by firmware (UNSUPPORTED)"))
        XCTAssertTrue(text.contains("Result code @12: UNSUPPORTED(3)"))
    }

    func testWhoop5Payload_doesNotPrintAGuessedVoltage() {
        // 5/MG SUCCESS(1) with a ≥9-byte payload: the mV offset is unconfirmed on 5/MG, so NO voltage line.
        let (text, _) = ExtendedBatteryProbe.format(frame: hexToBytes("aa000c000000000000006200010102030405060708090a46758858"), cmdOff: 10, isWhoop5: true, prevPayloadHex: nil)
        XCTAssertTrue(text.contains("Result code @12: SUCCESS(1)"))
        XCTAssertFalse(text.contains("Voltage:"))
    }
}
