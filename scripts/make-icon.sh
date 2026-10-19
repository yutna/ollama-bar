#!/bin/sh
# Regenerates resources/AppIcon.icns (llama glyph on a rounded tile) and
# refreshes the PNG sizes used for docs/screenshots.
#
# Usage: scripts/make-icon.sh
set -eu

cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/render.swift" <<'SWIFT'
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = 1024

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
else { fatalError("could not create bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let radius = CGFloat(size) * 0.2
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
if let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.24, green: 0.28, blue: 0.34, alpha: 1.0),
    NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.14, alpha: 1.0),
]) {
    gradient.draw(in: path, angle: -90)
}

let glyph = "🦙" as NSString
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: CGFloat(size) * 0.60)]
let textSize = glyph.size(withAttributes: attributes)
glyph.draw(
    at: NSPoint(
        x: (CGFloat(size) - textSize.width) / 2,
        y: (CGFloat(size) - textSize.height) / 2 - CGFloat(size) * 0.03),
    withAttributes: attributes)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
SWIFT

swift "$WORK/render.swift" "$WORK/icon-1024.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    doubles=$((s * 2))
    sips -z "$doubles" "$doubles" "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o resources/AppIcon.icns
echo "wrote resources/AppIcon.icns"
