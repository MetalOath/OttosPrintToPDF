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

# Define paths
PRINTER_NAME="Otto's Print to PDF"
BACKEND_PATH="/usr/libexec/cups/backend/cups-pdf"
PPD_PATH="/usr/share/cups/model/CUPS-PDF.ppd"

# Remove printer
log_message "Removing printer..."
lpadmin -x "${PRINTER_NAME}"

# Verify printer removal
if lpstat -v | grep -q "${PRINTER_NAME}"; then
    log_message "Failed to remove printer"
    exit 1
fi
check_status "Printer removed"

# Remove CUPS backend
log_message "Removing CUPS backend..."
if [ -f "${BACKEND_PATH}" ]; then
    rm -f "${BACKEND_PATH}"
    check_status "CUPS backend removed"
else
    log_message "CUPS backend not found"
fi

# Remove PPD file
log_message "Removing PPD file..."
if [ -f "${PPD_PATH}" ]; then
    rm -f "${PPD_PATH}"
    check_status "PPD file removed"
else
    log_message "PPD file not found"
fi

# Restart CUPS
log_message "Restarting CUPS service..."
launchctl unload /System/Library/LaunchDaemons/org.cups.cupsd.plist
launchctl load /System/Library/LaunchDaemons/org.cups.cupsd.plist
check_status "CUPS service restarted"

log_message "Virtual PDF printer uninstalled successfully"
