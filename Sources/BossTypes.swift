import Foundation

enum BossSite {
    static let cities = ["全国", "上海", "北京", "深圳", "广州", "杭州", "成都", "苏州", "南京", "武汉", "西安"]
    static let codes = ["全国": "100010000", "上海": "101020100", "北京": "101010100", "深圳": "101280600", "广州": "101280100", "杭州": "101210100", "成都": "101270100", "苏州": "101190400", "南京": "101190100", "武汉": "101200100", "西安": "101110100"]
    static func isBoss(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        return host == "zhipin.com" || host.hasSuffix(".zhipin.com")
    }
    static func searchURL(keyword: String, city: String) -> URL {
        var parts = URLComponents(string: "https://www.zhipin.com/web/geek/jobs")!
        parts.queryItems = [URLQueryItem(name: "query", value: keyword.trimmingCharacters(in: .whitespacesAndNewlines)), URLQueryItem(name: "city", value: codes[city] ?? codes["全国"]!)]
        return parts.url!
    }
    static func canonical(_ value: String) -> String? {
        guard let url = URL(string: value), isBoss(url), ["www.zhipin.com", "m.zhipin.com", "zhipin.com"].contains(url.host ?? ""),
              url.path.range(of: #"^/job_detail/[\w~-]+\.html$"#, options: .regularExpression) != nil else { return nil }
        return "https://www.zhipin.com" + url.path
    }
}

struct BossCard: Codable, Identifiable {
    var title: String
    var company: String
    var city: String
    var salary: String
    var experience: String
    var tags: [String]
    var url: String
    var id: String { url }
}

struct BossDetail: Decodable {
    var title: String
    var company: String
    var jd: String
    var url: String
    var complete: Bool
    var salary: String?
    var city: String?
    var experience: String?
}

struct BossReadResult: Decodable {
    var pageURL: String
    var gated: Bool
    var cards: [BossCard]
    var detail: BossDetail?
    var previewURL: String?
}

enum BossDraftError: LocalizedError {
    case verification, noDetail, incomplete, mismatched
    var errorDescription: String? {
        switch self {
        case .verification: return "BOSS 要求安全验证，请在右侧自行完成后再读取。"
        case .noDetail: return "请先在右侧打开一个岗位详情，或在左侧选择岗位。"
        case .incomplete: return "尚未读到完整 JD。请登录、展开完整描述，等待内容显示后重新读取。"
        case .mismatched: return "岗位原链接与当前页面不一致，请重新打开详情后读取。"
        }
    }
}

enum BossDraftBuilder {
    static func make(_ result: BossReadResult, cards: [BossCard], fallbackCity: String) throws -> Job {
        guard !result.gated else { throw BossDraftError.verification }
        guard let detail = result.detail else { throw BossDraftError.noDetail }
        guard let url = BossSite.canonical(detail.url), url == BossSite.canonical(result.pageURL) else { throw BossDraftError.mismatched }
        guard detail.complete, !detail.jd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BossDraftError.incomplete }
        let card = cards.first { BossSite.canonical($0.url) == url }
        let area = detail.city.flatMap { $0.isEmpty ? nil : $0 } ?? card?.city ?? fallbackCity
        let salary = detail.salary.flatMap { $0.isEmpty ? nil : $0 } ?? card?.salary ?? ""
        let experience = card?.experience.isEmpty == false ? card!.experience : detail.experience ?? ""
        return Job(title: detail.title.isEmpty ? card?.title ?? "" : detail.title,
                   company: detail.company.isEmpty ? card?.company ?? "" : detail.company,
                   city: String(area.components(separatedBy: "·").first ?? area),
                   salary: salary.isEmpty ? "薪资未能读取，请查看原岗位" : salary,
                   experience: experience.isEmpty ? "以 JD 为准" : experience,
                   tags: Analysis.vocabulary.filter { Analysis.contains(detail.jd, $0) }, jd: detail.jd,
                   source: "BOSS 直聘", colorIndex: 0, sourceURL: url, fetchedAt: Date())
    }
}
