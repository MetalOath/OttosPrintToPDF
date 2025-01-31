import Foundation
import AppKit
import UniformTypeIdentifiers

class PrinterManager: ObservableObject {
    static let shared = PrinterManager()
    
    @Published var isAutoSaveEnabled = false
    @Published var isInstalled = false
    
    private let printerName = "OttosPDF"
    private let printerDescription = "Otto's Print to PDF"
    private let spoolDirectory = "/var/spool/cups-pdf/"
    private let configFile = "/etc/cups/cups-pdf.conf"
    
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
        // Create CUPS-PDF configuration
        let configContent = """
        Out ${HOME}/Documents/PDFs
        Label 1
        PostProcessing /usr/local/bin/pdfpostproc.sh
        """
        try configContent.write(to: URL(fileURLWithPath: configFile), atomically: true, encoding: .utf8)
        
        // Copy CUPS backend from reference implementation
        try fileManager.copyItem(at: URL(fileURLWithPath: "reference/cups-pdf"), 
                               to: URL(fileURLWithPath: "/usr/local/lib/cups/backend/cups-pdf"))
        
        // Set permissions
        try fileManager.setAttributes([.posixPermissions: 0o755], 
                                    ofItemAtPath: "/usr/local/lib/cups/backend/cups-pdf")
        
        // Install printer via CUPS
        let request = ippNewRequest(IPP_OP_CUPS_ADD_MODIFY_PRINTER)
        defer { ippDelete(request) }
        
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI,
                    "printer-uri", nil, "ipp://localhost/printers/\(printerName)")
        ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_NAME,
                    "printer-name", nil, printerName)
        ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_URI,
                    "device-uri", nil, "cups-pdf:/")
        ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_TEXT,
                    "printer-info", nil, printerDescription)
        ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_TEXT,
                    "printer-location", nil, "Local PDF Printer")
        
        let http = httpConnect2(cupsServer(), ippPort(), nil, AF_UNSPEC, cupsEncryption(), 1, 30000, nil)
        defer { httpClose(http) }
        
        let response = cupsDoRequest(http, request, "/admin/")
        guard response != nil else {
            throw NSError(domain: "CUPSError", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to add printer"])
        }
        ippDelete(response)
        
        isInstalled = true
    }
    
    func uninstallPrinter() throws {
        let request = ippNewRequest(IPP_OP_CUPS_DELETE_PRINTER)
        defer { ippDelete(request) }
        
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI,
                    "printer-uri", nil, "ipp://localhost/printers/\(printerName)")
        
        let http = httpConnect2(cupsServer(), ippPort(), nil, AF_UNSPEC, cupsEncryption(), 1, 30000, nil)
        defer { httpClose(http) }
        
        let response = cupsDoRequest(http, request, "/admin/")
        guard response != nil else {
            throw NSError(domain: "CUPSError", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to delete printer"])
        }
        ippDelete(response)
        
        // Clean up configuration and backend
        try? fileManager.removeItem(atPath: configFile)
        try? fileManager.removeItem(atPath: "/usr/local/lib/cups/backend/cups-pdf")
        
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
