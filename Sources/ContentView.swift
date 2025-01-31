import SwiftUI

struct ContentView: View {
    @StateObject private var printerManager = PrinterManager.shared
    @State private var showingUninstallAlert = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "printer.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Otto's Print to PDF")
                .font(.title)
                .bold()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Status: \(printerManager.isInstalled ? "Installed" : "Not Installed")")
                    .foregroundColor(printerManager.isInstalled ? .green : .red)
                
                Toggle("Auto-save PDFs to original document location", isOn: $printerManager.isAutoSaveEnabled)
                    .disabled(!printerManager.isInstalled)
                
                Text("When enabled, PDFs will be saved automatically to the same folder as the original document.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(radius: 2))
            
            if !printerManager.isInstalled {
                Button(action: installPrinter) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Install Virtual Printer")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(action: { showingUninstallAlert = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Uninstall Printer")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .foregroundColor(.red)
            }
        }
        .frame(width: 400)
        .padding(20)
        .alert("Uninstall Printer", isPresented: $showingUninstallAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall", role: .destructive) {
                uninstallPrinter()
            }
        } message: {
            Text("This will remove the virtual printer and clean up all associated files. Are you sure?")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func installPrinter() {
        do {
            try printerManager.installPrinter()
        } catch {
            errorMessage = "Failed to install printer: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func uninstallPrinter() {
        do {
            try printerManager.uninstallPrinter()
        } catch {
            errorMessage = "Failed to uninstall printer: \(error.localizedDescription)"
            showingError = true
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 400, height: 500)
}
