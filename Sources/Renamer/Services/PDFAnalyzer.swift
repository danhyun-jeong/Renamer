import Foundation
import PDFKit
import Vision

struct ArticleInfo {
    let authorName: String
    let mainTitle: String
    let publicationYear: String   // "2023" or "" if not found
}

struct PDFAnalyzer {
    let service: AnthropicService

    func analyze(pdfURL: URL) async throws -> (info: ArticleInfo?, usage: APIUsage?) {
        guard let pdf = PDFDocument(url: pdfURL) else { return (nil, nil) }
        let pageCount = pdf.pageCount
        guard let firstPage = pdf.page(at: 0) else { return (nil, nil) }

        // ── 1. 첫 페이지 ────────────────────────────────────────────
        var firstPageText = firstPage.string ?? ""
        let isScanned = firstPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isScanned {
            firstPageText = await ocrPage(firstPage)
        }
        guard !firstPageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (nil, nil) }

        // ── 사전 필터: 발제문·초고 등 학술지 논문이 아닌 문서 제외 ───
        let excludeKeywords = ["발제", "발제문", "발표", "발표문", "초고"]
        let filename = pdfURL.deletingPathExtension().lastPathComponent
        let firstChars = String(firstPageText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        let candidateText = filename + " " + firstChars
        if excludeKeywords.contains(where: { candidateText.contains($0) }) { return (nil, nil) }

        // ── 2. 2~3페이지 머릿말·꼬리말 ─────────────────────────────
        // 짝수/홀수 페이지에만 나오는 머릿말을 모두 잡기 위해 2, 3페이지 각각 상단 + 하단 발췌
        var headerFooterText = ""
        for i in 1..<min(4, pageCount) {
            if let page = pdf.page(at: i),
               let raw = page.string,
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let head = String(t.prefix(80))
                let tail = t.count > 160 ? " … " + String(t.suffix(80)) : ""
                headerFooterText += "p\(i + 1): \(head)\(tail)\n"
            }
        }

        // ── 3. 마지막 3페이지에서 날짜 키워드 줄만 추출 ────────────
        // 영문 초록이 맨 마지막에 와도 날짜 키워드가 없으므로 자동으로 걸러짐
        var tailPagesText = ""
        let tailStart = max(1, pageCount - 3)
        for i in tailStart..<pageCount {
            if let page = pdf.page(at: i) {
                var text = page.string ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isScanned {
                    text = await ocrPage(page)
                }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tailPagesText += text + "\n"
                }
            }
        }
        let lastPageSnippet = extractDateLines(from: tailPagesText)

        // ── API 호출 ────────────────────────────────────────────────
        let firstPageSnippet = String(firstPageText.prefix(1000))

        let system = "You are a file naming assistant for academic papers. Respond ONLY with valid JSON. No explanation or markdown."

        let sourceBlock = """
            [SOURCE 1 — First page (title, authors, journal metadata)]
            ---
            \(firstPageSnippet)
            ---

            [SOURCE 2 — Pages 2–3 header/footer excerpts (running head, journal name, volume/year)]
            ---
            \(headerFooterText.isEmpty ? "(unavailable)" : headerFooterText)
            ---

            [SOURCE 3 — Last page (submission / acceptance / publication dates)]
            ---
            \(lastPageSnippet.isEmpty ? "(unavailable)" : lastPageSnippet)
            ---
            """

        let userContent: [[String: Any]] = [
            [
                "type": "text",
                "text": """
                \(sourceBlock)

                Is this a journal article (학술 논문)?

                A journal article typically has: title, author(s), abstract, journal name, DOI, volume/issue number.
                Not an article: textbook chapter, thesis, conference poster, report, presentation slides, 발제문, 발표문, 초고, class handout.

                For pub_year: look independently in all three sources above.
                - SOURCE 1: journal metadata at the top of the first page (volume, issue, year / DOI / copyright line)
                - SOURCE 2: running headers or footers (e.g. "Korean J. Edu. 2023, 40(2)")
                - SOURCE 3: phrases like "게재 확정일", "최종 게재일", "Accepted", "Published" followed by a date
                If two or more sources agree on a 4-digit year, return that year.
                If only one source has a year and the others are unavailable, return that year.
                If sources conflict, return the year from SOURCE 3 (publication/acceptance date is most authoritative).
                If no year is found anywhere, return "".

                Respond with JSON only (no markdown, no explanation):
                {
                  "is_journal_article": true,
                  "author": "Use the language of the paper's main body. Korean paper → Korean author names: (1) 1명: 성명 전체 (예: '홍길동'). (2) 2명: '저자1·저자2' (예: '홍길동·김철수'). (3) 3명 이상: 반드시 첫 번째 저자 이름만 쓰고 ' 외' 추가 (예: 저자가 홍길동·김철수·이영희이면 → '홍길동 외'). English paper → (1) 1 author: full name. (2) 2 authors: 'Name1 & Name2'. (3) 3+ authors: first author name only followed by ' et al.' (e.g. 'Smith et al.'). If both Korean and English names appear, use the Korean names.",
                  "main_title": "Use the language of the paper's main body. If both Korean and English titles appear (e.g. Korean body + English abstract at the end), use the KOREAN title. Main title ONLY — omit subtitles after ':', '—', or similar separators. If the Korean title has missing word spacing (words concatenated without spaces, which can happen in both scanned and older digital PDFs), restore proper Korean word spacing.",
                  "pub_year": "2023"
                }

                If NOT a journal article:
                {"is_journal_article": false, "author": "", "main_title": "", "pub_year": ""}
                """
            ]
        ]

        let (text, usage) = try await service.send(system: system, content: userContent)
        return (parseArticleJSON(text), usage)
    }

    // MARK: - Date line extraction

    /// 날짜 관련 키워드가 포함된 줄만 추출.
    /// - 한국어 키워드: 날짜가 다음 줄에 올 수 있으므로 ±1줄 포함
    /// - 영문 키워드: 날짜가 같은 줄에 있고, 컨텍스트를 넓히면 영문 초록의 제목 등이 딸려올 수 있으므로 해당 줄만 포함
    private func extractDateLines(from text: String) -> String {
        let koreanKeywords = ["접수", "수정", "게재", "심사", "투고", "발행", "출판"]
        let englishKeywords = ["received", "accepted", "published", "online", "revised", "submitted"]

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var result: [String] = []
        var added = Set<Int>()

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            let isKorean  = koreanKeywords.contains(where:  { lower.contains($0) })
            let isEnglish = englishKeywords.contains(where: { lower.contains($0) })
            guard isKorean || isEnglish else { continue }

            let range = isKorean
                ? max(0, i - 1)...min(lines.count - 1, i + 1)  // ±1줄
                : i...i                                          // 해당 줄만
            for j in range {
                if added.insert(j).inserted { result.append(lines[j]) }
            }
        }

        // 키워드가 전혀 없으면 마지막 200자만 fallback으로 전달
        return result.isEmpty ? String(text.suffix(200)) : result.joined(separator: "\n")
    }

    // MARK: - Vision OCR

    private func ocrPage(_ page: PDFPage) async -> String {
        guard let cgImage = renderPageToImage(page) else { return "" }

        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            guard (try? handler.perform([request])) != nil else { return "" }

            return request.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""
        }.value
    }

    /// Renders a PDF page to a CGImage using CoreGraphics (thread-safe).
    private func renderPageToImage(_ page: PDFPage) -> CGImage? {
        guard let cgPage = page.pageRef else { return nil }

        let rect = cgPage.getBoxRect(.mediaBox)
        let scale: CGFloat = 2.0
        let width = Int(rect.width * scale)
        let height = Int(rect.height * scale)
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(cgPage)

        return context.makeImage()
    }

    // MARK: - JSON parsing

    private func parseArticleJSON(_ text: String) -> ArticleInfo? {
        guard let data = extractJSON(from: text).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isArticle = json["is_journal_article"] as? Bool,
              isArticle else { return nil }

        let author = (json["author"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let title  = (json["main_title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let year   = (json["pub_year"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !author.isEmpty, !title.isEmpty else { return nil }

        return ArticleInfo(authorName: author, mainTitle: title, publicationYear: year)
    }

    private func extractJSON(from text: String) -> String {
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}
