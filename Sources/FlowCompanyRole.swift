import Foundation

enum FlowCompanyRole {
    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN")).filter { !$0.isWhitespace && !$0.isPunctuation }
    }
    static func company(_ value: String) -> String {
        var value = normalize(value)
        for suffix in ["股份有限公司", "有限责任公司", "有限公司"] where value.hasSuffix(suffix) { value = String(value.dropLast(suffix.count)) }
        let aliases = ["bytedance": "字节跳动", "字节": "字节跳动", "tencent": "腾讯", "baidu": "百度", "alibaba": "阿里巴巴", "阿里": "阿里巴巴", "meituan": "美团", "kuaishou": "快手", "xiaohongshu": "小红书"]
        return aliases[value] ?? value
    }
    static func companyMatches(_ candidate: String, query: String) -> Bool {
        let key = company(query)
        if key.isEmpty { return true }
        if company(candidate).contains(key) { return true }
        let families = [["字节跳动", "字节", "bytedance"], ["腾讯", "tencent"], ["百度", "baidu"], ["阿里巴巴", "阿里", "alibaba"], ["美团", "meituan"], ["快手", "kuaishou"], ["小红书", "xiaohongshu"]]
        return families.first(where: { $0.contains(key) })?.contains(where: { normalize(candidate).contains($0) }) == true
    }
    static func role(_ value: String) -> String {
        var value = normalize(value)
        for (a,b) in [("人工智能", "ai"), ("aipm", "ai产品经理"), ("产品pm", "产品经理"), ("产品经理pm", "产品经理"), ("productmanager", "产品经理")] { value = value.replacingOccurrences(of: a, with: b) }
        if value == "pm" { value = "产品经理" }
        return value
    }
}

