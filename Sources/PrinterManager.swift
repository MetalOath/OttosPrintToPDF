import Foundation
import CUPS
import AppKit

class PrinterManager: ObservableObject {
    static let shared = PrinterManager()
    
    @Published var isAutoSaveEnabled = false
    @Published var isInstalled = false
    
    private let printerName = "OttosPDF"
    private let printerDescription = "Otto's Print to PDF"
    private let spoolDirectory = "/var/spool/cups-pdf/"
    private let configFile = "/etc/cups/cups-pdf.conf"
    
    private var fileManager = FileManager.default
    
    init() {
        checkPrinterInstallation()
    }
    
    private func checkPrinterInstallation() {
        do {
            let printers = try cupsGetPrinters()
            isInstalled = printers.contains(where: { $0.name == printerName })
        } catch {
            print("Error checking printer installation: \(error)")
            isInstalled = false
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
                               to: URL(fileURLWithPath: "/usr/lib/cups/backend/cups-pdf"))
        
        // Set permissions
        try fileManager.setAttributes([.posixPermissions: 0o755], 
                                    ofItemAtPath: "/usr/lib/cups/backend/cups-pdf")
        
        // Install printer via CUPS
        let conn = try CUPSConnection()
        try conn.addPrinter(
            name: printerName,
            uri: "cups-pdf:/",
            ppdFile: "/System/Library/Frameworks/CUPS.framework/PPDs/Generic.ppd",
            info: printerDescription,
            location: "Local PDF Printer"
        )
        
        isInstalled = true
    }
    
    func uninstallPrinter() throws {
        // Remove printer from CUPS
        let conn = try CUPSConnection()
        try conn.deletePrinter(name: printerName)
        
        // Clean up configuration and backend
        try? fileManager.removeItem(atPath: configFile)
        try? fileManager.removeItem(atPath: "/usr/lib/cups/backend/cups-pdf")
        
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
            savePanel.allowedContentTypes = [UTType.pdf]
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

// CUPS Connection Helper
struct CUPSConnection {
    private var http: UnsafeMutablePointer<http_t>?
    
    init() throws {
        http = httpConnect2(cupsServer(), ippPort(), nil, AF_UNSPEC,
                          cupsEncryption(), 1, 30000, nil)
        guard http != nil else {
            throw NSError(domain: "CUPSError", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to connect to CUPS server"])
        }
    }
    
    func addPrinter(name: String, uri: String, ppdFile: String,
                   info: String, location: String) throws {
        var request = ippNewRequest(IPP_OP_CUPS_ADD_MODIFY_PRINTER)
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI,
                    "printer-uri", nil, "ipp://localhost/printers/\(name)")
        ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_NAME,
                    "printer-name", nil, name)
        ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_URI,
                    "device-uri", nil, uri)
        ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_TEXT,
                    "printer-info", nil, info)
        ippAddString(request, IPP_TAG_PRINTER, IPP_TAG_TEXT,
                    "printer-location", nil, location)
        
        var response = cupsDoRequest(http, request, "/admin/")
        guard response != nil else {
            throw NSError(domain: "CUPSError", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to add printer"])
        }
        ippDelete(response)
    }
    
    func deletePrinter(name: String) throws {
        var request = ippNewRequest(IPP_OP_CUPS_DELETE_PRINTER)
        ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI,
                    "printer-uri", nil, "ipp://localhost/printers/\(name)")
        
        var response = cupsDoRequest(http, request, "/admin/")
        guard response != nil else {
            throw NSError(domain: "CUPSError", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to delete printer"])
        }
        ippDelete(response)
    }
    
    func cupsGetPrinters() throws -> [(name: String, uri: String)] {
        var request = ippNewRequest(IPP_OP_CUPS_GET_PRINTERS)
        var response = cupsDoRequest(http, request, "/admin/")
        guard response != nil else {
            throw NSError(domain: "CUPSError", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to get printers"])
        }
        defer { ippDelete(response) }
        
        var printers: [(name: String, uri: String)] = []
        var attr: UnsafeMutablePointer<ipp_attribute_t>?
        
        while let printer = ippNextAttribute(response) {
            if ippGetName(printer) == "printer-name" {
                let name = String(cString: ippGetString(printer, 0, nil))
                attr = ippFindAttribute(response, "device-uri", IPP_TAG_URI)
                if let uri = attr.map({ String(cString: ippGetString($0, 0, nil)) }) {
                    printers.append((name: name, uri: uri))
                }
            }
        }
        
        return printers
    }
}
