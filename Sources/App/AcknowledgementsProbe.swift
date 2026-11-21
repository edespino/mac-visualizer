//
// Copyright 2026 Ed Espino
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
// implied. See the License for the specific language governing
// permissions and limitations under the License.
//

import SwiftUI
import AppKit

/// `--acknowledgements-probe <outdir>`: renders the Acknowledgements content offscreen, each section in
/// light and dark appearance, at 720x620 and as one tall 720x2400 page, to PNG files.
enum AcknowledgementsProbe {
    static func run(outputDirectory: String) -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let dir = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var ok = true
        for section in AcknowledgementsSection.allCases {
            for dark in [false, true] {
                for (suffix, height) in [("", 620), ("-tall", 2400)] {
                    let name = "ack-\(section.rawValue)-\(dark ? "dark" : "light")\(suffix).png"
                    let wrote = render(section: section, dark: dark, size: CGSize(width: 720, height: CGFloat(height)),
                                       to: dir.appendingPathComponent(name))
                    print(wrote ? "wrote \(name)" : "FAILED \(name)")
                    ok = ok && wrote
                }
            }
        }
        return ok
    }

    private static func render(section: AcknowledgementsSection, dark: Bool, size: CGSize, to url: URL) -> Bool {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: AcknowledgementsView(initialSection: section))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setContentSize(size)
        // Let SwiftUI lay out and the ScrollView populate before capturing.
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        rep.size = size
        var drawn = false
        (appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: rep)
            drawn = true
        }
        guard drawn, let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}
