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

/// Best-effort text decode for a local `.lrc` file. Many lyric files are
/// not UTF-8 (Windows-1252 and Latin-1 are common, especially for accented
/// Spanish), so a strict UTF-8 read would silently skip them. Tries UTF-8
/// first (correct for UTF-8 content), then Windows-1252, then ISO Latin-1,
/// which accepts any byte sequence and so always yields something.
public enum LyricsTextDecoder {
    public static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        return String(data: data, encoding: .isoLatin1)
    }
}
