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

final class GeminiAPITests: XCTestCase {
    func testRequestShape() throws {
        let req = try GeminiAPI.makeRequest(apiKey: "secret-key", model: "gemini-flash-lite-latest", prompt: "hello")
        XCTAssertEqual(req.url?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-goog-api-key"), "secret-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertFalse(req.url!.absoluteString.contains("secret-key"))

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any])
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, "hello")
        let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(config["responseMimeType"] as? String, "application/json")
    }

    func testRequestRejectsModelThatBreaksTheURL() {
        XCTAssertThrowsError(try GeminiAPI.makeRequest(apiKey: "k", model: "bad model/../x", prompt: "p"))
        XCTAssertThrowsError(try GeminiAPI.makeRequest(apiKey: "k", model: "", prompt: "p"))
    }

    func testParseExtractsText() throws {
        let body = #"{"candidates":[{"content":{"role":"model","parts":[{"text":"[\"a\","},{"text":"\"b\"]"}]}}]}"#
        XCTAssertEqual(try GeminiAPI.parse(data: Data(body.utf8), statusCode: 200, model: "m"), #"["a","b"]"#)
    }

    func testParseSuccessWithNoTextThrowsOther() {
        XCTAssertThrowsError(try GeminiAPI.parse(data: Data(#"{"candidates":[]}"#.utf8), statusCode: 200, model: "m")) {
            guard case TranslationProviderError.other = $0 else { return XCTFail("wrong error \($0)") }
        }
        XCTAssertThrowsError(try GeminiAPI.parse(data: Data("garbage".utf8), statusCode: 200, model: "m"))
    }

    func testParse429CarriesRetryDelay() {
        let body = #"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","details":[{"retryDelay":"7s"}]}}"#
        XCTAssertThrowsError(try GeminiAPI.parse(data: Data(body.utf8), statusCode: 429, model: "m")) {
            XCTAssertEqual($0 as? TranslationProviderError, .rateLimited(retryAfterMs: 7000))
        }
        XCTAssertThrowsError(try GeminiAPI.parse(data: Data("{}".utf8), statusCode: 429, model: "m")) {
            XCTAssertEqual($0 as? TranslationProviderError, .rateLimited(retryAfterMs: nil))
        }
    }

    func testParse404ModelNotFound() {
        let body = #"{"error":{"code":404,"message":"This model retired-model is no longer available to new users"}}"#
        XCTAssertThrowsError(try GeminiAPI.parse(data: Data(body.utf8), statusCode: 404, model: "retired-model")) {
            XCTAssertEqual($0 as? TranslationProviderError, .modelUnavailable(model: "retired-model"))
        }
    }

    func testParseOtherErrors() {
        XCTAssertThrowsError(try GeminiAPI.parse(data: Data("{}".utf8), statusCode: 500, model: "m")) {
            guard case TranslationProviderError.other = $0 else { return XCTFail("wrong error \($0)") }
        }
        XCTAssertThrowsError(try GeminiAPI.parse(data: Data(#"{"error":{"message":"nope"}}"#.utf8), statusCode: 404, model: "m")) {
            guard case TranslationProviderError.other = $0 else { return XCTFail("wrong error \($0)") }
        }
    }

    func testParseRejectedRequests() {
        for code in [400, 401, 403] {
            let body = #"{"error":{"code":\#(code),"message":"API key not valid. Please pass a valid API key."}}"#
            XCTAssertThrowsError(try GeminiAPI.parse(data: Data(body.utf8), statusCode: code, model: "m")) {
                XCTAssertEqual($0 as? TranslationProviderError, .rejected(statusCode: code))
            }
        }
    }

    func testErrorsNeverContainTheKey() {
        // The key is not an input to parse; the body is echoed at most truncated.
        let long = String(repeating: "x", count: 5000)
        XCTAssertThrowsError(try GeminiAPI.parse(data: Data(long.utf8), statusCode: 500, model: "m")) {
            guard case TranslationProviderError.other(let message) = $0 else { return XCTFail("wrong error \($0)") }
            XCTAssertLessThan(message.count, 400)
        }
    }

    func testRetryDelayForms() {
        XCTAssertEqual(GeminiAPI.retryDelayMs(fromErrorBody: #""retryDelay": "39s""#), 39000)
        XCTAssertEqual(GeminiAPI.retryDelayMs(fromErrorBody: "Please retry in 7.5s."), 7500)
        XCTAssertEqual(GeminiAPI.retryDelayMs(fromErrorBody: #""retryDelay": "600s""#), 60000)
        XCTAssertNil(GeminiAPI.retryDelayMs(fromErrorBody: "no delay here"))
    }
}
