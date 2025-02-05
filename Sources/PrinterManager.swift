import Foundation
import AppKit
import UniformTypeIdentifiers
import CUPS

class PrinterManager: ObservableObject {
    static let shared = PrinterManager()
    
    @Published var isAutoSaveEnabled = false
    @Published var isInstalled = false
    
    private let printerName = "Otto's Print to PDF"
    private let spoolDirectory = "/var/spool/cups-pdf/"
    
    private var fileManager = FileManager.default
    private let cupsQueue = DispatchQueue(label: "com.otto.printopdf.cups")
    
    init() {
        // Defer printer check to avoid crash if CUPS is not running
        DispatchQueue.main.async {
            self.checkPrinterInstallation()
        }
    }
    
    private func checkPrinterInstallation() {
        cupsQueue.async {
            // First check if CUPS is available
            var dest: UnsafeMutablePointer<cups_dest_t>?
            let count = cupsGetDests(&dest)
            
            if count == 0 {
                // CUPS might not be running, set as not installed
                DispatchQueue.main.async {
                    self.isInstalled = false
                }
                if dest != nil {
                    cupsFreeDests(count, dest)
                }
                return
            }
            
            defer { cupsFreeDests(count, dest) }
            
            let found = (0..<count).contains { i in
                let printer = dest!.advanced(by: Int(i)).pointee
                let name = String(cString: printer.name)
                return name == self.printerName
            }
            
            DispatchQueue.main.async {
                self.isInstalled = found
            }
        }
    }
    
    func installPrinter() throws {
        print("Starting printer installation...")
        
        // Check if CUPS is running
        var dest: UnsafeMutablePointer<cups_dest_t>?
        let destCount = cupsGetDests(&dest)
        defer { if dest != nil { cupsFreeDests(destCount, dest) } }
        
        if destCount == 0 {
            print("CUPS service not running")
            throw NSError(domain: "CUPSError", code: 9,
                        userInfo: [NSLocalizedDescriptionKey: "CUPS service is not running"])
        }
        
        print("CUPS service is running")
        
        // Get the path to the installation script
        guard let bundlePath = Bundle.main.resourcePath else {
            print("Failed to get bundle resource path")
            throw NSError(domain: "CUPSError", code: 11,
                        userInfo: [NSLocalizedDescriptionKey: "Could not locate installation script"])
        }
        
        print("Bundle resource path: \(bundlePath)")
        
        let scriptName = "install-printer.sh"
        let resourcePath = (bundlePath as NSString).appendingPathComponent(scriptName)
        
        // Create a temporary directory
        let tempDir = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: URL(fileURLWithPath: bundlePath), create: true)
        let tempScriptPath = (tempDir.path as NSString).appendingPathComponent(scriptName)
        
        defer {
            // Clean up temporary directory
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Copy the script to temp directory
        try fileManager.copyItem(atPath: resourcePath, toPath: tempScriptPath)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptPath)
        
        // Pass the bundle path to the script so it can find the CUPS backend and PPD
        // Create and configure the process
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        
        // Properly quote paths for shell command
        let quotedTempPath = tempScriptPath.replacingOccurrences(of: "\"", with: "\\\"")
        let quotedBundlePath = bundlePath.replacingOccurrences(of: "\"", with: "\\\"")
        
        print("Using temp script path: \(quotedTempPath)")
        print("Using bundle path: \(quotedBundlePath)")
        
        // Use AppleScript with explicit sudo command and proper path escaping
        let scriptCommand = """
        tell application "System Events"
            activate
            do shell script "sudo " & (quoted form of "\(tempScriptPath)") & " " & (quoted form of "\(bundlePath)") with administrator privileges
        end tell
        """
        task.arguments = ["-e", scriptCommand]
        
        // Capture output and errors
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let status = task.terminationStatus
            
            // Capture both standard output and error output
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            print("Installation script output: \(output)")
            if !errorOutput.isEmpty {
                print("Installation script error output: \(errorOutput)")
            }
            print("Installation script completed with status: \(status)")
            
            if status != 0 {
                // Log both error and output for better debugging
                print("Error output: \(errorOutput)")
                print("Standard output: \(output)")
                throw NSError(domain: "CUPSError", code: 12,
                            userInfo: [NSLocalizedDescriptionKey: "Installation failed. Please check your administrator password and try again."])
            }
            
            // Verify the installation
            print("Verifying printer installation...")
            checkPrinterInstallation()
            
            isInstalled = true
        } catch {
            throw NSError(domain: "CUPSError", code: 13,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to run installation script: \(error.localizedDescription)"])
        }
    }
    
    func uninstallPrinter() throws {
        // Check if CUPS is running
        var dest: UnsafeMutablePointer<cups_dest_t>?
        if cupsGetDests(&dest) == 0 {
            cupsFreeDests(0, dest)
            throw NSError(domain: "CUPSError", code: 9,
                        userInfo: [NSLocalizedDescriptionKey: "CUPS service is not running"])
        }
        cupsFreeDests(0, dest)
        
        // Get the path to the uninstallation script
        guard let bundlePath = Bundle.main.resourcePath else {
            throw NSError(domain: "CUPSError", code: 11,
                        userInfo: [NSLocalizedDescriptionKey: "Could not locate uninstallation script"])
        }
        
        let scriptName = "uninstall-printer.sh"
        let resourcePath = (bundlePath as NSString).appendingPathComponent(scriptName)
        
        // Create a temporary directory
        let tempDir = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: URL(fileURLWithPath: bundlePath), create: true)
        let tempScriptPath = (tempDir.path as NSString).appendingPathComponent(scriptName)
        
        defer {
            // Clean up temporary directory
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Copy the script to temp directory
        try fileManager.copyItem(atPath: resourcePath, toPath: tempScriptPath)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptPath)
        
        // Create and configure the process
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        
        // Use AppleScript with explicit sudo command and proper path escaping
        let scriptCommand = """
        tell application "System Events"
            activate
            do shell script "sudo " & (quoted form of "\(tempScriptPath)") & " " & (quoted form of "\(bundlePath)") with administrator privileges
        end tell
        """
        task.arguments = ["-e", scriptCommand]
        
        // Capture output and errors
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let status = task.terminationStatus
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            if status != 0 {
                // Log both error and output for better debugging
                print("Error output: \(errorOutput)")
                print("Standard output: \(output)")
                throw NSError(domain: "CUPSError", code: 12,
                            userInfo: [NSLocalizedDescriptionKey: "Uninstallation failed. Please check your administrator password and try again."])
            }
            
            isInstalled = false
        } catch {
            throw NSError(domain: "CUPSError", code: 13,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to run uninstallation script: \(error.localizedDescription)"])
        }
    }
    
    func handleNewPDF(at spoolPath: String) {
        guard let filename = URL(string: spoolPath)?.lastPathComponent else { return }
        let sourceURL = URL(fileURLWithPath: spoolPath)
        
        if isAutoSaveEnabled {
            // Auto-save to original document's directory
            if let originalURL = NSDocumentController.shared.currentDocument?.fileURL {
                var targetURL = originalURL.deletingLastPathComponent()
                targetURL.appendPathComponent(filename)
                
                // Handle filename conflicts
                var uniqueURL = targetURL
                var counter = 1
                while fileManager.fileExists(atPath: uniqueURL.path) {
                    uniqueURL = targetURL.deletingPathExtension()
                    uniqueURL.appendPathComponent(filename + "_\(counter)")
                    uniqueURL.appendPathExtension("pdf")
                    counter += 1
                }
                
                do {
                    try fileManager.moveItem(at: sourceURL, to: uniqueURL)
                } catch {
                    print("Error moving PDF: \(error)")
                }
            }
        } else {
            // Show save dialog
            let savePanel = NSSavePanel()
            if #available(macOS 11.0, *) {
                savePanel.allowedContentTypes = [UTType.pdf]
            } else {
                savePanel.allowedFileTypes = ["pdf"]
            }
            savePanel.nameFieldStringValue = filename
            
            savePanel.begin { response in
                if response == .OK, let targetURL = savePanel.url {
                    do {
                        try self.fileManager.moveItem(at: sourceURL, to: targetURL)
                    } catch {
                        print("Error saving PDF: \(error)")
                    }
                }
            }
        }
    }
}
