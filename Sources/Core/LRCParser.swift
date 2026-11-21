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

/// LRC lyric parser. Port of the web app's `parseLrc`.
public enum LRCParser {
    /// Parses LRC text into lines sorted by time. Lines without a valid
    /// leading timestamp (metadata tags, garbage) are skipped. A line may
    /// carry several leading timestamps; it is emitted once per timestamp.
    /// Empty-text lines are kept.
    public static func parse(_ lrc: String) -> [LyricLine] {
        var out: [LyricLine] = []
        // split(whereSeparator:) on Character treats "\r\n" as one newline grapheme.
        for line in lrc.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let raw = Array(line.drop(while: { $0 == " " || $0 == "\t" }))
            var times: [Int] = []
            var index = 0
            var valid = true
            while let (ms, next) = timestamp(in: raw, at: index) {
                guard let ms else { valid = false; break }
                times.append(ms)
                index = next
            }
            if !valid || times.isEmpty { continue }
            let text = String(raw[index...]).trimmingCharacters(in: .whitespaces)
            for t in times { out.append(LyricLine(timeMs: t, text: text)) }
        }
        // Stable sort by time.
        return out.enumerated()
            .sorted { $0.element.timeMs != $1.element.timeMs ? $0.element.timeMs < $1.element.timeMs : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Matches `[m+:s{1,2}]` with an optional `.` or `:` plus 1 to 3 digit
    /// fraction starting exactly at `start`. Returns nil when there is no
    /// timestamp there; returns `(nil, _)` when the timestamp matches but
    /// its seconds are 60 or more (which invalidates the whole line).
    private static func timestamp(in chars: [Character], at start: Int) -> (Int?, Int)? {
        var i = start
        guard i < chars.count, chars[i] == "[" else { return nil }
        i += 1
        func digits(max: Int) -> String {
            var s = ""
            while i < chars.count, s.count < max, chars[i].isASCII, chars[i].isNumber {
                s.append(chars[i]); i += 1
            }
            return s
        }
        let minutes = digits(max: 9)
        guard !minutes.isEmpty, i < chars.count, chars[i] == ":" else { return nil }
        i += 1
        let seconds = digits(max: 2)
        guard !seconds.isEmpty else { return nil }
        var frac = ""
        if i < chars.count, chars[i] == "." || chars[i] == ":" {
            let save = i
            i += 1
            frac = digits(max: 3)
            if frac.isEmpty { i = save }
        }
        guard i < chars.count, chars[i] == "]" else { return nil }
        i += 1
        guard let m = Int(minutes), let s = Int(seconds) else { return nil }
        if s >= 60 { return (nil, i) }
        let fracMs: Int
        switch frac.count {
        case 0: fracMs = 0
        case 1: fracMs = Int(frac)! * 100
        case 2: fracMs = Int(frac)! * 10
        default: fracMs = Int(frac)!
        }
        return (m * 60000 + s * 1000 + fracMs, i)
    }
}

/// Index of the last line whose timestamp is at or before `positionMs`,
/// or -1 when the position is before the first line.
public func findActiveLine(_ lines: [LyricLine], positionMs: Int) -> Int {
    var lo = 0
    var hi = lines.count - 1
    var result = -1
    while lo <= hi {
        let mid = (lo + hi) / 2
        if lines[mid].timeMs <= positionMs {
            result = mid
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    return result
}
