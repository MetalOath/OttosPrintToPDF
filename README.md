# Otto's Print to PDF

A macOS virtual printer that converts any document to PDF with smart save options.

## Features

- Print to PDF from any application
- Automatic or manual save location selection
- Smart file naming with conflict resolution
- Easy installation and uninstallation
- Clean, modern SwiftUI interface
- System-wide CUPS integration

## Requirements

- macOS 12.0 or later
- Xcode 14.0+ (for building)
- Command Line Tools (`xcode-select --install`)
- CUPS development headers (`brew install cups`)

## Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/otto/OttosPrintToPDF.git
   cd OttosPrintToPDF
   ```

2. Clone the reference implementation:
   ```bash
   git clone https://github.com/alexivkin/CUPS-PDF-to-PDF.git reference
   ```

3. Run the build script:
   ```bash
   ./build.sh
   ```

## Installation

1. After building, drag `build/Otto's Print to PDF.app` to your Applications folder
2. Launch the application
3. Click "Install Virtual Printer" when prompted
   - You may need to enter your administrator password
   - The app will install the necessary CUPS backend and configuration

## Usage

### Setting Up

1. Launch "Otto's Print to PDF" from your Applications folder
2. The app will show the current installation status
3. Toggle automatic PDF saving if desired:
   - When enabled: PDFs save to the original document's location
   - When disabled: You'll be prompted for a save location

### Printing to PDF

1. From any application, choose File > Print
2. Select "OttosPDF" from the printer list
3. Click Print
4. Based on your settings:
   - Auto-save enabled: PDF saves automatically
   - Auto-save disabled: Choose where to save the PDF

### Uninstalling

1. Open the application
2. Click "Uninstall Printer"
3. Confirm the uninstallation
4. The app will clean up all associated files and configurations

## How It Works

The application integrates with macOS's CUPS printing system to provide system-wide PDF printing capabilities:

1. Registers a virtual printer using CUPS
2. Intercepts print jobs and converts them to PDF
3. Handles file saving through a native macOS interface
4. Manages printer installation and configuration
5. Provides a user-friendly interface for settings

## Security

The application requires certain permissions:
- System Events access for printer management
- File system access for saving PDFs
- Administrator access for CUPS configuration

All permissions are requested only when needed and are managed through the macOS security system.

## Troubleshooting

### Common Issues

1. Printer not appearing:
   - Ensure the app is running
   - Try reinstalling through the app
   - Check System Preferences > Printers & Scanners

2. PDF save issues:
   - Verify permissions in System Preferences > Security & Privacy
   - Ensure the app has access to save locations
   - Check CUPS error log: `/var/log/cups/error_log`

### Getting Help

If you encounter issues:
1. Check the Console.app for application logs
2. Open an issue on GitHub with:
   - macOS version
   - Steps to reproduce
   - Error messages or logs

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

MIT License - See LICENSE file for details

## Credits

- Based on [CUPS-PDF-to-PDF](https://github.com/alexivkin/CUPS-PDF-to-PDF)
- Built with SwiftUI and CUPS
