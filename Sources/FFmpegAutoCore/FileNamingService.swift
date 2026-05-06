import Foundation

public struct FileNamingService {
    public init() {}

    public func outputPrefix(for inputFile: URL, filenamePrefix: String = "meeting") -> String {
        let stem = inputFile.deletingPathExtension().lastPathComponent
        let sanitized = sanitize(stem)
        let safePrefix = sanitize(filenamePrefix)
        return "\(safePrefix.isEmpty ? "meeting" : safePrefix)\(sanitized.isEmpty ? "recording" : sanitized)"
    }

    public func outputPattern(inputFile: URL, outputFolder: URL, settings: AudioConversionSettings = .transcriptionDefault) -> URL {
        outputFolder.appendingPathComponent("\(outputPrefix(for: inputFile, filenamePrefix: settings.filenamePrefix))_%03d.\(settings.container.fileExtension)")
    }

    public func countGeneratedOutputs(inputFile: URL, outputFolder: URL, settings: AudioConversionSettings = .transcriptionDefault, fileManager: FileManager = .default) -> Int? {
        guard let names = try? fileManager.contentsOfDirectory(atPath: outputFolder.path) else { return nil }
        let prefix = outputPrefix(for: inputFile, filenamePrefix: settings.filenamePrefix) + "_"
        let suffix = ".\(settings.container.fileExtension)"
        return names.filter { name in
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
            let start = name.index(name.startIndex, offsetBy: prefix.count)
            let end = name.index(name.endIndex, offsetBy: -suffix.count)
            let number = name[start..<end]
            return number.count >= 3 && number.allSatisfy(\.isNumber)
        }.count
    }

    public func hasExistingSegmentOutputs(inputFile: URL, outputFolder: URL, settings: AudioConversionSettings = .transcriptionDefault, fileManager: FileManager = .default) -> Bool {
        guard let count = countGeneratedOutputs(inputFile: inputFile, outputFolder: outputFolder, settings: settings, fileManager: fileManager) else { return false }
        return count > 0
    }

    public func sanitizedPrefix(_ prefix: String) -> String {
        sanitize(prefix)
    }

    private func sanitize(_ stem: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = stem.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ".-_").union(.whitespacesAndNewlines))
    }
}
