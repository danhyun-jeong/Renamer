import Foundation

struct ActivityEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let message: String
    let inputTokens: Int?
    let outputTokens: Int?
    let model: String?
    let cost: Double?   // USD

    init(timestamp: Date, message: String,
         inputTokens: Int? = nil, outputTokens: Int? = nil,
         model: String? = nil, cost: Double? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.message = message
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.model = model
        self.cost = cost
    }
}
