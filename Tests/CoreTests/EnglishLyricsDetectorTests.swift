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

enum LyricSamples {
    static let english = [
        "I was walking down the road tonight",
        "And you were waiting by the door",
        "All the things we never got to say",
        "Are written on the kitchen floor",
        "But I know that when the morning comes",
        "You will not be there anymore",
        "So I keep on driving through the rain",
        "Just to see your face once more",
    ]
    static let spanish = [
        "Caminaba por la calle esta noche",
        "Y tu esperabas junto a la puerta",
        "Todas las cosas que nunca dijimos",
        "Siguen escritas en el corazón",
        "Pero yo sé que cuando llegue el día",
        "Ya no vas a estar aquí",
        "Sigo manejando bajo la lluvia",
        "Solo para verte una vez más",
    ]
    static let spanglish = [
        "Baby I know que tu me quieres",
        "And I want you here conmigo",
        "Dime why you had to leave me",
        "Porque my heart esta contigo",
        "All the noches que te espero",
        "You know que yo no miento",
        "Come back porque te quiero",
        "Mi amor, you are my sueño",
    ]
    static let portuguese = [
        "Eu caminhava pela rua esta noite",
        "E voce esperava perto da porta",
        "Todas as coisas que nunca dissemos",
        "Ficaram escritas no meu coracao",
        "Mas eu sei que quando chegar o dia",
        "Voce nao vai estar mais aqui",
        "Sigo dirigindo embaixo da chuva",
        "So para ver seu rosto mais uma vez",
    ]
    static let italian = [
        "Camminavo per la strada stanotte",
        "E tu aspettavi vicino alla porta",
        "Tutte le cose che non abbiamo detto",
        "Sono rimaste scritte nel mio cuore",
        "Ma io so che quando arriva il giorno",
        "Tu non sarai piu qui con me",
        "Continuo a guidare sotto la pioggia",
        "Solo per vedere il tuo viso ancora",
    ]
    static let french = [
        "Je marchais dans la rue ce soir",
        "Et tu attendais pres de la porte",
        "Toutes les choses que nous n'avons pas dites",
        "Sont restees ecrites dans mon coeur",
        "Mais je sais que quand le jour viendra",
        "Tu ne seras plus jamais la pour moi",
        "Je continue de rouler sous la pluie",
        "Juste pour voir ton visage encore",
    ]
}

final class EnglishLyricsDetectorTests: XCTestCase {
    private func text(_ lines: [String]) -> String { lines.joined(separator: "\n") }

    func testEnglishIsEnglish() {
        XCTAssertTrue(EnglishLyricsDetector.isEnglish(text(LyricSamples.english)))
    }

    func testSpanishIsNotEnglish() {
        XCTAssertFalse(EnglishLyricsDetector.isEnglish(text(LyricSamples.spanish)))
    }

    func testSpanglishIsNotEnglish() {
        XCTAssertFalse(EnglishLyricsDetector.isEnglish(text(LyricSamples.spanglish)))
    }

    func testPortugueseIsNotEnglish() {
        XCTAssertFalse(EnglishLyricsDetector.isEnglish(text(LyricSamples.portuguese)))
    }

    func testItalianIsNotEnglish() {
        XCTAssertFalse(EnglishLyricsDetector.isEnglish(text(LyricSamples.italian)))
    }

    func testFrenchIsNotEnglish() {
        XCTAssertFalse(EnglishLyricsDetector.isEnglish(text(LyricSamples.french)))
    }

    /// An English song with a short NON-Spanish (here Portuguese) line is still
    /// English. The Spanish-only translator would mangle it, and English
    /// overwhelmingly dominates (many distinct function words). This is the same
    /// reason "Psycho Killer" — English with a French verse — must not translate.
    /// Genuine Spanish still translates: see `testEnglishWithSpanishAccentsIsNotEnglish`
    /// and the Spanish/Spanglish samples, which carry real Spanish evidence.
    func testEnglishWithNonSpanishForeignLineIsEnglish() {
        XCTAssertTrue(EnglishLyricsDetector.isEnglish(text(LyricSamples.english) + "\nnão vou voltar atrás"))
    }

    /// An English-dominant song with a French refrain/verse (the "Psycho Killer"
    /// class) reads as English — the French words ("c'est", "j'ai", "mon") and a
    /// French accent ("soir-là") do not disqualify it; the many distinct English
    /// function words carry it, and there is no uniquely-Spanish mark.
    func testEnglishSongWithFrenchRefrainIsEnglish() {
        let song = """
        i can't tell you what i want but you know that it is not right
        and when they say it is time we will not just let it be
        you have been down this road and i know you want to get out now
        but i can't seem to say what i feel when you are not with me
        qu'est-ce que c'est, c'est la vie
        ce que j'ai fait, ce soir-là, mon ami
        """
        XCTAssertTrue(EnglishLyricsDetector.isEnglish(song))
    }

    func testShortOrEmptyIsNotEnglish() {
        XCTAssertFalse(EnglishLyricsDetector.isEnglish(""))
        XCTAssertFalse(EnglishLyricsDetector.isEnglish("yeah yeah yeah"))
    }

    func testEnglishWithSpanishAccentsIsNotEnglish() {
        let accented = text(LyricSamples.english)
            .replacingOccurrences(of: "road", with: "corazón")
            .replacingOccurrences(of: "door", with: "señorita")
        XCTAssertFalse(EnglishLyricsDetector.isEnglish(accented))
    }

    func testUppercaseEnglishIsEnglish() {
        XCTAssertTrue(EnglishLyricsDetector.isEnglish(text(LyricSamples.english).uppercased()))
    }

    /// Casual English pop that leans on the slang "ya" ("for ya", "do it for
    /// ya") must still read as English. "ya" also means "already/now" in
    /// Spanish; counting it as Spanish evidence pushed esRate over the gate and
    /// misclassified English songs (e.g. Espresso), which then got translated
    /// and shown two-column left instead of a single centered column.
    func testCasualEnglishWithYaSlangIsEnglish() {
        let casual = """
        Now he is thinkin' about me, tell ya, every night
        Is it that sweet? I know ya want it, baby, right
        Say you can't sleep, I got what ya like, so
        That is the way we do it, up and down, ya know
        I can't relate, but they want it, do it for ya
        Too bad they won't stop callin', I know ya need it now
        """
        XCTAssertTrue(EnglishLyricsDetector.isEnglish(casual))
    }

    /// Guard the other side: removing "ya" from the Spanish list must not make
    /// genuine Spanish read as English.
    func testSpanishSampleStillNotEnglishAfterYaRemoval() {
        XCTAssertFalse(EnglishLyricsDetector.isEnglish(text(LyricSamples.spanish)))
    }

    /// English songs lean on the vocable "la la la" (e.g. Brick's "Dazz"). "la"
    /// is the Spanish article but also universal English filler; counting it as
    /// Spanish evidence pushed esRate over the gate and left these songs
    /// misclassified (lyrics shown two-column left instead of centered).
    func testEnglishWithLaLaVocablesIsEnglish() {
        let song = """
        Everybody go on and dance if you want to now
        Music makes your body move, well all right tonight
        Funky dancing, get up, get down, and shake it
        La la la la la la la la la la la la la
        I know you want to move your feet and clap your hands
        Come on and dance with me, you know it feels so right
        """
        XCTAssertTrue(EnglishLyricsDetector.isEnglish(song))
    }

    /// Guard: dropping "la" must not make genuine Spanish read as English.
    func testSpanishSampleStillNotEnglishAfterLaRemoval() {
        XCTAssertFalse(EnglishLyricsDetector.isEnglish(text(LyricSamples.spanish)))
    }

    /// A short, repetitive English song (e.g. The Little Dippers' "Forever") has
    /// few DISTINCT function words but zero foreign evidence — no Spanish words,
    /// no accents, no other-language markers. It must read as English rather than
    /// get a pointless English→English "translation" shown two-column left.
    func testShortSimpleEnglishLoveSongIsEnglish() {
        let song = """
        Hold me, kiss me
        Whisper sweetly
        That you love me forever
        Forever, forever
        Hold me, kiss me
        Say you love me, you and me
        """
        XCTAssertTrue(EnglishLyricsDetector.isEnglish(song))
    }

    /// Guard: the lenient short-text path must still reject short Spanish — any
    /// Spanish stopword or accent keeps it out of English.
    func testShortSpanishIsNotEnglish() {
        XCTAssertFalse(EnglishLyricsDetector.isEnglish("""
        Abrázame, bésame
        Que tú me quieres
        Para siempre, mi amor
        """))
    }
}
