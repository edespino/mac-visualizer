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
import MacVisualizerCore

/// Sends translation prompts to the Gemini REST API. Request building and
/// response parsing live in `GeminiAPI` (Core, unit tested); this type only
/// does the network round trip. The API key is never logged.
struct GeminiProvider: TranslationProvider {
    let apiKey: String
    let model: String

    /// `generateContent` is not streamed: no bytes arrive until the model
    /// has finished, and the request timeout is an idle timer, so it has to
    /// allow for a whole-song generation, not just a stalled connection.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    func generate(prompt: String) async throws -> String {
        let request = try GeminiAPI.makeRequest(apiKey: apiKey, model: model, prompt: prompt)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TranslationProviderError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try GeminiAPI.parse(data: data, statusCode: status, model: model)
    }
}
