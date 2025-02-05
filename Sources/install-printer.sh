#!/bin/bash

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Create CUPS-PDF backend directory if it doesn't exist
mkdir -p /usr/libexec/cups/backend

# Install CUPS-PDF backend
cp "$1/cups-pdf" /usr/libexec/cups/backend/
chown root:wheel /usr/libexec/cups/backend/cups-pdf
chmod 755 /usr/libexec/cups/backend/cups-pdf

# Install PPD file
mkdir -p /usr/share/cups/model
cp "$1/CUPS-PDF.ppd" /usr/share/cups/model/
chown root:wheel /usr/share/cups/model/CUPS-PDF.ppd
chmod 644 /usr/share/cups/model/CUPS-PDF.ppd

# Create output directory
mkdir -p /var/spool/cups-pdf
chmod 755 /var/spool/cups-pdf

# Restart CUPS to recognize new backend
launchctl unload /System/Library/LaunchDaemons/org.cups.cupsd.plist
launchctl load /System/Library/LaunchDaemons/org.cups.cupsd.plist

# Add printer using lpadmin
lpadmin -p "Otto's Print to PDF" \
    -v cups-pdf:/ \
    -P /usr/share/cups/model/CUPS-PDF.ppd \
    -o printer-is-shared=false \
    -E

echo "Virtual PDF printer installed successfully"
