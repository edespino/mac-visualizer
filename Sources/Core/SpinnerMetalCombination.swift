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

// Separate metals for the Tri-wing's wing plates and bosses, the resolvers that turn the three persisted choices into
// effective metals, and the named "favoured combinations" (nothing extra is persisted: a combination is recognised from
// the body, plate and boss settings, and no match reads as Custom).

/// Metal of the three wing plates: follow the body, or one of the five metals.
public enum SpinnerPlateMetal: String, Codable, CaseIterable {
    case sameAsBody, steel, brass, copper, blackZirconium, anodizedTitanium

    /// Probe index: 0 same as body, 1 steel ... 5 titanium. Not persisted.
    public var index: Int { SpinnerPlateMetal.allCases.firstIndex(of: self) ?? 0 }

    /// The fixed metal, or nil when the plates follow the body.
    public var fixedMetal: SpinnerMetal? {
        switch self {
        case .sameAsBody: return nil
        case .steel: return .steel
        case .brass: return .brass
        case .copper: return .copper
        case .blackZirconium: return .blackZirconium
        case .anodizedTitanium: return .anodizedTitanium
        }
    }

    public var displayName: String {
        if let m = fixedMetal { return m.displayName }
        return "Same as body"
    }

    /// The next choice, wrapping after the last.
    public var next: SpinnerPlateMetal {
        let all = SpinnerPlateMetal.allCases
        let i: Int = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

/// Metal of the three bosses (the round pedestals under the jewel settings): follow the body, follow the plate, or one
/// of the five metals.
public enum SpinnerBossMetal: String, Codable, CaseIterable {
    case sameAsBody, sameAsPlate, steel, brass, copper, blackZirconium, anodizedTitanium

    /// Probe index: 0 same as body, 1 same as plate, 2 steel ... 6 titanium. Not persisted.
    public var index: Int { SpinnerBossMetal.allCases.firstIndex(of: self) ?? 0 }

    public var fixedMetal: SpinnerMetal? {
        switch self {
        case .sameAsBody, .sameAsPlate: return nil
        case .steel: return .steel
        case .brass: return .brass
        case .copper: return .copper
        case .blackZirconium: return .blackZirconium
        case .anodizedTitanium: return .anodizedTitanium
        }
    }

    public var displayName: String {
        switch self {
        case .sameAsBody: return "Same as body"
        case .sameAsPlate: return "Same as plate"
        default: return fixedMetal?.displayName ?? ""
        }
    }

    public var next: SpinnerBossMetal {
        let all = SpinnerBossMetal.allCases
        let i: Int = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

/// Effective plate and boss metals from the body, plate and boss settings.
public enum SpinnerMetalResolver {
    public static func plate(body: SpinnerMetal, plate: SpinnerPlateMetal) -> SpinnerMetal {
        return plate.fixedMetal ?? body
    }

    public static func boss(body: SpinnerMetal, plate: SpinnerPlateMetal, boss: SpinnerBossMetal) -> SpinnerMetal {
        if let m = boss.fixedMetal { return m }
        if boss == .sameAsPlate { return Self.plate(body: body, plate: plate) }
        return body
    }
}

extension SpinnerSettings {
    /// The metal the three wing plates are drawn in.
    public var effectivePlateMetal: SpinnerMetal {
        SpinnerMetalResolver.plate(body: metal, plate: plateMetal)
    }

    /// The metal the three bosses are drawn in.
    public var effectiveBossMetal: SpinnerMetal {
        SpinnerMetalResolver.boss(body: metal, plate: plateMetal, boss: bossMetal)
    }
}

/// A named body / plate / boss combination. Every one leaves the boss following the body.
public enum SpinnerMetalCombination: String, CaseIterable {
    case matched, steelAndBrass, steelAndCopper, blackAndSteel, blackAndBrass, blackAndCopper, titaniumAndBrass

    public var displayName: String {
        switch self {
        case .matched: return "Matched"
        case .steelAndBrass: return "Steel and brass"
        case .steelAndCopper: return "Steel and copper"
        case .blackAndSteel: return "Black and steel"
        case .blackAndBrass: return "Black and brass"
        case .blackAndCopper: return "Black and copper"
        case .titaniumAndBrass: return "Titanium and brass"
        }
    }

    /// The body metal the combination sets (nil: the body is left as it is) and the plate choice it sets.
    var body: SpinnerMetal? {
        switch self {
        case .matched: return nil
        case .steelAndBrass, .steelAndCopper: return .steel
        case .blackAndSteel, .blackAndBrass, .blackAndCopper: return .blackZirconium
        case .titaniumAndBrass: return .anodizedTitanium
        }
    }

    var plate: SpinnerPlateMetal {
        switch self {
        case .matched: return .sameAsBody
        case .steelAndBrass, .blackAndBrass, .titaniumAndBrass: return .brass
        case .steelAndCopper, .blackAndCopper: return .copper
        case .blackAndSteel: return .steel
        }
    }

    /// Writes the combination's body (when it names one), plate and boss.
    public func apply(to settings: inout SpinnerSettings) {
        if let b = body { settings.metal = b }
        settings.plateMetal = plate
        settings.bossMetal = .sameAsBody
    }

    /// The combination the three settings spell out, or nil (Custom).
    public static func matching(metal: SpinnerMetal, plateMetal: SpinnerPlateMetal, bossMetal: SpinnerBossMetal) -> SpinnerMetalCombination? {
        for c in SpinnerMetalCombination.allCases {
            if c.plate == plateMetal && bossMetal == .sameAsBody && (c.body == nil || c.body == metal) { return c }
        }
        return nil
    }

    public static func matching(for settings: SpinnerSettings) -> SpinnerMetalCombination? {
        matching(metal: settings.metal, plateMetal: settings.plateMetal, bossMetal: settings.bossMetal)
    }
}
