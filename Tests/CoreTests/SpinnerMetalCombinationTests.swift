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

import XCTest
@testable import MacVisualizerCore

final class SpinnerMetalCombinationTests: XCTestCase {

    private func decode(_ json: String) throws -> SpinnerSettings {
        try JSONDecoder().decode(SpinnerSettings.self, from: Data(json.utf8))
    }

    // MARK: Plate and boss choices

    func testDefaultsAreSameAsBody() {
        let s = SpinnerSettings()
        XCTAssertEqual(s.plateMetal, .sameAsBody)
        XCTAssertEqual(s.bossMetal, .sameAsBody)
    }

    func testPlateChoiceRawValuesIndicesAndNames() {
        XCTAssertEqual(SpinnerPlateMetal.allCases.count, 6)
        XCTAssertEqual(SpinnerPlateMetal.sameAsBody.rawValue, "sameAsBody")
        XCTAssertEqual(SpinnerPlateMetal.blackZirconium.rawValue, "blackZirconium")
        XCTAssertEqual(SpinnerPlateMetal.allCases.map { $0.index }, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(SpinnerPlateMetal.sameAsBody.displayName, "Same as body")
        XCTAssertEqual(SpinnerPlateMetal.copper.displayName, "Copper")
    }

    func testBossChoiceRawValuesIndicesAndNames() {
        XCTAssertEqual(SpinnerBossMetal.allCases.count, 7)
        XCTAssertEqual(SpinnerBossMetal.sameAsBody.rawValue, "sameAsBody")
        XCTAssertEqual(SpinnerBossMetal.sameAsPlate.rawValue, "sameAsPlate")
        XCTAssertEqual(SpinnerBossMetal.anodizedTitanium.rawValue, "anodizedTitanium")
        XCTAssertEqual(SpinnerBossMetal.allCases.map { $0.index }, [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(SpinnerBossMetal.sameAsPlate.displayName, "Same as plate")
    }

    func testPlateNextCyclesThroughAllSixAndWraps() {
        var c: SpinnerPlateMetal = .sameAsBody
        var seen: [SpinnerPlateMetal] = []
        for _ in 0..<6 { seen.append(c); c = c.next }
        XCTAssertEqual(seen, SpinnerPlateMetal.allCases)
        XCTAssertEqual(c, .sameAsBody)
        XCTAssertEqual(SpinnerPlateMetal.anodizedTitanium.next, .sameAsBody)
        XCTAssertEqual(SpinnerPlateMetal.sameAsBody.next, .steel)
    }

    func testBossNextWraps() {
        XCTAssertEqual(SpinnerBossMetal.sameAsBody.next, .sameAsPlate)
        XCTAssertEqual(SpinnerBossMetal.anodizedTitanium.next, .sameAsBody)
    }

    func testRoundTrip() throws {
        var s = SpinnerSettings()
        s.plateMetal = .brass
        s.bossMetal = .sameAsPlate
        let back = try JSONDecoder().decode(SpinnerSettings.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.plateMetal, .brass)
        XCTAssertEqual(back.bossMetal, .sameAsPlate)
    }

    func testEncodesAsStableStrings() throws {
        var s = SpinnerSettings()
        s.plateMetal = .blackZirconium
        s.bossMetal = .sameAsPlate
        let text: String = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        XCTAssertTrue(text.contains("\"plateMetal\":\"blackZirconium\""))
        XCTAssertTrue(text.contains("\"bossMetal\":\"sameAsPlate\""))
    }

    func testUnknownValuesFallBackToDefault() throws {
        let s = try decode("{\"plateMetal\":\"gold\",\"bossMetal\":\"platinum\"}")
        XCTAssertEqual(s.plateMetal, .sameAsBody)
        XCTAssertEqual(s.bossMetal, .sameAsBody)
    }

    func testLegacyJSONWithoutKeysDecodesToDefaults() throws {
        let s = try decode("{\"metal\":\"copper\"}")
        XCTAssertEqual(s.metal, .copper)
        XCTAssertEqual(s.plateMetal, .sameAsBody)
        XCTAssertEqual(s.bossMetal, .sameAsBody)
    }

    // MARK: Resolvers

    func testPlateResolver() {
        for body in SpinnerMetal.allCases {
            XCTAssertEqual(SpinnerMetalResolver.plate(body: body, plate: .sameAsBody), body)
            XCTAssertEqual(SpinnerMetalResolver.plate(body: body, plate: .brass), .brass)
            XCTAssertEqual(SpinnerMetalResolver.plate(body: body, plate: .steel), .steel)
            XCTAssertEqual(SpinnerMetalResolver.plate(body: body, plate: .copper), .copper)
            XCTAssertEqual(SpinnerMetalResolver.plate(body: body, plate: .blackZirconium), .blackZirconium)
            XCTAssertEqual(SpinnerMetalResolver.plate(body: body, plate: .anodizedTitanium), .anodizedTitanium)
        }
    }

    func testBossResolver() {
        for body in SpinnerMetal.allCases {
            for plate in SpinnerPlateMetal.allCases {
                let resolvedPlate: SpinnerMetal = SpinnerMetalResolver.plate(body: body, plate: plate)
                XCTAssertEqual(SpinnerMetalResolver.boss(body: body, plate: plate, boss: .sameAsBody), body)
                XCTAssertEqual(SpinnerMetalResolver.boss(body: body, plate: plate, boss: .sameAsPlate), resolvedPlate)
                XCTAssertEqual(SpinnerMetalResolver.boss(body: body, plate: plate, boss: .copper), .copper)
                XCTAssertEqual(SpinnerMetalResolver.boss(body: body, plate: plate, boss: .steel), .steel)
                XCTAssertEqual(SpinnerMetalResolver.boss(body: body, plate: plate, boss: .brass), .brass)
                XCTAssertEqual(SpinnerMetalResolver.boss(body: body, plate: plate, boss: .blackZirconium), .blackZirconium)
                XCTAssertEqual(SpinnerMetalResolver.boss(body: body, plate: plate, boss: .anodizedTitanium), .anodizedTitanium)
            }
        }
    }

    func testSettingsEffectiveMetals() {
        var s = SpinnerSettings()
        s.metal = .blackZirconium
        XCTAssertEqual(s.effectivePlateMetal, .blackZirconium)
        XCTAssertEqual(s.effectiveBossMetal, .blackZirconium)
        s.plateMetal = .brass
        XCTAssertEqual(s.effectivePlateMetal, .brass)
        XCTAssertEqual(s.effectiveBossMetal, .blackZirconium)
        s.bossMetal = .sameAsPlate
        XCTAssertEqual(s.effectiveBossMetal, .brass)
        s.bossMetal = .steel
        XCTAssertEqual(s.effectiveBossMetal, .steel)
    }

    // MARK: Favoured combinations

    func testCombinationList() {
        XCTAssertEqual(SpinnerMetalCombination.allCases.map { $0.displayName },
                       ["Matched", "Steel and brass", "Steel and copper", "Black and steel", "Black and brass",
                        "Black and copper", "Titanium and brass"])
    }

    private func settings(_ body: SpinnerMetal, _ plate: SpinnerPlateMetal, _ boss: SpinnerBossMetal) -> SpinnerSettings {
        var s = SpinnerSettings()
        s.metal = body; s.plateMetal = plate; s.bossMetal = boss
        return s
    }

    func testApplyWritesBodyPlateAndBoss() {
        let table: [(SpinnerMetalCombination, SpinnerMetal, SpinnerPlateMetal)] = [
            (.steelAndBrass, .steel, .brass), (.steelAndCopper, .steel, .copper),
            (.blackAndSteel, .blackZirconium, .steel), (.blackAndBrass, .blackZirconium, .brass),
            (.blackAndCopper, .blackZirconium, .copper), (.titaniumAndBrass, .anodizedTitanium, .brass)]
        for (combo, body, plate) in table {
            var s = settings(.copper, .anodizedTitanium, .brass)
            combo.apply(to: &s)
            XCTAssertEqual(s.metal, body, "\(combo)")
            XCTAssertEqual(s.plateMetal, plate, "\(combo)")
            XCTAssertEqual(s.bossMetal, .sameAsBody, "\(combo)")
        }
    }

    func testMatchedKeepsBodyAndResetsPlateAndBoss() {
        var s = settings(.brass, .copper, .steel)
        SpinnerMetalCombination.matched.apply(to: &s)
        XCTAssertEqual(s.metal, .brass)
        XCTAssertEqual(s.plateMetal, .sameAsBody)
        XCTAssertEqual(s.bossMetal, .sameAsBody)
    }

    func testMatchingEveryCombination() {
        XCTAssertEqual(SpinnerMetalCombination.matching(metal: .steel, plateMetal: .brass, bossMetal: .sameAsBody), .steelAndBrass)
        XCTAssertEqual(SpinnerMetalCombination.matching(metal: .steel, plateMetal: .copper, bossMetal: .sameAsBody), .steelAndCopper)
        XCTAssertEqual(SpinnerMetalCombination.matching(metal: .blackZirconium, plateMetal: .steel, bossMetal: .sameAsBody), .blackAndSteel)
        XCTAssertEqual(SpinnerMetalCombination.matching(metal: .blackZirconium, plateMetal: .brass, bossMetal: .sameAsBody), .blackAndBrass)
        XCTAssertEqual(SpinnerMetalCombination.matching(metal: .blackZirconium, plateMetal: .copper, bossMetal: .sameAsBody), .blackAndCopper)
        XCTAssertEqual(SpinnerMetalCombination.matching(metal: .anodizedTitanium, plateMetal: .brass, bossMetal: .sameAsBody), .titaniumAndBrass)
    }

    func testMatchedMatchesEveryBodyMetal() {
        for body in SpinnerMetal.allCases {
            XCTAssertEqual(SpinnerMetalCombination.matching(metal: body, plateMetal: .sameAsBody, bossMetal: .sameAsBody), .matched)
        }
    }

    func testAnyOtherCombinationIsCustom() {
        XCTAssertNil(SpinnerMetalCombination.matching(metal: .copper, plateMetal: .brass, bossMetal: .sameAsBody))
        XCTAssertNil(SpinnerMetalCombination.matching(metal: .steel, plateMetal: .brass, bossMetal: .sameAsPlate))
        XCTAssertNil(SpinnerMetalCombination.matching(metal: .steel, plateMetal: .brass, bossMetal: .copper))
        XCTAssertNil(SpinnerMetalCombination.matching(metal: .steel, plateMetal: .sameAsBody, bossMetal: .brass))
        XCTAssertNil(SpinnerMetalCombination.matching(metal: .steel, plateMetal: .sameAsBody, bossMetal: .sameAsPlate))
        XCTAssertNil(SpinnerMetalCombination.matching(metal: .brass, plateMetal: .steel, bossMetal: .sameAsBody))
    }

    func testApplyThenMatchRoundTrips() {
        for combo in SpinnerMetalCombination.allCases {
            var s = SpinnerSettings()
            combo.apply(to: &s)
            XCTAssertEqual(SpinnerMetalCombination.matching(for: s), combo)
        }
    }
}
