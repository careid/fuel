import Foundation
import UIKit

final class ClaudeService {
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-6"

    private let extractionSystemPrompt = """
        You are a nutrition extraction assistant inside a calorie/protein tracking app.

        The user is logging what they ate. Inputs are often short — a brand name, a product \
        name, a quick note. Always extract items and return macros. Never refuse or ask for \
        clarification instead of extracting. If something is unclear, make your best estimate \
        and note it.

        Respond with ONLY valid JSON matching this schema — no markdown, no explanation:

        {
          "items": [
            {
              "name": "string — food name",
              "calories": "integer",
              "proteinGrams": "number",
              "carbsGrams": "number",
              "fatGrams": "number",
              "quantity": "string — e.g. '2 eggs', '1 cup', '6oz', '1 bottle'",
              "confidence": "high | medium | low"
            }
          ],
          "notes": "optional string — only for genuinely ambiguous quantities or sizes"
        }

        Guidelines:
        - Inputs can be very short: "Ensure Max", "quest bar", "chipotle bowl", "2 eggs" are \
          all valid. Extract them as-is using your knowledge of common foods and brands.
        - For branded products (Ensure, Quest, KIND, Rx Bar, Fairlife, etc.) use the standard \
          serving size and label macros.
        - Assume one serving unless a quantity is specified (e.g. "2 Ensure Max" = 2 servings).
        - Estimate portions based on typical servings if not specified.
        - Use USDA data as your baseline for generic foods; use label data for branded products.
        - Mark confidence "high" for well-known branded items or precisely specified quantities.
        - Mark confidence "low" only when the portion size is genuinely unknown.
        - Only use "notes" if the quantity is truly ambiguous — not just because the input is short.
        - Round calories to nearest 5, macros to nearest 0.5g.
        """

    func extractMeal(from text: String, apiKey: String) async throws -> ExtractionResult {
        let request = try buildRequest(
            apiKey: apiKey,
            systemPrompt: extractionSystemPrompt,
            userContent: [.text(text)]
        )

        return try await sendExtractionRequest(request)
    }

    func extractMeal(from image: UIImage, apiKey: String) async throws -> ExtractionResult {
        guard let jpeg = resizedJPEG(image) else { throw ClaudeError.noTextContent }
        let base64 = jpeg.base64EncodedString()
        let request = try buildRequest(
            apiKey: apiKey,
            systemPrompt: extractionSystemPrompt,
            userContent: [
                .image(mediaType: "image/jpeg", base64Data: base64),
                .text("Identify the food in this image and extract nutrition info using the schema.")
            ]
        )
        return try await sendExtractionRequest(request)
    }

    private func sendExtractionRequest(_ request: URLRequest) async throws -> ExtractionResult {

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let apiResponse = try decodeAnthropicResponse(data)
        let content = try extractTextContent(from: apiResponse)

        do {
            return try JSONDecoder().decode(ExtractionResult.self, from: Data(content.utf8))
        } catch {
            throw ClaudeError.badExtractionJSON(raw: content)
        }
    }

    func refineMeal(
        originalItems: [ExtractedItem],
        refinement: String,
        apiKey: String
    ) async throws -> ExtractionResult {
        let itemsJSON = try String(data: JSONEncoder().encode(originalItems), encoding: .utf8)!

        let prompt = """
            The user previously logged these items:
            \(itemsJSON)

            They want to make a correction: "\(refinement)"

            Return the COMPLETE updated list of items (not just the changed ones) \
            using the same JSON schema as before.
            """

        let request = try buildRequest(
            apiKey: apiKey,
            systemPrompt: extractionSystemPrompt,
            userContent: [.text(prompt)]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let apiResponse = try decodeAnthropicResponse(data)
        let content = try extractTextContent(from: apiResponse)

        do {
            return try JSONDecoder().decode(ExtractionResult.self, from: Data(content.utf8))
        } catch {
            throw ClaudeError.badExtractionJSON(raw: content)
        }
    }
}

// MARK: - Request Building

extension ClaudeService {
    private func buildRequest(
        apiKey: String,
        systemPrompt: String,
        userContent: [ContentBlock]
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = AnthropicRequest(
            model: model,
            maxTokens: 1024,
            system: systemPrompt,
            messages: [
                .init(role: "user", content: userContent),
            ]
        )

        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func decodeAnthropicResponse(_ data: Data) throws -> AnthropicResponse {
        do {
            return try JSONDecoder().decode(AnthropicResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw ClaudeError.badAPIResponse(raw: raw)
        }
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.badAPIResponse(raw: "Non-HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode)
        }
    }

    private func extractTextContent(from response: AnthropicResponse) throws -> String {
        guard let textBlock = response.content.first(where: { $0.type == "text" }),
              let text = textBlock.text else {
            throw ClaudeError.noTextContent
        }
        return stripMarkdownCodeFences(text)
    }

    private func resizedJPEG(_ image: UIImage, maxDimension: CGFloat = 1024) -> Data? {
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.75)
    }

    private func stripMarkdownCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.drop(while: { $0 != "\n" }).dropFirst()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }
}

// MARK: - API Types

enum ClaudeError: Error, LocalizedError {
    case apiError(statusCode: Int)
    case noTextContent
    case badAPIResponse(raw: String)
    case badExtractionJSON(raw: String)

    var errorDescription: String? {
        switch self {
        case .apiError(let code): "Claude API error (HTTP \(code))"
        case .noTextContent: "No text content in Claude response"
        case .badAPIResponse(let raw): "Unexpected API response: \(raw.prefix(300))"
        case .badExtractionJSON(let raw): "Could not parse Claude's response: \(raw.prefix(300))"
        }
    }
}

struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }

    struct Message: Encodable {
        let role: String
        let content: [ContentBlock]
    }
}

enum ContentBlock: Encodable {
    case text(String)
    case image(mediaType: String, base64Data: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let mediaType, let base64Data):
            try container.encode("image", forKey: .type)
            var src = container.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try src.encode("base64", forKey: .type)
            try src.encode(mediaType, forKey: .mediaType)
            try src.encode(base64Data, forKey: .data)
        }
    }

    private enum CodingKeys: String, CodingKey { case type, text, source }
    private enum SourceKeys: String, CodingKey {
        case type, mediaType = "media_type", data
    }
}

struct AnthropicResponse: Decodable {
    let content: [ResponseContent]

    struct ResponseContent: Decodable {
        let type: String
        let text: String?
    }
}

// MARK: - Extraction Types

struct ExtractionResult: Decodable {
    let items: [ExtractedItem]
    let notes: String?
}

struct ExtractedItem: Codable {
    let name: String
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let quantity: String
    let confidence: String
}
