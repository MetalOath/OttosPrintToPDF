#!/bin/bash

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Remove printer
lpadmin -x "Otto's Print to PDF"

# Remove CUPS backend
rm -f /usr/libexec/cups/backend/cups-pdf

# Remove PPD file
rm -f /usr/share/cups/model/CUPS-PDF.ppd

# Restart CUPS
launchctl unload /System/Library/LaunchDaemons/org.cups.cupsd.plist
launchctl load /System/Library/LaunchDaemons/org.cups.cupsd.plist

echo "Virtual PDF printer uninstalled successfully"
