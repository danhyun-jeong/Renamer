import Foundation

/// 파일 이름 템플릿 파서 및 렌더러.
///
/// 포스터 변수: {title}  {when: FORMAT}
/// 논문 변수:  {name}  {year}  {title}
///
/// FORMAT 토큰 (앞에서부터 가장 긴 것 우선 적용):
///   YYYY → 4자리 연도   YY → 2자리 연도
///   MM   → 2자리 월(선행 0)  M → 월(선행 0 없음)
///   DD   → 2자리 일(선행 0)  D → 일(선행 0 없음)
///   그 외 문자 → 그대로 출력
///
/// 빈 값 처리: 변수가 빈 문자열로 치환된 뒤 남은 빈 괄호 쌍 () [] 을 제거.
enum NameTemplate {
    static let defaultPosterTemplate  = "(포스터){title}({when: YYMMDD})"
    static let defaultArticleTemplate = "{name}({year}), {title}"

    // MARK: - Poster

    static func renderPoster(template: String, info: PosterInfo) -> String {
        var result = template

        // {when: FORMAT} 처리 — 포맷 문자열을 추출해 날짜 조합
        let whenRegex = try! NSRegularExpression(pattern: #"\{when:\s*([^}]+?)\s*\}"#)
        let nsRange = NSRange(result.startIndex..., in: result)
        for match in whenRegex.matches(in: result, range: nsRange).reversed() {
            guard let fullRange = Range(match.range,      in: result),
                  let fmtRange  = Range(match.range(at: 1), in: result) else { continue }
            let format  = String(result[fmtRange])
            let dateStr = formatDate(year: info.year, month: info.month, day: info.day, format: format)
            result.replaceSubrange(fullRange, with: dateStr)
        }

        result = result.replacingOccurrences(of: "{title}", with: info.eventTitle)
        return cleanupEmpty(result)
    }

    // MARK: - Article

    static func renderArticle(template: String, info: ArticleInfo) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{name}",  with: info.authorName)
        result = result.replacingOccurrences(of: "{year}",  with: info.publicationYear)
        result = result.replacingOccurrences(of: "{title}", with: info.mainTitle)
        return cleanupEmpty(result)
    }

    // MARK: - Date formatting

    static func formatDate(year: String, month: String, day: String, format: String) -> String {
        guard !year.isEmpty || !month.isEmpty || !day.isEmpty else { return "" }

        var out = ""
        var i = format.startIndex
        while i < format.endIndex {
            let rem = format[i...]
            if rem.hasPrefix("YYYY") {
                out += year
                i = format.index(i, offsetBy: 4)
            } else if rem.hasPrefix("YY") {
                out += year.count >= 2 ? String(year.suffix(2)) : year
                i = format.index(i, offsetBy: 2)
            } else if rem.hasPrefix("MM") {
                out += month
                i = format.index(i, offsetBy: 2)
            } else if format[i] == "M" {
                out += String(Int(month) ?? 0)
                i = format.index(after: i)
            } else if rem.hasPrefix("DD") {
                out += day
                i = format.index(i, offsetBy: 2)
            } else if format[i] == "D" {
                out += String(Int(day) ?? 0)
                i = format.index(after: i)
            } else {
                out += String(format[i])
                i = format.index(after: i)
            }
        }
        return out
    }

    // MARK: - Cleanup

    /// 빈 값 치환 후 남은 빈 괄호 쌍을 제거.
    /// 반복 적용해 중첩된 경우도 처리.
    private static func cleanupEmpty(_ str: String) -> String {
        var result = str
        for pattern in [#"\(\s*\)"#, #"\[\s*\]"#] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            var prev = ""
            while prev != result {
                prev = result
                result = re.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
