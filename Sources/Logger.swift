import Foundation

public class Logger {
    public static let shared = Logger()
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter
    private var logFileURL: URL?
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Set up log file in app support directory
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDirectory = appSupport.appendingPathComponent("Otto's Print to PDF")
            let logsDirectory = appDirectory.appendingPathComponent("Logs")
            
            // Create directories if needed
            try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            
            // Create log file with timestamp
            let timestamp = ISO8601DateFormatter().string(from: Date())
            logFileURL = logsDirectory.appendingPathComponent("install_log_\(timestamp).txt")
        }
    }
    
    public enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }
    
    public func log(_ message: String, level: Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let filename = (file as NSString).lastPathComponent
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(filename):\(line) \(function)] \(message)\n"
        
        // Print to console
        print(logMessage, terminator: "")
        
        // Write to file
        if let logFileURL = logFileURL {
            try? logMessage.data(using: .utf8)?.write(to: logFileURL, options: .atomic)
        }
    }
}
