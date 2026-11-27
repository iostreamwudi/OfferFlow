import Foundation

// Snapshots preserve the actual source used for a session, even if its note is edited later.
struct CoachSourceQuestion: Codable, Identifiable, Equatable {
    var id: String
    var noteID: String
    var title: String
    var url: String
    var original: String
    var intent: String
    var mode: String?
    var round: String
}
enum CoachSources {
    static let rounds = ["不限轮次", "一面", "二面", "三面", "四面", "终面", "HR面"]
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN")).filter { !$0.isWhitespace && !$0.isPunctuation }
    }
    static func matches(_ note: InterviewNote, company: String, role: String) -> Bool {
        let companyCandidate = note.sourceCompany?.isEmpty == false ? note.sourceCompany! : note.title
        let roleCandidate = note.sourceRole?.isEmpty == false ? note.sourceRole! : note.title
        return FlowCompanyRole.companyMatches(companyCandidate, query: company) &&
            (FlowCompanyRole.role(role).isEmpty || FlowCompanyRole.role(roleCandidate).contains(FlowCompanyRole.role(role)))
    }
    private static let roundPattern = try! NSRegularExpression(pattern: "(?i)(第?[一二三四1234]轮(?:面试)?|第?[一二三四1234]面|终面|HR\\s*面(?:试)?)")
    static func roundMarkers(_ text: String) -> [(NSRange, String)] {
        let ns = text as NSString
        return roundPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { item in
            let value = ns.substring(with: item.range).uppercased()
            let round: String
            if value.contains("HR") { round = "HR面" }
            else if value.contains("终") { round = "终面" }
            else if value.contains("一") || value.contains("1") { round = "一面" }
            else if value.contains("二") || value.contains("2") { round = "二面" }
            else if value.contains("三") || value.contains("3") { round = "三面" }
            else { round = "四面" }
            return (item.range, round)
        }
    }
    static func round(for question: InterviewQuestion, in note: InterviewNote) -> String {
        if let explicit = question.interviewRound, rounds.contains(explicit), explicit != rounds[0] { return explicit }
        let segment = note.segments.first { $0.id == question.segmentID }?.text ?? ""
        let location = (segment as NSString).range(of: question.original).location
        // Only headings identify a section; a question mentioning “一面” is not itself a heading.
        var offset = 0
        var preceding: String?
        for line in segment.components(separatedBy: "\n") {
            if offset >= location { break }
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let markers = roundMarkers(clean)
            if clean.count <= 55, markers.count == 1,
               let marker = markers.first, marker.0.location <= 10,
               !clean.contains("？"), !clean.contains("?") { preceding = marker.1 }
            offset += (line as NSString).length + 1
        }
        if let preceding { return preceding }
        if let explicit = note.sourceRound, rounds.contains(explicit), explicit != rounds[0] { return explicit }
        let titles = Set(roundMarkers(note.title).map { $0.1 })
        return titles.count == 1 ? titles.first! : "未标注"
    }
    static func pool(notes: [InterviewNote], company: String, role: String, round: String, includeUnlabeled: Bool = false) -> [CoachSourceQuestion] {
        notes.filter { matches($0, company: company, role: role) && $0.extractionIsCurrent }.flatMap { note in
            note.questions.compactMap { question in
                let questionRound = self.round(for: question, in: note)
                guard round == rounds[0] || round == questionRound || (includeUnlabeled && questionRound == "未标注") else { return nil }
                guard note.segments.contains(where: { $0.id == question.segmentID && $0.text.contains(question.original) }) else { return nil }
                return CoachSourceQuestion(id: note.id + ":" + question.id, noteID: note.id, title: note.title, url: note.sourceURL, original: question.original, intent: question.intent, mode: question.answerMode?.rawValue, round: questionRound)
            }
        }
    }
}
