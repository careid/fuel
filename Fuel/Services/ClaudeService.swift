import Foundation

final class ClaudeService {
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-6"

    private let extractionSystemPrompt = """
        You are a nutrition extraction assistant inside a calorie/protein tracking app.

        When the user describes what they ate, extract each food item with macro estimates.

        Respond with ONLY valid JSON matching this schema — no markdown, no explanation:

        {
          "items": [
            {
              "name": "string — food name",
              "calories": "integer",
              "proteinGrams": "number",
              "carbsGrams": "number",
              "fatGrams": "number",
              "quantity": "string — e.g. '2 eggs', '1 cup', '6oz'",
              "confidence": "high | medium | low"
            }
          ],
          "notes": "optional string — anything ambiguous or worth mentioning"
        }

        Guidelines:
        - Estimate portions based on typical servings if not specified
        - Use USDA data as your baseline for macros
        - Mark confidence as "low" if you're guessing portion size
        - Mark confidence as "high" for well-known items like "1 large egg"
        - If the user says something vague like "a big lunch", ask for clarification in "notes"
        - Round calories to nearest 5, macros to nearest 0.5g
        """

    func extractMeal(from text: String, apiKey: String) async throws -> ExtractionResult {
        let request = buildRequest(
            apiKey: apiKey,
            systemPrompt: extractionSystemPrompt,
            userContent: [.text(text)]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = try extractTextContent(from: apiResponse)

        return try JSONDecoder().decode(ExtractionResult.self, from: Data(content.utf8))
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

        let request = buildRequest(
            apiKey: apiKey,
            systemPrompt: extractionSystemPrompt,
            userContent: [.text(prompt)]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let content = try extractTextContent(from: apiResponse)

        return try JSONDecoder().decode(ExtractionResult.self, from: Data(content.utf8))
    }
}

// MARK: - Request Building

extension ClaudeService {
    private func buildRequest(
        apiKey: String,
        systemPrompt: String,
        userContent: [ContentBlock]
    ) -> URLRequest {
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

        request.httpBody = try! JSONEncoder().encode(body)
        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        let httpResponse = response as! HTTPURLResponse
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode)
        }
    }

    private func extractTextContent(from response: AnthropicResponse) throws -> String {
        guard let textBlock = response.content.first(where: { $0.type == "text" }) else {
            throw ClaudeError.noTextContent
        }
        return textBlock.text
    }
}

// MARK: - API Types

enum ClaudeError: Error, LocalizedError {
    case apiError(statusCode: Int)
    case noTextContent

    var errorDescription: String? {
        switch self {
        case .apiError(let code): "Claude API error (HTTP \(code))"
        case .noTextContent: "No text content in Claude response"
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text
    }
}

struct AnthropicResponse: Decodable {
    let content: [ResponseContent]

    struct ResponseContent: Decodable {
        let type: String
        let text: String
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
