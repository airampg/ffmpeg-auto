import AppKit
import Foundation
import FFmpegAutoCore

public struct FinderService: FinderOpening {
    public init() {}

    public func openFolder(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw AppActionError.openFolderFailed(url.path)
        }
    }
}

public struct TrashService: TrashHandling {
    public init() {}

    public func moveToTrash(_ url: URL) throws {
        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        } catch {
            throw AppActionError.trashFailed(error.localizedDescription)
        }
    }
}
