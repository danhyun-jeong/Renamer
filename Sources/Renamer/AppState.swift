import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var apiKey: String
    @Published var selectedModel: String
    @Published var posterTemplate: String
    @Published var articleTemplate: String
    @Published var maxLogCount: Int
    @Published var enablePDF: Bool
    @Published var enableImage: Bool
    @Published var statsResetDate: Date

    static let logCountOptions = [100, 250, 500, 1000]

    let service = FileRenamerService()
    private let defaults = UserDefaults.standard
    private var cancellable: AnyCancellable?

    static let availableModels: [(id: String, label: String)] = [
        ("claude-haiku-4-5-20251001", "Haiku 4.5"),
        ("claude-sonnet-4-6",         "Sonnet 4.6"),
    ]

    init() {
        apiKey        = defaults.string(forKey: "anthropicAPIKey") ?? ""
        selectedModel = defaults.string(forKey: "selectedModel")   ?? "claude-haiku-4-5-20251001"
        posterTemplate  = defaults.string(forKey: "posterTemplate")  ?? NameTemplate.defaultPosterTemplate
        articleTemplate = defaults.string(forKey: "articleTemplate") ?? NameTemplate.defaultArticleTemplate
        maxLogCount  = defaults.integer(forKey: "maxLogCount").nonZero ?? 100
        enablePDF    = defaults.object(forKey: "enablePDF")   as? Bool ?? true
        enableImage  = defaults.object(forKey: "enableImage") as? Bool ?? true
        statsResetDate = defaults.object(forKey: "statsResetDate") as? Date ?? .distantPast

        cancellable = service.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        service.posterTemplate  = posterTemplate
        service.articleTemplate = articleTemplate
        service.maxLogCount     = maxLogCount
        service.enablePDF       = enablePDF
        service.enableImage     = enableImage
        service.statsResetDate  = statsResetDate

        if !apiKey.isEmpty {
            service.start(apiKey: apiKey, model: selectedModel)
        }
    }

    func saveAndStart() {
        defaults.set(apiKey,        forKey: "anthropicAPIKey")
        defaults.set(selectedModel, forKey: "selectedModel")
        service.stop()
        guard !apiKey.isEmpty else { return }
        service.start(apiKey: apiKey, model: selectedModel)
    }

    func saveModel() {
        defaults.set(selectedModel, forKey: "selectedModel")
        guard !apiKey.isEmpty, service.isRunning else { return }
        service.stop()
        service.start(apiKey: apiKey, model: selectedModel)
    }

    func saveTemplates() {
        defaults.set(posterTemplate,  forKey: "posterTemplate")
        defaults.set(articleTemplate, forKey: "articleTemplate")
        service.posterTemplate  = posterTemplate
        service.articleTemplate = articleTemplate
    }

    func resetPosterTemplate() {
        posterTemplate = NameTemplate.defaultPosterTemplate
        saveTemplates()
    }

    func resetArticleTemplate() {
        articleTemplate = NameTemplate.defaultArticleTemplate
        saveTemplates()
    }

    func saveTargets() {
        defaults.set(enablePDF,   forKey: "enablePDF")
        defaults.set(enableImage, forKey: "enableImage")
        service.enablePDF   = enablePDF
        service.enableImage = enableImage
    }

    func saveMaxLogCount() {
        defaults.set(maxLogCount, forKey: "maxLogCount")
        service.maxLogCount = maxLogCount
    }

    func clearLog() {
        service.clearLog()
    }

    func resetStats() {
        statsResetDate = Date()
        defaults.set(statsResetDate, forKey: "statsResetDate")
        service.statsResetDate = statsResetDate
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
