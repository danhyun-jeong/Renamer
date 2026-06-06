import Foundation

struct PosterInfo {
    let eventTitle: String
    let year: String    // "2025" (4자리) or ""
    let month: String   // "06"  (2자리, 선행 0) or ""
    let day: String     // "15"  (2자리, 선행 0) or ""
}

struct ImageAnalyzer {
    let service: AnthropicService

    func analyze(imageURL: URL) async throws -> (info: PosterInfo?, usage: APIUsage?) {
        let imageData = try Data(contentsOf: imageURL)
        guard imageData.count < 20_000_000 else { return (nil, nil) }

        let base64    = imageData.base64EncodedString()
        let mediaType = imageMediaType(for: imageURL)

        let system = "You are a file naming assistant. Analyze images and respond ONLY with valid JSON. No explanation or markdown."

        let userContent: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": base64
                ]
            ],
            [
                "type": "text",
                "text": """
                Is this image an event poster (행사 포스터, 공연 포스터, 전시 포스터, 강연 포스터, 세미나 포스터, etc.)?

                A poster typically advertises an event with: event title, date/time, venue, and promotional design.
                Not a poster: regular photos, screenshots, product images, logos, documents, memes.

                Respond with JSON only (no markdown, no explanation):
                {
                  "is_poster": true,
                  "event_title": "exact event title as shown in the image (preserve original language)",
                  "year":  "4-digit year, e.g. 2025. Empty string if not found.",
                  "month": "2-digit month with leading zero, e.g. 06. Empty string if not found.",
                  "day":   "2-digit day with leading zero, e.g. 15. Empty string if not found."
                }

                If NOT a poster:
                {"is_poster": false, "event_title": "", "year": "", "month": "", "day": ""}
                """
            ]
        ]

        let (text, usage) = try await service.send(system: system, content: userContent)
        return (parsePosterJSON(text), usage)
    }

    private func parsePosterJSON(_ text: String) -> PosterInfo? {
        guard let data = extractJSON(from: text).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isPoster = json["is_poster"] as? Bool,
              isPoster else { return nil }

        let title = (json["event_title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let year  = (json["year"]        as? String ?? "").trimmingCharacters(in: .whitespaces)
        let month = (json["month"]       as? String ?? "").trimmingCharacters(in: .whitespaces)
        let day   = (json["day"]         as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        return PosterInfo(eventTitle: title, year: year, month: month, day: day)
    }

    private func imageMediaType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":          return "image/png"
        case "gif":          return "image/gif"
        case "webp":         return "image/webp"
        default:             return "image/jpeg"
        }
    }

    private func extractJSON(from text: String) -> String {
        if let start = text.firstIndex(of: "{"),
           let end   = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}
