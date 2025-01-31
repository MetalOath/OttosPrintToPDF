#!/bin/bash
set -e

# Configuration
APP_NAME="Otto's Print to PDF"
BUNDLE_ID="com.otto.printopdf"
VERSION="1.0"

# Ensure we're in the correct directory
cd "$(dirname "$0")"

echo "Building Otto's Print to PDF..."

# 1. Build CUPS backend
echo "Building CUPS backend..."
cd reference
gcc -O9 -s -o cups-pdf cups-pdf.c -lcups
cd ..

# 2. Create app bundle structure
echo "Creating app bundle..."
BUNDLE_ROOT="build/$APP_NAME.app"
CONTENTS="$BUNDLE_ROOT/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# 3. Build Swift application
echo "Building Swift application..."
xcodebuild -scheme OttosPrintToPDF -configuration Release

# 4. Copy files into bundle
echo "Assembling application bundle..."
cp -r "build/Release/OttosPrintToPDF.app/"* "$BUNDLE_ROOT/"

# 5. Copy CUPS backend and configuration
echo "Installing CUPS components..."
sudo mkdir -p "/usr/local/lib/cups/backend"
sudo cp "reference/cups-pdf" "/usr/local/lib/cups/backend/"
sudo chmod 755 "/usr/local/lib/cups/backend/cups-pdf"

# Copy PPD file
sudo mkdir -p "/usr/local/share/cups/model"
sudo cp "reference/CUPS-PDF_opt.ppd" "/usr/local/share/cups/model/"

# 6. Install post-processing script
echo "Installing post-processing script..."
sudo cp "Sources/pdfpostproc.sh" "/usr/local/bin/"
sudo chmod 755 "/usr/local/bin/pdfpostproc.sh"

# 7. Create CUPS configuration directory
sudo mkdir -p "/etc/cups"
sudo chown root:admin "/etc/cups"
sudo chmod 775 "/etc/cups"

echo "Build complete!"
echo "You can now find the application in: build/$APP_NAME.app"
echo ""
echo "Installation Instructions:"
echo "1. Drag '$APP_NAME.app' to your Applications folder"
echo "2. Launch the application"
echo "3. Click 'Install Virtual Printer' when prompted"
echo ""
echo "The virtual printer will be available in all applications' print dialogs."
