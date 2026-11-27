import Foundation

extension Store {
    /// URL alone is not a job identity: a recruitment page can contain many roles.
    @discardableResult func trackApplication(company: String, role: String, url: String, jd: String = "") -> String? {
        let company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !company.isEmpty, !role.isEmpty, LiveJobListing.safeHTTPURL(url) != nil else { notice = "请填写公司和具体岗位。"; return nil }
        if let match = jobs.first(where: { $0.company == company && $0.title == role && $0.sourceURL == url }) {
            if applications[match.id] == nil, !updateApplication(match.id, stage: .planned, notes: "", followUpAt: nil) { return nil }
            selected = match.id; return match.id
        }
        let job = Job(title: role, company: company, city: "", salary: "", experience: "", tags: [], jd: jd, source: "企业网申", sourceURL: url)
        add(job)
        guard updateApplication(job.id, stage: .planned, notes: "", followUpAt: nil) else { return nil }
        return job.id
    }
    func recordFormProgress(_ id: String, state: String, resumeVersion: String) {
        guard var record = applications[id] else { return }
        record.formState = state; record.resumeVersion = resumeVersion; record.updatedAt = Date()
        applications[id] = record; persist()
    }
}


/// Company/project context can be carried through browsing without creating a record.
enum ApplicationRecording {
    static func roleChoices(_ text: String) -> [String] {
        var depth = 0, buffer = "", result: [String] = []
        for character in text {
            if "(（[【".contains(character) { depth += 1 }
            if ")）]】".contains(character) { depth = max(0, depth - 1) }
            if depth == 0 && "、；;，,\n".contains(character) {
                let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { result.append(value) }; buffer = ""
            } else { buffer.append(character) }
        }
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { result.append(value) }
        var seen = Set<String>(); return result.filter { seen.insert($0).inserted }
    }
}
