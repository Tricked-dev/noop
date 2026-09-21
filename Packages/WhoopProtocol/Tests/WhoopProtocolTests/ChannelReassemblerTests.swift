import XCTest
@testable import WhoopProtocol

final class ChannelReassemblerTests: XCTestCase {
    private func frame(_ payload: [UInt8], family: DeviceFamily) -> [UInt8] {
        if family == .whoop5 { return puffinCommandFrame(cmd: 22, seq: 7, payload: payload) }
        let inner: [UInt8] = [47, 7, 24] + payload
        let length = inner.count + 4
        let size = [UInt8(length & 255), UInt8(length >> 8)]
        let crc = crc32(inner)
        return [0xAA] + size + [crc8(size)] + inner +
            [UInt8(truncatingIfNeeded: crc), UInt8(truncatingIfNeeded: crc >> 8),
             UInt8(truncatingIfNeeded: crc >> 16), UInt8(truncatingIfNeeded: crc >> 24)]
    }

    func testRepliesAndEventsDoNotCorruptFragmentedHistory() {
        for family in [DeviceFamily.whoop4, .whoop5] {
            let history = frame((0..<1917).map { UInt8(truncatingIfNeeded: $0) }, family: family)
            let reply = frame([1, 2, 3, 4], family: family)
            let event = frame([5, 6, 7, 8], family: family)
            let r = ChannelReassembler<String>(family: family)
            XCTAssertTrue(r.feed(Array(history.prefix(244)), channel: "history").isEmpty)
            XCTAssertEqual(r.feed(reply, channel: "command"), [reply])
            XCTAssertEqual(r.feed(event, channel: "events"), [event])
            var result: [[UInt8]] = []
            for offset in stride(from: 244, to: history.count, by: 244) {
                result += r.feed(Array(history[offset..<min(offset + 244, history.count)]), channel: "history")
            }
            XCTAssertEqual(result, [history])
            XCTAssertTrue(result.allSatisfy { verifyFrame($0, family: family).ok })
        }
    }

    func testAllChannelsCanBeFragmentedAtTheSameTime() {
        let frames = (0..<3).map { frame(Array(repeating: UInt8($0), count: 40), family: .whoop4) }
        let r = ChannelReassembler<Int>()
        for channel in 0..<3 { XCTAssertTrue(r.feed(Array(frames[channel].prefix(5)), channel: channel).isEmpty) }
        for channel in (0..<3).reversed() {
            XCTAssertEqual(r.feed(Array(frames[channel].dropFirst(5)), channel: channel), [frames[channel]])
        }
    }

    func testOneBrokenChannelCannotBlockAnotherAndDropCountIsAggregated() {
        let r = ChannelReassembler<String>()
        let valid = frame([9, 8, 7], family: .whoop4)
        XCTAssertTrue(r.feed([0xAA, 0x20, 0, 0], channel: "incomplete").isEmpty)
        XCTAssertTrue(r.feed([0xAA, 0, 0, 0], channel: "corrupt").isEmpty)
        XCTAssertEqual(r.belowMinimumLengthDrops, 1)
        XCTAssertEqual(r.feed(valid + valid, channel: "healthy"), [valid, valid])
        XCTAssertEqual(r.belowMinimumLengthDrops, 1)
    }
}
