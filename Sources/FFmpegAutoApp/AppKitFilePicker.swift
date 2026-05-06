import AppKit
import Foundation
import UniformTypeIdentifiers
import FFmpegAutoCore

struct AppKitFilePicker: FilePicking {
    func pickInputFile() async -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.title = "Select Meeting Recording"
            panel.prompt = "Select"
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.movie, .audio, .mpeg4Movie, .quickTimeMovie]
            return panel.runModal() == .OK ? panel.url : nil
        }
    }

    func pickOutputFolder() async -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.title = "Choose Output Folder"
            panel.prompt = "Choose"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            return panel.runModal() == .OK ? panel.url : nil
        }
    }
}
