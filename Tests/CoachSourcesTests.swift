import Foundation
@main struct CoachSourcesTests {
    static func main() throws {
        let q1 = InterviewQuestion(original: "解释检索增强生成的原理？", segmentID: "body", intent: "检索", reasoning: "原题", category: "知识", answerMode: .direct)
        let q2 = InterviewQuestion(original: "你如何评估自己项目的效果？", segmentID: "body", intent: "评估", reasoning: "原题", category: "项目", answerMode: .project)
        var note = InterviewNote(id: "n", title: "示例公司 AI 产品经理 一面与二面", sourceURL: "https://www.nowcoder.com/discuss/123", segments: [.init(id: "body", label: "正文", text: "一面\n" + q1.original + "\n二面\n" + q2.original)], questions: [q1, q2], sourceCompany: "示例公司", sourceRole: "AI 产品经理")
        note.extractedFingerprint = note.fingerprint
        func pool(_ round: String, company: String = "示例公司", role: String = "ai产品经理") -> [CoachSourceQuestion] { CoachSources.pool(notes: [note], company: company, role: role, round: round) }
        precondition(pool("一面").map(\.original) == [q1.original])
        precondition(pool("二面").map(\.original) == [q2.original])
        precondition(pool("不限轮次").count == 2)
        precondition(pool("三面").isEmpty)
        precondition(pool("不限轮次", company: "另一公司").isEmpty)
        precondition(pool("不限轮次", role: "后端工程师").isEmpty)
        note.title += " 提到了另一公司"
        precondition(pool("不限轮次", company: "另一公司").isEmpty, "explicit labels must outrank title mentions")
        let snapshot = pool("二面")[0]
        let restored = try JSONDecoder().decode(CoachSourceQuestion.self, from: JSONEncoder().encode(snapshot))
        precondition(restored == snapshot)
        note.segments[0].text += "\n修订"
        precondition(pool("不限轮次").isEmpty, "stale extraction cannot ground a session")
        note.extractedFingerprint = note.fingerprint
        note.questions[0].original = "模型编造但未出现在原文的问题"
        precondition(pool("不限轮次").count == 1)
        note.questions[0] = q1
        note.segments[0].text = q1.original + "\n" + q2.original
        note.title = "示例公司 AI 产品经理 一面"
        note.extractedFingerprint = note.fingerprint
        precondition(pool("一面").count == 2)
        note.sourceRound = "三面"
        precondition(pool("三面").count == 2)
        note.title = "ByteDance AI PM 面经"; note.sourceCompany = "字节跳动"; note.sourceRole = "人工智能产品经理"; note.sourceRound = nil
        note.extractedFingerprint = note.fingerprint
        precondition(CoachSources.pool(notes: [note], company: "字节", role: "AI PM", round: "一面").isEmpty)
        precondition(CoachSources.pool(notes: [note], company: "bytedance", role: "AI PM", round: "一面", includeUnlabeled: true).count == 2)
        precondition(CoachSources.pool(notes: [note], company: "腾讯", role: "AI PM", round: "不限轮次").isEmpty)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as! [String: Any]
        legacy.removeValue(forKey: "sourceRound")
        let decoded = try JSONDecoder().decode(InterviewNote.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(decoded.sourceRound == nil && decoded.questions.count == 2)
        print("PASS company/role normalization, explicit metadata, mixed rounds, fallback, source validation, stale extraction, snapshots and legacy notes")
    }
}
