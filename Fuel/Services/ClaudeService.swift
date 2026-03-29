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

    func generateDailyBrief(context: BriefContext, apiKey: String) async throws -> DailyBriefResult {
        let systemPrompt = """
            You are a personal nutrition and performance coach embedded in a health tracking app. \
            You speak like a knowledgeable friend — direct, warm, and specific. Never say "data", \
            "statistics", or "metrics". Speak to the person, not about numbers.

            The user gives you a summary of their recent health context. You respond with a \
            personalized morning brief.

            Respond with ONLY valid JSON — no markdown, no explanation:

            {
              "brief": "2–4 sentences of specific, actionable coaching for today",
              "patternAlert": "optional — only include if there is a genuinely meaningful \
            cross-pattern insight (e.g. sleep → snacking, workout days → under-eating). \
            Omit this key entirely if no strong pattern exists.",
              "recommendedCalories": optional integer — only if yesterday or trends suggest \
            a meaningful target tweak (±100–200 cal). Omit if current target is appropriate.,
              "recommendedProtein": optional integer — only if protein trend warrants adjustment. \
            Omit if current target is fine.
            }

            Guidelines:
            - Be specific: mention actual numbers (sleep hours, calorie gap, etc.)
            - Focus on today's biggest lever — don't give a list of 5 things
            - If yesterday was great, say so briefly, then look ahead
            - If there's nothing interesting to say (consistent, on-target), still give \
            an encouraging, specific brief — don't be generic
            - Never include both a pattern alert AND a target recommendation unless both \
            are clearly warranted
            """

        let userMessage = buildBriefUserMessage(context)
        let request = try buildRequest(
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userContent: [.text(userMessage)]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let apiResponse = try decodeAnthropicResponse(data)
        let content = try extractTextContent(from: apiResponse)

        do {
            return try JSONDecoder().decode(DailyBriefResult.self, from: Data(content.utf8))
        } catch {
            throw ClaudeError.badExtractionJSON(raw: content)
        }
    }

    private func buildBriefUserMessage(_ context: BriefContext) -> String {
        var lines: [String] = []

        // Yesterday
        lines.append("Yesterday:")
        if let sleep = context.yesterdaySleepHours {
            lines.append("  Sleep: \(String(format: "%.1f", sleep))h")
        } else {
            lines.append("  Sleep: not available")
        }
        let calDiff = context.yesterdayCalories - context.yesterdayCalorieTarget
        let calSign = calDiff >= 0 ? "+" : ""
        lines.append("  Calories: \(context.yesterdayCalories) (target \(context.yesterdayCalorieTarget), \(calSign)\(calDiff))")
        let protDiff = context.yesterdayProtein - Double(context.yesterdayProteinTarget)
        let protSign = protDiff >= 0 ? "+" : ""
        lines.append("  Protein: \(Int(context.yesterdayProtein))g (target \(context.yesterdayProteinTarget)g, \(protSign)\(Int(protDiff))g)")

        // 14-day picture
        lines.append("\n14-day averages:")
        if let avgSleep = context.avgSleepHours {
            lines.append("  Sleep: \(String(format: "%.1f", avgSleep))h/night")
        }
        lines.append("  Calories: \(Int(context.avgCalories))/day")
        lines.append("  Protein: \(Int(context.avgProtein))g/day")
        lines.append("  Logging consistency: \(context.loggingConsistencyPct)% of days")

        // Weight
        if let weight = context.latestWeightLbs {
            var weightLine = "  Current weight: \(String(format: "%.1f", weight)) lbs"
            if let trend = context.weightTrendLbsPerWeek {
                let dir = trend > 0.05 ? "gaining" : trend < -0.05 ? "losing" : "stable"
                weightLine += " (\(dir), \(String(format: "%.1f", abs(trend))) lbs/week)"
            }
            lines.append("\nWeight:\n\(weightLine)")
        }

        // Today's targets
        lines.append("\nCurrent targets: \(context.currentCalorieTarget) cal, \(context.currentProteinTarget)g protein")

        // Workout
        if let workout = context.todayWorkoutType, let mins = context.todayWorkoutMinutes {
            lines.append("\nAlready detected today: \(workout) for \(mins) min")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Coaching Prompts

    private let dailyInsightSystemPrompt = """
        You are a concise nutrition coach in a personal tracking app. The user's #1 goal is hitting \
        their protein target. Speak like a knowledgeable friend — direct and specific. Never say \
        "data", "statistics", or "metrics". Respond with EXACTLY 1–2 sentences of actionable coaching. \
        No bullet points, no headers, no "Great job!" openers. Mention specific numbers. Focus on the \
        single highest-leverage action.
        """

    private let askCoachSystemPrompt = """
        You are a personal nutrition coach inside a tracking app. Answer the user's food question directly. \
        Their primary goal is hitting their daily protein target. Be concrete — name actual foods and amounts. \
        Keep it to 2–4 sentences. Don't say "based on your data." Just answer like a knowledgeable friend.
        """

    private let weeklyInsightSystemPrompt = """
        You are a nutrition coach analyzing someone's week of eating. Their primary goal is hitting their \
        protein target consistently. Respond with 2–3 sentences covering: (1) their average protein, \
        (2) which day(s) were the weakest and likely why, (3) one specific actionable suggestion for the \
        coming week. Be direct and specific. No bullet points, no headers, no filler praise. Mention actual \
        day names and numbers.
        """

    func generateDailyInsight(
        proteinEaten: Double,
        proteinTarget: Int,
        caloriesEaten: Int,
        calorieTarget: Int,
        mealCount: Int,
        sleepHours: Double?,
        apiKey: String
    ) async throws -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        let timeOfDay: String
        switch hour {
        case 0..<12: timeOfDay = "morning"
        case 12..<17: timeOfDay = "afternoon"
        case 17..<21: timeOfDay = "evening"
        default:      timeOfDay = "night"
        }

        var lines = [
            "Time of day: \(timeOfDay) (\(hour):00)",
            "Meals logged today: \(mealCount)",
            "Protein: \(Int(proteinEaten))g eaten / \(proteinTarget)g target (\(proteinTarget - Int(proteinEaten))g remaining)",
            "Calories: \(caloriesEaten) eaten / \(calorieTarget) target"
        ]
        if let sleep = sleepHours {
            lines.append("Sleep last night: \(String(format: "%.1f", sleep))h")
        }

        let request = try buildRequest(
            apiKey: apiKey,
            systemPrompt: dailyInsightSystemPrompt,
            userContent: [.text(lines.joined(separator: "\n"))]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        let apiResponse = try decodeAnthropicResponse(data)
        return try extractTextContent(from: apiResponse)
    }

    func askCoach(
        question: String,
        proteinRemaining: Double,
        caloriesRemaining: Int,
        proteinTarget: Int,
        calorieTarget: Int,
        apiKey: String
    ) async throws -> String {
        let context = """
            Current context:
            Protein remaining today: \(Int(proteinRemaining))g (target \(proteinTarget)g)
            Calories remaining today: \(caloriesRemaining) (target \(calorieTarget))

            User's question: \(question)
            """
        let request = try buildRequest(
            apiKey: apiKey,
            systemPrompt: askCoachSystemPrompt,
            userContent: [.text(context)]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        let apiResponse = try decodeAnthropicResponse(data)
        return try extractTextContent(from: apiResponse)
    }

    func generateWeeklyInsight(
        days: [(dateString: String, protein: Double, calories: Int)],
        proteinTarget: Int,
        calorieTarget: Int,
        apiKey: String
    ) async throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"

        let rows = days.map { day -> String in
            let date = dateFormatter.date(from: day.dateString) ?? .now
            let dayName = dayFormatter.string(from: date)
            let hitTarget = day.protein >= Double(proteinTarget) * 0.9 ? "hit" : "missed"
            return "  \(dayName): \(Int(day.protein))g protein (\(hitTarget)), \(day.calories) cal"
        }.joined(separator: "\n")

        let avg = days.isEmpty ? 0 : Int(days.reduce(0.0) { $0 + $1.protein } / Double(days.count))

        let message = """
            7-day summary (target: \(proteinTarget)g protein / \(calorieTarget) cal):
            \(rows)
            7-day average protein: \(avg)g
            """

        let request = try buildRequest(
            apiKey: apiKey,
            systemPrompt: weeklyInsightSystemPrompt,
            userContent: [.text(message)]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
        let apiResponse = try decodeAnthropicResponse(data)
        return try extractTextContent(from: apiResponse)
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

// MARK: - Daily Brief Types

struct BriefContext {
    // Yesterday
    let yesterdaySleepHours: Double?
    let yesterdayCalories: Int
    let yesterdayCalorieTarget: Int
    let yesterdayProtein: Double
    let yesterdayProteinTarget: Int

    // 14-day averages
    let avgSleepHours: Double?
    let avgCalories: Double
    let avgProtein: Double
    let loggingConsistencyPct: Int  // 0–100

    // Weight trend
    let latestWeightLbs: Double?
    let weightTrendLbsPerWeek: Double?  // positive = gaining, negative = losing

    // Today context
    let currentCalorieTarget: Int
    let currentProteinTarget: Int
    let todayWorkoutType: String?
    let todayWorkoutMinutes: Int?
}

struct DailyBriefResult: Decodable {
    let brief: String
    let patternAlert: String?
    let recommendedCalories: Int?
    let recommendedProtein: Int?
}
