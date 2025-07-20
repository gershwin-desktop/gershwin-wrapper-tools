#!/usr/local/bin/bash

# Usage: generate-wrapper-code.sh <AppName> <ExecutablePath> <IconPath>
# Example: generate-wrapper-code.sh Chrome /usr/local/bin/chrome /Users/jmaloney/Downloads/chrome.png

if [ $# -ne 3 ]; then
    echo "Usage: $0 <AppName> <ExecutablePath> <IconPath>"
    echo "Example: $0 Chrome /usr/local/bin/chrome /Users/jmaloney/Downloads/chrome.png"
    exit 1
fi

APP_NAME="$1"
EXECUTABLE_PATH="$2"
ICON_PATH="$3"

# Derived values
APP_DIR="./${APP_NAME,,}-app"  # Convert to lowercase and add -app suffix
EXECUTABLE_NAME="${APP_NAME,,}"
SERVICE_NAME="$APP_NAME"
WINDOW_SEARCH_STRING="$APP_NAME"
BUNDLE_ID="org.gnustep.${APP_NAME,,}-wrapper"
ICON_FILENAME="${APP_NAME}.png"
VERSION="3.0.0"

# Template directory (assumes it's in the same directory as this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/Template"

echo "Generating wrapper for $APP_NAME..."
echo "Target directory: $APP_DIR"
echo "Executable: $EXECUTABLE_PATH"
echo "Icon: $ICON_PATH"
echo "Template source: $TEMPLATE_DIR"

# Check if template directory exists
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "Error: Template directory not found at $TEMPLATE_DIR"
    echo "Please ensure the Template directory exists with the following files:"
    echo "  - ApplicationWrapper.h"
    echo "  - ApplicationWrapper.m"
    echo "  - GNUmakefile"
    echo "  - main.m"
    echo "  - LICENSE"
    echo "  - README.md"
    exit 1
fi

# Create target directory
mkdir -p "$APP_DIR"

# Copy all template files except GNUmakefile.preamble
echo "Copying template files..."
for file in "$TEMPLATE_DIR"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        if [ "$filename" != "GNUmakefile.preamble" ]; then
            cp "$file" "$APP_DIR/"
            echo "  Copied: $filename"
        fi
    fi
done

# Copy and rename icon file
if [ -f "$ICON_PATH" ]; then
    echo "Copying icon file..."
    cp "$ICON_PATH" "$APP_DIR/$ICON_FILENAME"
    echo "  Icon copied as: $ICON_FILENAME"
else
    echo "Warning: Icon file $ICON_PATH not found. Creating placeholder."
    touch "$APP_DIR/$ICON_FILENAME"
fi

# Generate custom GNUmakefile.preamble
echo "Generating GNUmakefile.preamble..."
cat > "$APP_DIR/GNUmakefile.preamble" << EOF
APP_NAME = $APP_NAME
EXECUTABLE_NAME = $EXECUTABLE_NAME
EXECUTABLE_PATH = $EXECUTABLE_PATH
SERVICE_NAME = $SERVICE_NAME
WINDOW_SEARCH_STRING = $WINDOW_SEARCH_STRING
BUNDLE_ID = $BUNDLE_ID
ICON_FILE = $ICON_FILENAME
VERSION = $VERSION
EOF

echo ""
echo "Successfully generated $APP_NAME wrapper in $APP_DIR"
echo ""
echo "Generated configuration:"
echo "  APP_NAME = $APP_NAME"
echo "  EXECUTABLE_NAME = $EXECUTABLE_NAME"
echo "  EXECUTABLE_PATH = $EXECUTABLE_PATH"
echo "  SERVICE_NAME = $SERVICE_NAME"
echo "  WINDOW_SEARCH_STRING = $WINDOW_SEARCH_STRING"
echo "  BUNDLE_ID = $BUNDLE_ID"
echo "  ICON_FILE = $ICON_FILENAME"
echo "  VERSION = $VERSION"
echo ""
echo "To build and run:"
echo "  cd $APP_DIR"
echo "  make"
echo "  ./${APP_NAME}.app/${APP_NAME}"
echo ""
echo "Files in $APP_DIR:"
echo "  - GNUmakefile.preamble (generated)"
echo "  - ApplicationWrapper.h (from template)"
echo "  - ApplicationWrapper.m (from template)"
echo "  - GNUmakefile (from template)"
echo "  - main.m (from template)"
echo "  - LICENSE (from template)"
echo "  - README.md (from template)"
echo "  - $ICON_FILENAME (copied from $ICON_PATH)"
