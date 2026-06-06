import Foundation

// 통계 전용 경량 레코드 — 로그와 독립적으로 저장
struct StatEntry: Codable {
    let timestamp: Date
    let wasRenamed: Bool
    let cost: Double
}

@MainActor
class FileRenamerService: ObservableObject {
    @Published var activityLog: [ActivityEntry] = []
    @Published var isRunning = false

    var posterTemplate  = NameTemplate.defaultPosterTemplate
    var articleTemplate = NameTemplate.defaultArticleTemplate
    var enablePDF: Bool   = true
    var enableImage: Bool = true
    private(set) var currentModel: String = ""
    var statsResetDate: Date = .distantPast
    var maxLogCount: Int  = 100 {
        didSet { trimLog() }
    }

    private var statsLog: [StatEntry] = []

    private var watcher: DownloadsFolderWatcher?
    private var imageAnalyzer: ImageAnalyzer?
    private var pdfAnalyzer: PDFAnalyzer?

    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"]

    private var renamerDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Renamer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var logFileURL:   URL { renamerDir.appendingPathComponent("activity_log.json") }
    private var statsFileURL: URL { renamerDir.appendingPathComponent("stats_log.json") }

    init() {
        loadLog()
        loadStatsLog()
    }

    // MARK: - Activity log persistence

    private func loadLog() {
        guard let data = try? Data(contentsOf: logFileURL),
              let entries = try? JSONDecoder().decode([ActivityEntry].self, from: data) else { return }
        activityLog = Array(entries.prefix(maxLogCount))
    }

    private func saveLog() {
        guard let data = try? JSONEncoder().encode(activityLog) else { return }
        try? data.write(to: logFileURL, options: .atomic)
    }

    func clearLog() {
        activityLog = []
        try? FileManager.default.removeItem(at: logFileURL)
        // statsLog는 건드리지 않음
    }

    private func trimLog() {
        if activityLog.count > maxLogCount {
            activityLog = Array(activityLog.prefix(maxLogCount))
            saveLog()
        }
    }

    // MARK: - Stats log persistence (로그 초기화와 독립)

    private func loadStatsLog() {
        guard let data = try? Data(contentsOf: statsFileURL),
              let entries = try? JSONDecoder().decode([StatEntry].self, from: data) else { return }
        statsLog = entries
    }

    private func saveStatsLog() {
        guard let data = try? JSONEncoder().encode(statsLog) else { return }
        try? data.write(to: statsFileURL, options: .atomic)
    }

    private func recordStat(wasRenamed: Bool, cost: Double) {
        statsLog.append(StatEntry(timestamp: Date(), wasRenamed: wasRenamed, cost: cost))
        // 60일 초과 항목 정리
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -60,
            to: Calendar.current.startOfDay(for: Date())
        )!
        statsLog = statsLog.filter { $0.timestamp >= cutoff }
        saveStatsLog()
    }

    // MARK: - Stats (기준일 이후 누적)

    var totalAnalyzed: Int {
        statsLog.filter { $0.timestamp > statsResetDate }.count
    }

    var totalRenamed: Int {
        statsLog.filter { $0.wasRenamed && $0.timestamp > statsResetDate }.count
    }

    var totalCost: Double {
        statsLog
            .filter { $0.timestamp > statsResetDate }
            .map { $0.cost }
            .reduce(0, +)
    }

    // MARK: - Stats (지난 30일 — 로그 삭제와 무관)

    private var thirtyDaysCutoff: Date {
        Calendar.current.date(
            byAdding: .day, value: -30,
            to: Calendar.current.startOfDay(for: Date())
        )!
    }

    var last30DaysAnalyzed: Int {
        statsLog.filter { $0.timestamp >= thirtyDaysCutoff }.count
    }

    var last30DaysRenamed: Int {
        statsLog.filter { $0.wasRenamed && $0.timestamp >= thirtyDaysCutoff }.count
    }

    var last30DaysCost: Double {
        statsLog
            .filter { $0.timestamp >= thirtyDaysCutoff }
            .map { $0.cost }
            .reduce(0, +)
    }

    func start(apiKey: String, model: String) {
        currentModel = model
        let anthropic = AnthropicService(apiKey: apiKey, model: model)
        imageAnalyzer = ImageAnalyzer(service: anthropic)
        pdfAnalyzer = PDFAnalyzer(service: anthropic)

        let newWatcher = DownloadsFolderWatcher()
        newWatcher.onNewFile = { [weak self] url in
            Task { @MainActor [weak self] in
                await self?.handle(url)
            }
        }
        newWatcher.start()
        watcher = newWatcher

        isRunning = true
        log("모니터링 시작: 다운로드 폴더")
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        isRunning = false
        log("모니터링 중지")
    }

    private func handle(_ url: URL) async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let ext = url.pathExtension.lowercased()
        if enableImage && imageExtensions.contains(ext) {
            await processImage(url)
        } else if enablePDF && ext == "pdf" {
            await processPDF(url)
        }
    }

    private let retryDelays: [TimeInterval] = [5, 15, 30]

    private func processImage(_ url: URL) async {
        let original = url.lastPathComponent
        log("이미지 분석 중: \(original)")
        for attempt in 0...retryDelays.count {
            if attempt > 0 {
                let delay = retryDelays[attempt - 1]
                log("↩ 재시도 \(attempt)/\(retryDelays.count) (\(Int(delay))초 후): \(original)")
                try? await Task.sleep(for: .seconds(delay))
                guard FileManager.default.fileExists(atPath: url.path) else { return }
            }
            do {
                let (info, usage) = try await imageAnalyzer?.analyze(imageURL: url) ?? (nil, nil)
                guard let info else {
                    log("포스터 아님, 제목 변경 안 함: \(original)", usage: usage)
                    return
                }
                let newName = buildPosterName(info: info, ext: url.pathExtension)
                watcher?.markProcessed(url: url)
                let actual = try renameFile(at: url, to: newName)
                log("✓ \(original)\n  → \(actual)", usage: usage)
                return
            } catch {
                if attempt == retryDelays.count {
                    log("⚠️ 최종 실패 (\(original)): \(error.localizedDescription)")
                } else {
                    log("오류, 재시도 예정 (\(original)): \(error.localizedDescription)")
                }
            }
        }
    }

    private func processPDF(_ url: URL) async {
        let original = url.lastPathComponent
        log("PDF 분석 중: \(original)")
        for attempt in 0...retryDelays.count {
            if attempt > 0 {
                let delay = retryDelays[attempt - 1]
                log("↩ 재시도 \(attempt)/\(retryDelays.count) (\(Int(delay))초 후): \(original)")
                try? await Task.sleep(for: .seconds(delay))
                guard FileManager.default.fileExists(atPath: url.path) else { return }
            }
            do {
                let (info, usage) = try await pdfAnalyzer?.analyze(pdfURL: url) ?? (nil, nil)
                guard let info else {
                    log("논문 아님, 제목 변경 안 함: \(original)", usage: usage)
                    return
                }
                let newName = buildArticleName(info: info)
                watcher?.markProcessed(url: url)
                let actual = try renameFile(at: url, to: newName)
                log("✓ \(original)\n  → \(actual)", usage: usage)
                return
            } catch {
                if attempt == retryDelays.count {
                    log("⚠️ 최종 실패 (\(original)): \(error.localizedDescription)")
                } else {
                    log("오류, 재시도 예정 (\(original)): \(error.localizedDescription)")
                }
            }
        }
    }

    private func buildPosterName(info: PosterInfo, ext: String) -> String {
        let sanitized = PosterInfo(
            eventTitle: sanitize(info.eventTitle),
            year: info.year, month: info.month, day: info.day
        )
        let rendered = NameTemplate.renderPoster(template: posterTemplate, info: sanitized)
        let fileExt = ext.isEmpty ? "jpg" : ext
        return "\(rendered).\(fileExt)"
    }

    private func buildArticleName(info: ArticleInfo) -> String {
        let sanitized = ArticleInfo(
            authorName: sanitize(info.authorName),
            mainTitle: sanitize(info.mainTitle),
            publicationYear: info.publicationYear
        )
        let rendered = NameTemplate.renderArticle(template: articleTemplate, info: sanitized)
        return "\(rendered).pdf"
    }

    private func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\0")
        return name
            .replacingOccurrences(of: "<", with: "〈")
            .replacingOccurrences(of: ">", with: "〉")
            .curlyQuoted()
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func renameFile(at url: URL, to newName: String) throws -> String {
        var dest = url.deletingLastPathComponent().appendingPathComponent(newName)

        if FileManager.default.fileExists(atPath: dest.path) {
            let baseName = dest.deletingPathExtension().lastPathComponent
            let ext = dest.pathExtension
            var i = 2
            repeat {
                let candidate = ext.isEmpty ? "\(baseName) (\(i))" : "\(baseName) (\(i)).\(ext)"
                dest = url.deletingLastPathComponent().appendingPathComponent(candidate)
                i += 1
            } while FileManager.default.fileExists(atPath: dest.path)
        }

        try FileManager.default.moveItem(at: url, to: dest)
        return dest.lastPathComponent
    }

    private func log(_ message: String, usage: APIUsage? = nil) {
        let cost = usage.map { $0.cost(model: currentModel) }
        let entry = ActivityEntry(
            timestamp: Date(),
            message: message,
            inputTokens: usage?.inputTokens,
            outputTokens: usage?.outputTokens,
            model: usage != nil ? currentModel : nil,
            cost: cost
        )
        activityLog.insert(entry, at: 0)
        if activityLog.count > maxLogCount {
            activityLog = Array(activityLog.prefix(maxLogCount))
        }
        saveLog()

        // 통계 저장 (로그와 독립)
        if let cost {
            recordStat(wasRenamed: message.hasPrefix("✓"), cost: cost)
        }
    }
}
