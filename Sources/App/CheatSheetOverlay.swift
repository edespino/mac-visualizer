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
import MacVisualizerCore

/// Keyboard and mouse cheat sheet, toggled with `?`. Purely visual: it must stay
/// non-interactive (`allowsHitTesting(false)`) so it never blocks window drag or the
/// track overlay.
struct CheatSheetOverlay: View {
    let mouseModifier: MouseControlModifier
    /// True while the Spinner style is active; adds the Spinner key group.
    var showsSpinnerKeys: Bool = false
    /// The Spinner's current rotation step (Settings > Spinner > Motion), shown beside the pitch / yaw keys.
    var spinnerStepDegrees: Int = 15

    private var modifierName: String? {
        switch mouseModifier {
        case .off: return nil
        case .shift: return "Shift"
        case .option: return "Option"
        case .command: return "Command"
        }
    }

    private let keys: [(String, String)] = [
        ("h / l", "Previous / next visualization"),
        ("j / k", "Next / previous palette"),
        ("r", "Random visualization"),
        (", / .", "Previous / next song"),
        ("Space", "Play / pause"),
        ("f", "Toggle full screen"),
        ("?", "Show / hide this sheet"),
        ("Esc", "Close this sheet"),
    ]

    private var spinnerKeys: [(String, String)] {
        [
            ("m", "Metal"),
            ("t / Shift+t", "Pitch forward / back (\(spinnerStepDegrees) degree steps, hold to repeat)"),
            ("y / Shift+y", "Yaw right / left (hold to repeat)"),
            ("Option+t / Option+Shift+t", "Yaw right / left (same as y / Shift+y, hold to repeat)"),
            ("0", "Reset orientation; pressed again at face-on, flip to the other side"),
            ("Option+0", "Same, flipping about the vertical axis (RealityKit; the classic shader ignores yaw)"),
            ("Option+drag", "Rotate the disc freely (yaw / pitch)"),
            ("b", "Music mode"),
            ("c", "Hub finish: lit, raised, engraved"),
            ("u", "Hum on / off (the hum is only heard when no music is playing)"),
            ("g", "Classic shader renderer / RealityKit"),
            ("Scroll", "Spin the disc"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shortcuts").font(.headline)
            ForEach(keys, id: \.0) { k in
                HStack(spacing: 12) {
                    Text(k.0).font(.system(.body, design: .monospaced)).frame(width: 64, alignment: .leading)
                    Text(k.1)
                }
            }
            if showsSpinnerKeys {
                Divider().padding(.vertical, 2)
                Text("Spinner").font(.headline)
                ForEach(spinnerKeys, id: \.0) { k in
                    HStack(spacing: 12) {
                        Text(k.0).font(.system(.body, design: .monospaced)).frame(width: 190, alignment: .leading)
                        Text(k.1)
                    }
                }
            }
            Divider().padding(.vertical, 2)
            if let m = modifierName {
                Text("\(m) + click: previous visualization").font(.callout)
                Text("\(m) + right-click: next visualization").font(.callout)
                Text("\(m) + middle-click: random visualization").font(.callout)
                Text("\(m) + scroll: change palette").font(.callout)
            } else {
                Text("Modifier mouse controls are off").font(.callout)
            }
            Text("Right-click: menu    Double-click: full screen").font(.callout)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }
}
