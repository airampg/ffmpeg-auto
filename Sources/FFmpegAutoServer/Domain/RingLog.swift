import Foundation

public struct RingLog: Sendable {
    public private(set) var content: String
    public let capacity: Int

    public init(capacity: Int = 80_000) {
        self.capacity = capacity
        self.content = ""
    }

    public mutating func append(_ text: String) {
        content += text
        if content.count > capacity {
            content.removeFirst(content.count - capacity)
        }
    }
}
