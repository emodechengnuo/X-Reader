#!/bin/bash
# X-Reader DMG 安装包制作脚本
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/X-Reader.app"
DMG_TEMP="$SCRIPT_DIR/dmg_temp"
DMG_OUTPUT="$SCRIPT_DIR/../X-Reader-Installer.dmg"
APP_NAME="X-Reader"
VOLUME_NAME="X-Reader"

echo "📦 Creating DMG installer for $APP_NAME..."

# Clean up previous attempts
rm -rf "$DMG_TEMP" "$DMG_OUTPUT"

# Create temp directory for DMG contents
mkdir -p "$DMG_TEMP"

# Copy app
cp -R "$APP_PATH" "$DMG_TEMP/$APP_NAME.app"

# Create Applications symlink (for drag-and-drop install)
ln -s /Applications "$DMG_TEMP/Applications"

# Create a nice background using AppleScript (no external tools needed)
BG_DIR="$DMG_TEMP/.background"
mkdir -p "$BG_DIR"

# Generate a simple but elegant background image with Swift/SIPS
cat > /tmp/gen_dmg_bg.swift << 'SWIFT'
import AppKit

let size = NSSize(width: 560, height: 360)
let image = NSImage(size: size)
image.lockFocus()

// Gradient background
let gradient = NSGradient(starting: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0),
                          ending: NSColor(red: 0.15, green: 0.12, blue: 0.20, alpha: 1.0))
gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 135)

// Subtle decorative elements
NSColor.white.withAlphaComponent(0.03).setFill()
NSBezierPath(ovalIn: NSRect(x: -50, y: -50, width: 300, height: 300)).fill()
NSColor.white.withAlphaComponent(0.02).setFill()
NSBezierPath(ovalIn: NSRect(x: 350, y: 100, width: 250, height: 250)).fill()

// Title text
let titleFont = NSFont.systemFont(ofSize: 28, weight: .bold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor.white
]
let title = "X-Reader"
let titleSize = title.size(withAttributes: titleAttrs)
let titlePoint = NSPoint(
    x: (size.width - titleSize.width) / 2,
    y: size.height - 60
)
title.draw(at: titlePoint, withAttributes: titleAttrs)

// Subtitle
let subFont = NSFont.systemFont(ofSize: 13)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor.white.withAlphaComponent(0.5)
]
let subtitle = "Drag X-Reader to Applications to install"
let subSize = subtitle.size(withAttributes: subAttrs)
subtitle.draw(at: NSPoint(x: (size.width - subSize.width) / 2, y: size.height - 90), withAttributes: subAttrs)

image.unlockFocus()

// Save as TIFF then convert to PNG
let tiffData = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiffData)!
let pngData = bitmap.representation(using: .png, properties: [])!
try! pngData.write(to: URL(fileURLWithPath: "/tmp/dmg_background.png"))
SWIFT

swift /tmp/gen_dmg_bg.swift 2>/dev/null || {
    # Fallback: create a minimal PNG if swift fails
    sips -s format png --resampleWidth 560 "/System/Library/Desktop Pictures/Solid Colors/Black.png" \
        --out "/tmp/dmg_background.png" 2>/dev/null || true
}

cp /tmp/dmg_background.png "$BG_DIR/background.png" 2>/dev/null || true

# Create the DMG
echo "🔨 Building DMG..."
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_OUTPUT" >/dev/null 2>&1

# Customize DMG appearance
echo "✨ Customizing DMG appearance..."

# Attach the DMG read-write temporarily to set up view options
MOUNT_DIR=$(hdiutil attach "$DMG_OUTPUT" -readwrite -noverify -noautoopen 2>/dev/null | grep '/Volumes' | awk '{print $3}')

if [ -n "$MOUNT_DIR" ]; then
    # Set custom icon view with background
    applescript_code="
    tell application \"Finder\"
        tell disk \"$VOLUME_NAME\"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {400, 100, 960, 520}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 120
            set background picture of theViewOptions to file \".background:background.png\"
            
            -- Position items
            set position of item \"$APP_NAME.app\" to {180, 200}
            set position of item \"Applications\" to {380, 200}
            
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
    "

    osascript -e "$applescript_code" 2>/dev/null || echo "⚠️  Could not customize layout (non-critical)"

    # Sync and detach
    sync
    hdiutil detach "$MOUNT_DIR" 2>/dev/null || sleep 2 && hdiutil detach "$MOUNT_DIR" -force 2>/dev/null
fi

# Compress final DMG
echo "🗜️  Compressing final DMG..."
rm -f "${DMG_OUTPUT%.dmg}-final.dmg"
hdiutil convert "$DMG_OUTPUT" -format UDZO -imagekey zlib-level=9 -o "${DMG_OUTPUT%.dmg}-final.dmg" >/dev/null 2>&1
mv "${DMG_OUTPUT%.dmg}-final.dmg" "$DMG_OUTPUT"

# Cleanup temp
rm -rf "$DMG_TEMP" /tmp/gen_dmg_bg.swift /tmp/dmg_background.png

# Get final size
FINAL_SIZE=$(du -sh "$DMG_OUTPUT" | cut -f1)

echo ""
echo "✅ DMG created successfully!"
echo "   📍 Location: $DMG_OUTPUT"
echo "   📏 Size: $FINAL_SIZE"
echo ""
echo "   📋 Installation instructions for your friend:"
echo "      1. Open the .dmg file"
echo "      2. Drag X-Reader to Applications"
echo "      3. Launch from Applications or Launchpad"
echo ""
echo "   🗑️  Uninstall: Just drag X-Reader from Applications to Trash"
echo "      (Kokoro voice models are in ~/Library/Application Support/com.xiaxia.xreader/ if needed)"
