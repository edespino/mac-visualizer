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

/// Pure request building and response parsing for the Gemini REST
/// `models.generateContent` method. No networking here, so it is unit
/// tested; `GeminiProvider` (Services) sends the request.
///
/// Shape checked against Google's API reference on 2026-11-11:
/// `POST /v1beta/models/{model}:generateContent` on
/// generativelanguage.googleapis.com, key in the `x-goog-api-key` header,
/// `responseMimeType` in the generation config, output text under
/// candidates -> content -> parts -> text.
public enum GeminiAPI {
    static let host = "https://generativelanguage.googleapis.com"

    public static func makeRequest(apiKey: String, model: String, prompt: String) throws -> URLRequest {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        guard !model.isEmpty, model.unicodeScalars.allSatisfy(allowed.contains),
              let url = URL(string: "\(host)/v1beta/models/\(model):generateContent") else {
            throw TranslationProviderError.other("Invalid Gemini model name")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["responseMimeType": "application/json"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Returns the generated text from a response, or throws a
    /// `TranslationProviderError` describing the failure.
    public static func parse(data: Data, statusCode: Int, model: String) throws -> String {
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(statusCode) else {
            if statusCode == 429 {
                throw TranslationProviderError.rateLimited(retryAfterMs: retryDelayMs(fromErrorBody: bodyText))
            }
            if statusCode == 404, isModelUnavailable(bodyText) {
                throw TranslationProviderError.modelUnavailable(model: model)
            }
            if [400, 401, 403].contains(statusCode) {
                throw TranslationProviderError.rejected(statusCode: statusCode)
            }
            throw TranslationProviderError.other("Gemini error \(statusCode): \(String(bodyText.prefix(200)))")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw TranslationProviderError.other("Gemini response has no text")
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else {
            throw TranslationProviderError.other("Gemini response has no text")
        }
        return text
    }

    private static func isModelUnavailable(_ body: String) -> Bool {
        let lower = body.lowercased()
        guard lower.contains("model") else { return false }
        return ["not found", "no longer available", "not available", "unavailable"].contains { lower.contains($0) }
    }

    /// Gemini 429 errors carry a suggested wait, either as a RetryInfo
    /// detail (`"retryDelay": "7s"`) or as prose ("Please retry in 7.5s").
    /// Returns milliseconds capped at `LyricsTranslator.maxRetryDelayMs`.
    public static func retryDelayMs(fromErrorBody body: String) -> Int? {
        let patterns = [#""retryDelay"\s*:\s*"([\d.]+)s""#, #"(?i)retry in ([\d.]+)\s*s"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
                  let range = Range(match.range(at: 1), in: body),
                  let seconds = Double(body[range]), seconds.isFinite, seconds >= 0 else { continue }
            return min(Int((seconds * 1000).rounded()), LyricsTranslator.maxRetryDelayMs)
        }
        return nil
    }
}
