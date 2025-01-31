#!/bin/bash

# This script is called by CUPS-PDF after a PDF is generated
# $1 is the username
# $2 is the job ID
# $3 is the job title
# $4 is the number of copies
# $5 is the options
# $6 is the full path to the PDF file

# Send notification to our app using AppleScript
osascript -e "
tell application \"Otto's Print to PDF\"
    activate
    delay 0.5
    tell application \"System Events\"
        tell process \"Otto's Print to PDF\"
            set frontmost to true
        end tell
    end tell
end tell
" &

# Create a temporary file with the PDF information
echo "{\"path\": \"$6\", \"title\": \"$3\"}" > "/tmp/ottos-pdf-$2.json"

# Trigger our app's URL scheme to handle the PDF
open "ottospdf://handle-pdf?job=$2"

exit 0
