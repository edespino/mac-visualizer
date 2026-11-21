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

import Foundation

/// Picks the `.lrc` file in a local folder that names the playing track.
/// Pure matching only (no file I/O): the folder listing is passed in.
public enum LocalLyricsMatcher {
    /// The `.lrc` filename best matching the track, or nil. A file matches
    /// when its name (minus extension) normalizes equal to one of, in
    /// priority order, "<artist> <title>", "<title> <artist>", or "<title>"
    /// alone. Normalization lowercases, folds diacritics, and reduces every
    /// run of non-alphanumerics to a single space, so "Gilberto Santa Rosa
    /// - Conteo Regresivo.lrc" matches artist "Gilberto Santa Rosa", title
    /// "Conteo Regresivo".
    public static func match(filenames: [String], title: String, artist: String) -> String? {
        let candidates = [
            normalize(artist + " " + title),
            normalize(title + " " + artist),
            normalize(title),
        ].filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return nil }

        let lrc = filenames
            .filter { $0.lowercased().hasSuffix(".lrc") }
            .sorted()
            .map { (name: $0, key: normalize(stem($0))) }

        for candidate in candidates {
            if let hit = lrc.first(where: { $0.key == candidate }) { return hit.name }
        }
        return nil
    }

    /// Lowercased, accent-folded, with every run of non-alphanumeric
    /// characters collapsed to one space and the ends trimmed.
    static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var tokens: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens.joined(separator: " ")
    }

    private static func stem(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension
    }
}
