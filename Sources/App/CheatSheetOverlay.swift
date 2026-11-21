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
        ("H / L", "Previous / next visualization"),
        ("J / K", "Next / previous palette"),
        ("R", "Random visualization"),
        (", / .", "Previous / next song"),
        ("Space", "Play / pause"),
        ("F", "Toggle full screen"),
        ("?", "Show / hide this sheet"),
        ("Esc", "Close this sheet"),
    ]

    private var spinnerKeys: [(String, String)] {
        [
            ("M", "Metal"),
            ("T / Shift+T", "Pitch forward / back (\(spinnerStepDegrees) degree steps)"),
            ("Y / Shift+Y", "Yaw right / left (\(spinnerStepDegrees) degree steps)"),
            ("0", "Reset orientation"),
            ("Option+drag", "Rotate the disc freely (yaw / pitch)"),
            ("B", "Music mode"),
            ("C", "Hub finish"),
            ("U", "Hum on / off (the hum is only heard when no music is playing)"),
            ("G", "Classic shader renderer / RealityKit"),
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
                        Text(k.0).font(.system(.body, design: .monospaced)).frame(width: 96, alignment: .leading)
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
