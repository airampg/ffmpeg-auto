import Logging

public enum LoggingSetup {
    public static func bootstrap(level: String) {
        let parsedLevel = parseLevel(level)
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = parsedLevel
            return handler
        }
    }

    private static func parseLevel(_ raw: String) -> Logger.Level {
        switch raw.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "info": return .info
        case "warning", "warn": return .warning
        case "error": return .error
        case "critical": return .critical
        default: return .info
        }
    }
}
