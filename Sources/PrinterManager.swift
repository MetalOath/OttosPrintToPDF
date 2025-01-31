import Foundation
import AppKit
import UniformTypeIdentifiers

class PrinterManager: ObservableObject {
    static let shared = PrinterManager()
    
    @Published var isAutoSaveEnabled = false
    @Published var isInstalled = false
    
    private let printerName = "OttosPDF"
    private let printerDescription = "Otto's Print to PDF"
    private let spoolDirectory = "/private/var/spool/cups-pdf/"
    private let configFile = "/private/etc/cups/cups-pdf.conf"
    private let backendPath = "/usr/local/lib/cups/backend/cups-pdf"
    private let ppdPath = "/usr/local/share/cups/model/CUPS-PDF_opt.ppd"
    private let postProcPath = "/usr/local/bin/pdfpostproc.sh"
    
    private var fileManager = FileManager.default
    private let cupsQueue = DispatchQueue(label: "com.otto.printopdf.cups")
    
    init() {
        checkPrinterInstallation()
    }
    
    private func checkPrinterInstallation() {
        cupsQueue.async {
            var dest: UnsafeMutablePointer<cups_dest_t>?
            let count = cupsGetDests(&dest)
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
        do {
            // Create required directories
            try fileManager.createDirectory(atPath: "/private/var/spool/cups-pdf", withIntermediateDirectories: true, attributes: [.posixPermissions: 0o777])
            try fileManager.createDirectory(atPath: "/usr/local/share/cups/model", withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(atPath: "/usr/local/lib/cups/backend", withIntermediateDirectories: true, attributes: nil)
            
            // Create CUPS-PDF configuration
            let configContent = """
            Out ${HOME}/Documents/PDFs
            Label 1
            PostProcessing \(postProcPath)
            """
            
            try configContent.write(to: URL(fileURLWithPath: configFile), atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configFile)
            
            // Copy CUPS backend
            if let backendData = try? Data(contentsOf: URL(fileURLWithPath: "reference/cups-pdf")) {
                try backendData.write(to: URL(fileURLWithPath: backendPath))
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: backendPath)
            } else {
                throw NSError(domain: "CUPSError", code: 5,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to install backend"])
            }
            
            // Copy PPD file
            if let ppdData = try? Data(contentsOf: URL(fileURLWithPath: "reference/CUPS-PDF_opt.ppd")) {
                try ppdData.write(to: URL(fileURLWithPath: ppdPath))
                try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ppdPath)
            } else {
                throw NSError(domain: "CUPSError", code: 6,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to install PPD file"])
            }
            
            // Copy post-processing script
            if let scriptData = try? Data(contentsOf: URL(fileURLWithPath: "Sources/pdfpostproc.sh")) {
                try scriptData.write(to: URL(fileURLWithPath: postProcPath))
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: postProcPath)
            } else {
                throw NSError(domain: "CUPSError", code: 7,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to install post-processing script"])
            }
        } catch {
            throw NSError(domain: "CUPSError", code: 8,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to set up printer files: \(error.localizedDescription)"])
        }
        
        // Install printer using CUPS API
        var numOptions: Int32 = 0
        var options: UnsafeMutablePointer<cups_option_t>? = nil
        
        // Add printer options
        withUnsafeMutablePointer(to: &numOptions) { numPtr in
            _ = cupsAddOption("device-uri", "cups-pdf:/", numPtr, &options)
            _ = cupsAddOption("printer-is-accepting-jobs", "true", numPtr, &options)
            _ = cupsAddOption("printer-state", "3", numPtr, &options)
            _ = cupsAddOption("printer-location", "Local PDF Printer", numPtr, &options)
            _ = cupsAddOption("printer-info", printerDescription, numPtr, &options)
        }
        
        defer {
            if numOptions > 0 {
                cupsFreeOptions(numOptions, options)
            }
        }
        
        // Add the printer
        let result = cupsPrinterAdd(printerName, ppdPath)
        if result == 0 {
            let error = String(cString: cupsLastErrorString())
            throw NSError(domain: "CUPSError", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to add printer: \(error)"])
        }
        
        // Set printer options
        let optResult = cupsSetOptions(numOptions, options, printerName)
        if optResult == 0 {
            let error = String(cString: cupsLastErrorString())
            throw NSError(domain: "CUPSError", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to set printer options: \(error)"])
        }
        
        // Set as default printer
        _ = cupsSetDefaultPrinter(printerName)
        
        isInstalled = true
    }
    
    func uninstallPrinter() throws {
        // Delete printer using CUPS API
        let result = cupsPrinterDelete(printerName)
        if result == 0 {
            let error = String(cString: cupsLastErrorString())
            throw NSError(domain: "CUPSError", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to delete printer: \(error)"])
        }
        
        // Clean up configuration and backend (we have entitlements for this)
        // Clean up all installed components
        try? fileManager.removeItem(atPath: configFile)
        try? fileManager.removeItem(atPath: backendPath)
        try? fileManager.removeItem(atPath: ppdPath)
        try? fileManager.removeItem(atPath: postProcPath)
        
        isInstalled = false
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
