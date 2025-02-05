#!/bin/bash

# Function to log messages with timestamps
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        log_message "✓ $1"
    else
        log_message "✗ ERROR: $1"
        exit 1
    fi
}

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_message "This script must be run as root"
    exit 1
fi

# Verify input directory exists
if [ -z "$1" ] || [ ! -d "$1" ]; then
    log_message "Error: Resources directory not provided or invalid"
    exit 1
fi

# Define paths
BACKEND_DIR="/usr/libexec/cups/backend"
BACKEND_PATH="${BACKEND_DIR}/cups-pdf"
PPD_DIR="/usr/share/cups/model"
PPD_PATH="${PPD_DIR}/CUPS-PDF.ppd"
SPOOL_DIR="/var/spool/cups-pdf"
PRINTER_NAME="Otto's Print to PDF"

# Create CUPS-PDF backend directory if it doesn't exist
log_message "Creating CUPS backend directory..."
mkdir -p "${BACKEND_DIR}"
check_status "Created backend directory"

# Install CUPS-PDF backend
log_message "Installing CUPS backend..."
cp "${1}/cups-pdf" "${BACKEND_PATH}"
chown root:wheel "${BACKEND_PATH}"
chmod 755 "${BACKEND_PATH}"
check_status "Installed CUPS backend"

# Verify backend installation
if [ ! -x "${BACKEND_PATH}" ]; then
    log_message "ERROR: CUPS backend not executable"
    exit 1
fi

# Install PPD file
log_message "Installing PPD file..."
mkdir -p "${PPD_DIR}"
cp "${1}/CUPS-PDF.ppd" "${PPD_PATH}"
chown root:wheel "${PPD_PATH}"
chmod 644 "${PPD_PATH}"
check_status "Installed PPD file"

# Create output directory
log_message "Creating spool directory..."
mkdir -p "${SPOOL_DIR}"
chmod 755 "${SPOOL_DIR}"
check_status "Created spool directory"

# Restart CUPS to recognize new backend
log_message "Restarting CUPS service..."
launchctl unload /System/Library/LaunchDaemons/org.cups.cupsd.plist
launchctl load /System/Library/LaunchDaemons/org.cups.cupsd.plist
check_status "Restarted CUPS service"

# Wait for CUPS to fully restart
sleep 2

# Add printer using lpadmin
log_message "Installing printer..."
lpadmin -p "${PRINTER_NAME}" \
    -v cups-pdf:/ \
    -P "${PPD_PATH}" \
    -o printer-is-shared=false \
    -E
check_status "Added printer"

# Verify installation
log_message "Verifying installation..."
if lpstat -v | grep -q "${PRINTER_NAME}"; then
    log_message "✓ Printer verified and ready to use"
else
    log_message "✗ ERROR: Failed to verify printer installation"
    exit 1
fi

log_message "Virtual PDF printer installation completed successfully"
