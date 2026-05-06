import Foundation

public protocol FFmpegLocating {
    func locateFFmpeg(overridePath: String?) -> FFmpegLocation
}

public protocol FFmpegRunning {
    func run(command: FFmpegCommand, logHandler: @escaping @Sendable (String) -> Void) async throws -> FFmpegResult
}

public protocol FinderOpening {
    func openFolder(_ url: URL) throws
}

public protocol TrashHandling {
    func moveToTrash(_ url: URL) throws
}

public protocol FilePicking {
    func pickInputFile() async -> URL?
    func pickOutputFolder() async -> URL?
}
