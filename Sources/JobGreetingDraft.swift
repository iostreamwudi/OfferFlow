import Foundation

struct JobGreetingDraft: Codable {
    var greetingConfiguration: String? = nil
    var job: Job
    var result: GeneratedGreeting
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var editorText: String?
    var generatedAt: Date?
    var filledAt: Date?
    var filled = false
    var updatedAt = Date()
    var response: AIResponse { AIResponse(greetingConfiguration: greetingConfiguration, result: result, model: model, inputTokens: inputTokens, outputTokens: outputTokens) }
    var card: BossCard { BossCard(title: job.title, company: job.company, city: job.city, salary: job.salary, experience: job.experience, tags: job.tags, url: job.sourceURL ?? "") }
}

struct JobGreetingBook: Codable {
    var entries: [String: JobGreetingDraft] = [:]
    mutating func save(job: Job, response: AIResponse, editorText: String? = nil, filled: Bool = false) {
        guard let raw = job.sourceURL, let key = BossSite.canonical(raw) else { return }
        let previous = entries[key]
        let sameConfiguration = (previous?.greetingConfiguration ?? "ai") == (response.greetingConfiguration ?? "ai")
        entries[key] = JobGreetingDraft(greetingConfiguration: response.greetingConfiguration, job: job, result: response.result, model: response.model,
            inputTokens: response.inputTokens, outputTokens: response.outputTokens,
            editorText: editorText ?? (sameConfiguration ? previous?.editorText : nil), generatedAt: previous == nil || !sameConfiguration ? Date() : previous?.generatedAt, filledAt: previous?.filledAt ?? (filled ? Date() : nil), filled: filled || (previous?.filled ?? false))
    }
    func draft(for url: String) -> JobGreetingDraft? {
        guard let key = BossSite.canonical(url) else { return nil }
        return entries[key]
    }
}
