import SwiftUI

@main
struct OttosPrintToPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, maxWidth: 400, minHeight: 500, maxHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }  // Disable New menu item
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register defaults
        UserDefaults.standard.register(defaults: [
            "AutoSaveEnabled": false
        ])
        
        // Set up menu bar
        setupMenuBar()
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first,
              url.scheme == "ottospdf",
              url.host == "handle-pdf",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let jobIdItem = components.queryItems?.first(where: { $0.name == "job" }),
              let jobId = jobIdItem.value else {
            return
        }
        
        // Read the temporary file with PDF information
        let tempFile = "/tmp/ottos-pdf-\(jobId).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: tempFile)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let pdfPath = json["path"] else {
            return
        }
        
        // Clean up temp file
        try? FileManager.default.removeItem(atPath: tempFile)
        
        // Handle the PDF
        PrinterManager.shared.handleNewPDF(at: pdfPath)
    }
    
    private func setupMenuBar() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu
        
        // Application menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(withTitle: "About Otto's Print to PDF",
                       action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                       keyEquivalent: "")
        
        appMenu.addItem(NSMenuItem.separator())
        
        appMenu.addItem(withTitle: "Preferences...",
                       action: nil,
                       keyEquivalent: ",")
        
        appMenu.addItem(NSMenuItem.separator())
        
        appMenu.addItem(withTitle: "Hide Otto's Print to PDF",
                       action: #selector(NSApplication.hide(_:)),
                       keyEquivalent: "h")
        
        let hideOthersMenuItem = NSMenuItem(title: "Hide Others",
                                          action: #selector(NSApplication.hideOtherApplications(_:)),
                                          keyEquivalent: "h")
        hideOthersMenuItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersMenuItem)
        
        appMenu.addItem(withTitle: "Show All",
                       action: #selector(NSApplication.unhideAllApplications(_:)),
                       keyEquivalent: "")
        
        appMenu.addItem(NSMenuItem.separator())
        
        appMenu.addItem(withTitle: "Quit Otto's Print to PDF",
                       action: #selector(NSApplication.terminate(_:)),
                       keyEquivalent: "q")
        
        // Edit menu (for copy/paste in text fields)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(withTitle: "Cut",
                        action: #selector(NSText.cut(_:)),
                        keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",
                        action: #selector(NSText.copy(_:)),
                        keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",
                        action: #selector(NSText.paste(_:)),
                        keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                        action: #selector(NSText.selectAll(_:)),
                        keyEquivalent: "a")
        
        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        
        windowMenu.addItem(withTitle: "Minimize",
                          action: #selector(NSWindow.miniaturize(_:)),
                          keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                          action: #selector(NSWindow.zoom(_:)),
                          keyEquivalent: "")
        
        NSApp.windowsMenu = windowMenu
    }
}
