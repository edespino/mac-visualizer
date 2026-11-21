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

/// Track details the translation prompt needs.
public struct TranslationMeta: Equatable {
    public var title: String
    public var artist: String
    /// True when the first input line is the song title, not a lyric.
    public var titleFirst: Bool

    public init(title: String, artist: String, titleFirst: Bool) {
        self.title = title
        self.artist = artist
        self.titleFirst = titleFirst
    }
}

/// Failures a translation provider can report.
public enum TranslationProviderError: Error, Equatable {
    case rateLimited(retryAfterMs: Int?)
    case modelUnavailable(model: String)
    /// The service refused the request outright (HTTP 400/401/403): almost
    /// always a bad API key. Retrying cannot help.
    case rejected(statusCode: Int)
    /// The request never reached the service. Retrying at once cannot help.
    case network
    case other(String)
}

/// A text-generation backend. Returns the model's raw text output for one
/// prompt; `LyricsTranslator` owns the prompt and validates the output.
public protocol TranslationProvider {
    func generate(prompt: String) async throws -> String
}

/// Thrown when translation cannot be completed. Callers must treat this as
/// a hard failure: show no translation and cache nothing. Original text is
/// never passed off as a translation.
public struct TranslationFailed: Error, Equatable {
    public var message: String
    public init(message: String) { self.message = message }
}

/// The translation contract: N lines in, N lines out. Port of the web
/// app's `server/translator.ts` and `server/validate.ts` (lyrics only).
public enum LyricsTranslator {
    /// Chunk size for the fallback path. Big enough that a typical song
    /// needs only a handful of requests, small enough that the model can
    /// hold the exact line count.
    public static let chunkSize = 20
    /// The initial attempt plus this many retries on a rate limit.
    public static let maxRateLimitRetries = 2
    public static let defaultRetryDelayMs = 15_000
    public static let maxRetryDelayMs = 60_000

    public static func buildPrompt(lines: [String], meta: TranslationMeta) -> String {
        var parts = [
            "Translate these Spanish song lyrics to English. The song is \"\(meta.title)\" by \(meta.artist).",
            "Translate idiomatically, preserving tone and meaning, not word for word.",
        ]
        if meta.titleFirst {
            parts.append("The FIRST line of the input is the song title, not a lyric. Translate it as a title.")
        }
        parts += [
            "There are exactly \(lines.count) lines. Output exactly \(lines.count) lines in the same order.",
            "Keep empty lines empty. Do not merge, split, or reorder lines.",
            "Output ONLY a JSON array of strings, one per input line. No other text.",
            "",
            "Lyrics (JSON array):",
            jsonArray(lines),
        ]
        return parts.joined(separator: "\n")
    }

    private static func jsonArray(_ lines: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(lines), let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    /// Parses and validates a provider response: a JSON array of exactly
    /// `expected` strings, raw or wrapped in a markdown code fence.
    public static func parseResponse(_ raw: String, expected: Int) throws -> [String] {
        let text = unwrapJSONFence(raw)
        guard let data = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw TranslationProviderError.other("Provider response is not valid JSON")
        }
        guard let array = parsed as? [Any] else {
            throw TranslationProviderError.other("Provider response is not an array")
        }
        guard array.count == expected else {
            throw TranslationProviderError.other("Expected \(expected) lines, got \(array.count)")
        }
        var out: [String] = []
        out.reserveCapacity(array.count)
        for value in array {
            guard let s = value as? String else {
                throw TranslationProviderError.other("Provider response contains non-string members")
            }
            out.append(s)
        }
        return out
    }

    private static func unwrapJSONFence(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```"), text.hasSuffix("```"), text.count >= 6 else { return text }
        text.removeFirst(3)
        text.removeLast(3)
        if text.hasPrefix("json") { text.removeFirst(4) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Translates `lines` with the song title prepended as the first line
    /// of the batch, so one request covers both. Tries the full batch
    /// twice, then falls back to chunks of `chunkSize`, each still strictly
    /// N-in N-out. Any chunk failure fails the whole translation; there is
    /// never a partial result.
    public static func translateWithTitle(
        provider: TranslationProvider,
        lines: [String],
        meta: TranslationMeta,
        sleep: (Int) async -> Void
    ) async throws -> (titleEn: String, en: [String]) {
        if lines.isEmpty { return ("", []) }

        let batch = [meta.title] + lines
        var titled = meta
        titled.titleFirst = true
        var untitled = meta
        untitled.titleFirst = false

        for _ in 0..<2 {
            if let result = try await callProvider(provider, batch, titled, sleep) {
                return (result[0], Array(result.dropFirst()))
            }
        }

        var out: [String] = []
        var start = 0
        while start < batch.count {
            let chunk = Array(batch[start..<min(start + chunkSize, batch.count)])
            guard let result = try await callProvider(provider, chunk, start == 0 ? titled : untitled, sleep) else {
                throw TranslationFailed(message: "Translation failed for lines \(start + 1) to \(start + chunk.count)")
            }
            out.append(contentsOf: result)
            start += chunkSize
        }
        return (out[0], Array(out.dropFirst()))
    }

    /// One provider call with rate-limit handling. Returns nil on a soft
    /// failure (bad line count, non-rate-limit provider error) so the
    /// caller can fall back. Throws `TranslationFailed` when the rate limit
    /// does not clear within the retry budget (burning more quota on
    /// fallback requests would only make things worse) or the model is
    /// unavailable, the request was rejected, or the network is down (the
    /// last three fail fast with a message that says what to fix).
    private static func callProvider(
        _ provider: TranslationProvider,
        _ lines: [String],
        _ meta: TranslationMeta,
        _ sleep: (Int) async -> Void
    ) async throws -> [String]? {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let raw = try await provider.generate(prompt: buildPrompt(lines: lines, meta: meta))
                return try? parseResponse(raw, expected: lines.count)
            } catch is CancellationError {
                throw CancellationError()
            } catch TranslationProviderError.modelUnavailable(let model) {
                throw TranslationFailed(message:
                    "Gemini model \"\(model)\" is unavailable. Set the Gemini model in Settings to a supported model, for example \(LyricsSettings.defaultGeminiModel).")
            } catch TranslationProviderError.rejected(let statusCode) {
                throw TranslationFailed(message:
                    "Gemini rejected the request (HTTP \(statusCode)). Check the API key and model.")
            } catch TranslationProviderError.network {
                throw TranslationFailed(message: "Could not reach Gemini. Check the network connection.")
            } catch TranslationProviderError.rateLimited(let retryAfterMs) {
                if attempt >= maxRateLimitRetries {
                    throw TranslationFailed(message: "Translation provider rate limit not cleared after retries")
                }
                let delay = retryAfterMs.map { min(max($0, 0), maxRetryDelayMs) } ?? defaultRetryDelayMs * (attempt + 1)
                await sleep(delay)
                attempt += 1
            } catch {
                return nil
            }
        }
    }
}
