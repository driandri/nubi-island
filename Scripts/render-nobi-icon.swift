import AppKit
import SwiftUI

@main
@MainActor
struct RenderNobiIcon {
    static func main() throws {
        _ = NSApplication.shared
        let renderer = ImageRenderer(content: NobiAppIcon().frame(width: 1024, height: 1024))
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]),
              let destination = CommandLine.arguments.dropFirst().first else {
            throw NSError(domain: "NobiIcon", code: 1)
        }
        try png.write(to: URL(fileURLWithPath: destination))
    }
}
