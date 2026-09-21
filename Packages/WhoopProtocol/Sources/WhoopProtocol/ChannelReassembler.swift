import Foundation

/// Reassembles independent transport streams without mixing their partial frames.
/// Each Bluetooth notification characteristic must keep its own byte buffer.
public final class ChannelReassembler<Channel: Hashable> {
    private let family: DeviceFamily
    private var channels: [Channel: Reassembler] = [:]
    public private(set) var belowMinimumLengthDrops = 0

    public init(family: DeviceFamily = .whoop4) { self.family = family }

    public func feed(_ fragment: [UInt8], channel: Channel) -> [[UInt8]] {
        let parser: Reassembler
        if let existing = channels[channel] {
            parser = existing
        } else {
            parser = Reassembler(family: family)
            channels[channel] = parser
        }
        let previousDrops = parser.belowMinimumLengthDrops
        let frames = parser.feed(fragment)
        belowMinimumLengthDrops += parser.belowMinimumLengthDrops - previousDrops
        return frames
    }
}
