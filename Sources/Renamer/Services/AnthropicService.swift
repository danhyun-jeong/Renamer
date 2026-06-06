import Foundation

struct APIUsage: Sendable {
    let inputTokens: Int
    let outputTokens: Int

    func cost(model: String) -> Double {
        let (inRate, outRate): (Double, Double)
        if model.hasPrefix("claude-haiku-4-5") {
            (inRate, outRate) = (1.00, 5.00)
        } else if model.hasPrefix("claude-sonnet-4-6") {
            (inRate, outRate) = (3.00, 15.00)
        } else {
            (inRate, outRate) = (3.00, 15.00)
        }
        return Double(inputTokens) / 1_000_000 * inRate
             + Double(outputTokens) / 1_000_000 * outRate
    }
}

struct AnthropicService: Sendable {
    let apiKey: String
    let model: String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func send(system: String, content: [[String: Any]]) async throws -> (text: String, usage: APIUsage) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": [["role": "user", "content": content]]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw RenamerError.networkError("Invalid response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw RenamerError.apiError("HTTP \(http.statusCode): \(body.prefix(200))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArr = json["content"] as? [[String: Any]],
              let text = contentArr.first?["text"] as? String else {
            throw RenamerError.parseError("Unexpected API response format")
        }

        let usageDict = json["usage"] as? [String: Any]
        let usage = APIUsage(
            inputTokens: usageDict?["input_tokens"] as? Int ?? 0,
            outputTokens: usageDict?["output_tokens"] as? Int ?? 0
        )

        return (text: text, usage: usage)
    }
}

enum RenamerError: LocalizedError {
    case networkError(String)
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "네트워크 오류: \(msg)"
        case .apiError(let msg):     return "API 오류: \(msg)"
        case .parseError(let msg):   return "파싱 오류: \(msg)"
        }
    }
}
