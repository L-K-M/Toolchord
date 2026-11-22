// Generates App/AppIcon.icon, the Icon Composer document for the app icon:
// the menu bar wrench in white over an indigo automatic gradient. Xcode 26+ compiles
// it into the layered Liquid Glass icon and fallbacks for earlier macOS.
//
// Usage: swift Scripts/make-icon.swift
// Preview with Icon Composer’s bundled ictool:
// "$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" \
//          App/AppIcon.icon --export-image --output-file icon.png \
//          --platform macOS --rendition Default --width 512 --height 512 --scale 2
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/AppIcon.icon")
let assets = root.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

// Render the menu bar artwork into a padded layer for the app icon.
let artwork = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/ToolchordMac/Resources/Wrench.svg")
guard let wrench = NSImage(contentsOf: artwork) else { fatalError("Could not load " + artwork.path) }
let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not create bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let glyphSize: CGFloat = 608
let inset = (CGFloat(size) - glyphSize) / 2
wrench.draw(in: NSRect(x: inset, y: inset, width: glyphSize, height: glyphSize))
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
try png.write(to: assets.appendingPathComponent("glyph.png"))

let document = """
{
  "fill" : {
    "automatic-gradient" : "extended-srgb:0.38039,0.37647,0.94118,1.00000"
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : true,
          "image-name" : "glyph.png",
          "name" : "glyph",
          "position" : {
            "scale" : 1,
            "translation-in-points" : [
              0,
              0
            ]
          }
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.4
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

"""
try document.write(to: root.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(root.path)")
