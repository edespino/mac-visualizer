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

/// Language gate for lyrics. Decides whether fetched lyrics are already
/// English so translation can be skipped entirely. Pure stopword and
/// character-frequency heuristic over the full joined lyric text; no
/// network, no library. Port of the web app's `isEnglishLyrics`.
///
/// Deliberately biased: only confidently English text returns true.
/// Anything uncertain or mixed (Spanglish) returns false and is translated.
public enum EnglishLyricsDetector {
    // English evidence must be distinctively English. Tokens that are also
    // common words in other languages are deliberately absent: "i", "on",
    // "in", "do", "a", "no", "me", "la".
    private static let enWords: Set<String> = [
        "the", "you", "and", "to", "of", "it", "is", "my", "your",
        "that", "we", "with", "be", "this", "all", "for", "was", "are",
        "have", "but", "not", "what", "when", "she", "he", "they", "from",
        "know", "like", "just", "never", "now", "got", "get", "want", "will",
        "time", "up", "down", "out", "if", "so", "been", "were", "would",
        "could", "one", "gonna", "wanna", "right", "back", "because", "about",
        "don't", "can't", "i'm", "it's", "you're", "i'll", "won't", "ain't",
    ]

    // Spanish evidence. As with enWords, tokens that are also common in casual
    // English are deliberately absent — "ya" (English "for ya") and "la" (the
    // universal "la la la" vocable) — which otherwise pushed clearly-English pop
    // over the Spanish gate. Genuine Spanish still has ample other markers.
    private static let esWords: Set<String> = [
        "que", "de", "el", "en", "y", "tu", "te", "mi", "es", "un",
        "una", "por", "con", "para", "del", "los", "las", "lo", "como",
        "pero", "mas", "más", "yo", "si", "sí", "esta", "está", "este",
        "cuando", "porque", "quiero", "corazón", "corazon", "amor", "vida",
        "nada", "siempre", "nunca", "todo", "toda", "eres", "estoy", "soy",
        "tengo", "donde", "dónde", "noche", "así", "asi", "aquí", "aqui",
        "muy", "bien", "dime", "hasta", "sin", "entre", "voy", "vas",
        "era", "fue", "hay", "le", "les", "nos", "otra", "otro", "solo",
        "sólo", "también", "tambien", "vez", "quien", "quién", "contigo",
        "conmigo", "tus", "sus", "mis",
    ]

    // Evidence of any other language disqualifies: stopwords from small
    // Portuguese, Italian and French lists.
    private static let otherWords: Set<String> = [
        // Portuguese
        "não", "nao", "você", "voce", "eu", "meu", "minha", "muito", "isso",
        "ela", "ele", "seu", "sua", "coração", "saudade", "então", "obrigado",
        // Italian
        "il", "di", "che", "non", "per", "sono", "mi", "ti", "io", "questo",
        "quando", "amore", "cuore", "sei", "hai", "della", "nel", "perché",
        "più", "anche", "cosa", "voglio",
        // French
        "je", "les", "des", "qui", "pas", "ne", "est", "dans", "pour", "avec",
        "mon", "ma", "mes", "ton", "sur", "suis", "c'est", "j'ai", "moi",
        "toi", "rien", "jamais", "tout", "comme", "quand", "nous", "vous",
        "être", "etre", "veux", "coeur",
    ]

    private static let spanishMarks: Set<Character> = ["á", "é", "í", "ó", "ú", "ü", "ñ", "¿", "¡"]
    // Marks that are specifically Spanish — French, Portuguese and Italian do
    // not use them. (Unlike the shared accents á é í ó ú, common to all of them.)
    private static let uniqueSpanishMarks: Set<Character> = ["ñ", "¿", "¡"]
    private static let otherMarks: Set<Character> = [
        "à", "è", "ì", "ò", "ù", "â", "ê", "î", "ô", "û", "ë", "ï", "ç", "ã", "õ", "œ", "æ", "ß",
    ]
    private static let tokenChars: Set<Character> = {
        var set = Set("abcdefghijklmnopqrstuvwxyz'")
        set.formUnion(["á", "é", "í", "ó", "ú", "ü", "ñ"])
        set.formUnion(otherMarks)
        return set
    }()

    public static func isEnglish(_ text: String) -> Bool {
        let lower = text.lowercased()

        var tokens: [String] = []
        var current = ""
        for ch in lower {
            if tokenChars.contains(ch) {
                current.append(ch)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        if tokens.count < 10 { return false }

        // Foreign evidence is COUNTED, not rejected outright, so an
        // English-dominant song with a non-Spanish section can still read as
        // English (see Path 3). Paths 1 and 2 require zero foreign evidence,
        // preserving the original "any Portuguese/Italian/French word or accent
        // disqualifies" behavior for the confident-English paths.
        var en = 0
        var es = 0
        var other = 0
        var distinctEn = Set<String>()
        for t in tokens {
            if enWords.contains(t) { en += 1; distinctEn.insert(t) }
            if esWords.contains(t) { es += 1 }
            if otherWords.contains(t) { other += 1 }
        }
        let count = Double(tokens.count)
        let enRate = Double(en) / count
        let esRate = Double(es) / count
        // Counted on the original text (lowercase marks only), as the web app does.
        let marks = text.reduce(0) { $0 + (spanishMarks.contains($1) ? 1 : 0) }
        let otherMarkCount = lower.reduce(0) { $0 + (otherMarks.contains($1) ? 1 : 0) }
        let hasUniqueSpanishMark = text.contains { uniqueSpanishMarks.contains($0) }

        // Path 1 — confident English: plenty of English function words, several
        // distinct ones, near-zero Spanish stopwords, at most a stray Spanish
        // accent, and NO Portuguese/Italian/French evidence at all.
        if enRate >= 0.15
            && distinctEn.count >= 5
            && esRate <= 0.02
            && Double(marks) <= count / 200
            && other == 0 && otherMarkCount == 0 {
            return true
        }

        // Path 2 — short/simple English (a repetitive song that can't muster
        // five distinct function words) with ZERO evidence of any other
        // language: no Spanish stopwords or accents, no Portuguese/Italian/French
        // words or accents. Two distinct English function words guard against a
        // single repeated word carrying it.
        if esRate == 0
            && marks == 0
            && other == 0 && otherMarkCount == 0
            && enRate >= 0.15
            && distinctEn.count >= 2 {
            return true
        }

        // Path 3 — an English-dominant song with a NON-Spanish foreign section
        // (a French or Italian refrain/verse, e.g. Talking Heads' "Psycho
        // Killer"). The translator only does Spanish → English, so translating
        // such a song produces nonsense; show it as-is. Gated so a genuinely
        // Spanish song is never skipped: MANY distinct English function words
        // (which a foreign-language song cannot muster), a real English rate,
        // minimal Spanish *stopword* evidence, and none of the uniquely-Spanish
        // marks (ñ ¿ ¡). Shared accents (á é í ó ú) do not block it — they are
        // common to French, Portuguese and Italian, not evidence of Spanish.
        return distinctEn.count >= 10
            && enRate >= 0.10
            && esRate <= 0.03
            && !hasUniqueSpanishMark
    }
}
