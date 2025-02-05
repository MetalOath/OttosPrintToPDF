import Foundation
import AppKit
import UniformTypeIdentifiers
import CUPS
import Logger

class PrinterManager: ObservableObject {
    // Initialize logger for debugging
    private let log = Logger.shared
    
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
        log.log("Starting printer installation process", level: Logger.Level.info)
        
        // Check accessibility permissions
        let trusted = AXIsProcessTrusted()
        if !trusted {
            throw NSError(domain: "CUPSError", code: 15,
                         userInfo: [NSLocalizedDescriptionKey: "Accessibility permissions required. Please follow these steps:\n1. Open System Settings\n2. Go to Privacy & Security > Accessibility\n3. Find \"Otto's Print to PDF\" in the list\n4. Enable the toggle next to it\n5. Try installing the printer again"])
        }
        
        // Check if already installed
        guard !isInstalled else {
            log.log("Printer is already installed", level: Logger.Level.info)
            return
        }
        
        // Check if CUPS is running
        var dest: UnsafeMutablePointer<cups_dest_t>?
        let destCount = cupsGetDests(&dest)
        defer { if dest != nil { cupsFreeDests(destCount, dest) } }
        
        if destCount == 0 {
            log.log("CUPS service not running", level: Logger.Level.error)
            throw NSError(domain: "CUPSError", code: 9,
                        userInfo: [NSLocalizedDescriptionKey: "CUPS service is not running"])
        }
        
        log.log("CUPS service is running", level: Logger.Level.info)
        
        // Get the path to the installation script
        guard let bundlePath = Bundle.main.resourcePath else {
            log.log("Failed to get bundle resource path", level: Logger.Level.error)
            throw NSError(domain: "CUPSError", code: 11,
                        userInfo: [NSLocalizedDescriptionKey: "Could not locate installation script"])
        }
        
        log.log("Bundle resource path: \(bundlePath)", level: Logger.Level.debug)
        
        let scriptName = "install-printer.sh"
        let scriptPath = (bundlePath as NSString).appendingPathComponent(scriptName)
        
        // Verify all required files exist and are executable
        let requiredFiles = [
            (name: "Installation script", path: scriptPath, shouldBeExecutable: true),
            (name: "CUPS backend", path: (bundlePath as NSString).appendingPathComponent("cups-pdf"), shouldBeExecutable: true),
            (name: "PPD file", path: (bundlePath as NSString).appendingPathComponent("CUPS-PDF.ppd"), shouldBeExecutable: false)
        ]
        
        for file in requiredFiles {
            guard fileManager.fileExists(atPath: file.path) else {
                log.log("\(file.name) not found at path: \(file.path)", level: Logger.Level.error)
                throw NSError(domain: "CUPSError", code: 11,
                            userInfo: [NSLocalizedDescriptionKey: "\(file.name) not found"])
            }
            
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                log.log("\(file.name) is a directory at path: \(file.path)", level: Logger.Level.error)
                throw NSError(domain: "CUPSError", code: 11,
                            userInfo: [NSLocalizedDescriptionKey: "\(file.name) is not properly configured"])
            }
            
            if file.shouldBeExecutable {
                guard fileManager.isExecutableFile(atPath: file.path) else {
                    log.log("\(file.name) is not executable at path: \(file.path)", level: Logger.Level.error)
                    throw NSError(domain: "CUPSError", code: 11,
                                userInfo: [NSLocalizedDescriptionKey: "\(file.name) is not properly configured"])
                }
            }
        }
        
        log.log("Starting installation with NSAppleScript...", level: Logger.Level.info)
        
        // Improved AppleScript with better error handling and timing
        let scriptSource = """
        on run
            try
                tell application "System Events"
                    activate
                    delay 2.0
                end tell
                
                set scriptPath to "\(scriptPath.replacingOccurrences(of: "\"", with: "\\\""))"
                set resourcePath to "\(bundlePath.replacingOccurrences(of: "\"", with: "\\\""))"
                
                set command to quoted form of scriptPath & " " & quoted form of resourcePath
                
                log "Executing command: " & command
                
                try
                    set output to do shell script command with administrator privileges
                on error errMsg
                    error "Failed to obtain administrator privileges: " & errMsg
                end try
                
                if output contains "ERROR:" then
                    error output
                end if
                
                return output
            on error errMsg
                if errMsg contains "User canceled" then
                    error "Installation cancelled by user"
                else if errMsg contains "not allowed to send keystrokes" then
                    error "Failed to authenticate: System Events not authorized"
                else
                    error errMsg
                end if
            end try
        end run
        """
        
        log.log("AppleScript source prepared", level: Logger.Level.debug)
        log.log("AppleScript source:\n\(scriptSource)", level: Logger.Level.debug)
        
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            throw NSError(domain: "CUPSError", code: 13,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create AppleScript"])
        }
        
        log.log("Executing AppleScript...", level: Logger.Level.info)
        let result = script.executeAndReturnError(&error)
        
        if let error = error {
            log.log("AppleScript error: \(error)", level: Logger.Level.error)
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            if errorMessage.contains("cancelled") || errorMessage.contains("canceled") {
                throw NSError(domain: "CUPSError", code: 14,
                            userInfo: [NSLocalizedDescriptionKey: "Installation cancelled by user"])
            } else if errorMessage.contains("not authorized") {
                throw NSError(domain: "CUPSError", code: 15,
                            userInfo: [NSLocalizedDescriptionKey: "System Events not authorized. Please follow these steps:\n1. Open System Settings\n2. Go to Privacy & Security > Accessibility\n3. Find \"Otto's Print to PDF\" in the list\n4. Enable the toggle next to it\n5. Try installing the printer again"])
            } else {
                throw NSError(domain: "CUPSError", code: 12,
                            userInfo: [NSLocalizedDescriptionKey: "Installation failed: \(errorMessage)"])
            }
        }
        
        if let output = result.stringValue {
            log.log("Installation output: \(output)", level: Logger.Level.info)
            
            if output.contains("ERROR:") {
                throw NSError(domain: "CUPSError", code: 16,
                            userInfo: [NSLocalizedDescriptionKey: "Installation failed: \(output)"])
            }
        }
        
        // Verify the installation
        log.log("Verifying printer installation...", level: Logger.Level.info)
        checkPrinterInstallation()
        
        // Double check the installation status
        var verifyDest: UnsafeMutablePointer<cups_dest_t>?
        let verifyCount = cupsGetDests(&verifyDest)
        defer { if verifyDest != nil { cupsFreeDests(verifyCount, verifyDest) } }
        
        let printerFound = (0..<verifyCount).contains { i in
            let printer = verifyDest!.advanced(by: Int(i)).pointee
            let name = String(cString: printer.name)
            return name == self.printerName
        }
        
        if !printerFound {
            throw NSError(domain: "CUPSError", code: 17,
                        userInfo: [NSLocalizedDescriptionKey: "Printer installation verification failed"])
        }
        
        isInstalled = true
        log.log("Printer installation completed successfully", level: Logger.Level.info)
    }
    
    func uninstallPrinter() throws {
        log.log("Starting printer uninstallation...", level: Logger.Level.info)
        
        // Check if CUPS is running
        var dest: UnsafeMutablePointer<cups_dest_t>?
        let destCount = cupsGetDests(&dest)
        defer { if dest != nil { cupsFreeDests(destCount, dest) } }
        
        if destCount == 0 {
            log.log("CUPS service not running", level: Logger.Level.error)
            throw NSError(domain: "CUPSError", code: 9,
                        userInfo: [NSLocalizedDescriptionKey: "CUPS service is not running"])
        }
        
        // Get the path to the uninstallation script
        guard let bundlePath = Bundle.main.resourcePath else {
            log.log("Failed to get bundle resource path", level: Logger.Level.error)
            throw NSError(domain: "CUPSError", code: 11,
                        userInfo: [NSLocalizedDescriptionKey: "Could not locate uninstallation script"])
        }
        
        let scriptName = "uninstall-printer.sh"
        let scriptPath = (bundlePath as NSString).appendingPathComponent(scriptName)
        
        // Verify script exists and is executable
        guard fileManager.fileExists(atPath: scriptPath) else {
            log.log("Uninstallation script not found at path: \(scriptPath)", level: Logger.Level.error)
            throw NSError(domain: "CUPSError", code: 11,
                        userInfo: [NSLocalizedDescriptionKey: "Uninstallation script not found"])
        }
        
        // Verify script is executable
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: scriptPath, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: scriptPath) else {
            log.log("Uninstallation script is not executable at path: \(scriptPath)", level: Logger.Level.error)
            throw NSError(domain: "CUPSError", code: 11,
                        userInfo: [NSLocalizedDescriptionKey: "Uninstallation script is not properly configured"])
        }
        
        log.log("Starting uninstallation with NSAppleScript...", level: Logger.Level.info)
        
        // Improved AppleScript with better error handling and timing
        let scriptSource = """
        on run
            try
                tell application "System Events"
                    activate
                    delay 2.0
                end tell
                
                set scriptPath to "\(scriptPath.replacingOccurrences(of: "\"", with: "\\\""))"
                
                set command to "/usr/bin/sudo " & quoted form of scriptPath
                
                log "Executing command: " & command
                
                set output to do shell script command with administrator privileges
                
                if output contains "ERROR:" then
                    error output
                end if
                
                return output
            on error errMsg
                if errMsg contains "User canceled" then
                    error "Uninstallation cancelled by user"
                else if errMsg contains "not allowed to send keystrokes" then
                    error "Failed to authenticate: System Events not authorized"
                else
                    error errMsg
                end if
            end try
        end run
        """
        
        log.log("AppleScript source prepared", level: Logger.Level.debug)
        log.log("AppleScript source:\n\(scriptSource)", level: Logger.Level.debug)
        
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            throw NSError(domain: "CUPSError", code: 13,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create AppleScript"])
        }
        
        log.log("Executing AppleScript...", level: Logger.Level.info)
        let result = script.executeAndReturnError(&error)
        
        if let error = error {
            log.log("AppleScript error: \(error)", level: Logger.Level.error)
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            if errorMessage.contains("cancelled") || errorMessage.contains("canceled") {
                throw NSError(domain: "CUPSError", code: 14,
                            userInfo: [NSLocalizedDescriptionKey: "Uninstallation cancelled by user"])
            } else if errorMessage.contains("not authorized") {
                throw NSError(domain: "CUPSError", code: 15,
                            userInfo: [NSLocalizedDescriptionKey: "System Events not authorized. Please grant permission in System Settings > Privacy & Security > Accessibility"])
            } else {
                throw NSError(domain: "CUPSError", code: 12,
                            userInfo: [NSLocalizedDescriptionKey: "Uninstallation failed: \(errorMessage)"])
            }
        }
        
        if let output = result.stringValue {
            log.log("Uninstallation output: \(output)", level: Logger.Level.info)
            
            if output.contains("ERROR:") {
                throw NSError(domain: "CUPSError", code: 16,
                            userInfo: [NSLocalizedDescriptionKey: "Uninstallation failed: \(output)"])
            }
        }
        
        isInstalled = false
        log.log("Printer uninstallation completed successfully", level: Logger.Level.info)
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
                    log.log("Error moving PDF: \(error)", level: Logger.Level.error)
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
                        log.log("Error saving PDF: \(error)", level: Logger.Level.error)
                    }
                }
            }
        }
    }
}
