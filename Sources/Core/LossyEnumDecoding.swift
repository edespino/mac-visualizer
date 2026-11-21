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

/// Decodes (and discards) any single JSON value — scalar, array, or object.
/// Used to consume a malformed element from an unkeyed container so the
/// container's index advances past it (a failed `decode` does NOT advance,
/// which would otherwise loop forever) while the surrounding lossy decode
/// keeps going.
struct JSONFragment: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { return }
        if (try? c.decode(Bool.self)) != nil { return }
        if (try? c.decode(Double.self)) != nil { return }
        if (try? c.decode(String.self)) != nil { return }
        if (try? c.decode([JSONFragment].self)) != nil { return }
        if (try? c.decode([String: JSONFragment].self)) != nil { return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unconsumable JSON value")
    }
}

extension KeyedDecodingContainer {
    /// Lossy enum decode for the tolerant settings decoders: a missing key or
    /// an unknown raw value OF THE EXPECTED TYPE (e.g. a case written by a
    /// newer app version) yields `fallback`. Plain
    /// `decodeIfPresent(Enum.self, ...)` only tolerates a *missing* key — an
    /// unrecognized raw value throws and would fail the entire settings load.
    ///
    /// Deliberately NOT lossier than that: a wrong-typed value (a number where
    /// a string raw value belongs) is structural corruption and RETHROWS, so
    /// `VisualizerSettings.load` still takes its corrupt-file backup path
    /// instead of silently defaulting — a later save would otherwise overwrite
    /// the corrupt file and destroy the evidence.
    func decodeLossyEnum<T>(_ type: T.Type, forKey key: Key, default fallback: T) throws -> T
        where T: RawRepresentable & Decodable, T.RawValue: Decodable {
        guard let raw = try decodeIfPresent(T.RawValue.self, forKey: key) else {
            return fallback
        }
        return T(rawValue: raw) ?? fallback
    }
}
