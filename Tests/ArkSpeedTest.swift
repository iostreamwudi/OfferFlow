import Foundation
@main struct ArkSpeedTest {
    @MainActor static func main() async throws {
        let resume = LocalAIStorage.read("resume.json", as: ResumeMaterial.self)!
        let snapshot = try JSONDecoder().decode(Store.Snapshot.self, from: Data(contentsOf: LocalAIStorage.directory.appendingPathComponent("workspace.json")))
        let job = snapshot.jobs.first { $0.company == "记忆张量" && !$0.jd.isEmpty }!
        let start = Date()
        do {
            let response = try await ArkClient.generate(job: job, resume: resume, settings: LocalAIStorage.read("ark-settings.json", as: ArkSettings.self)!, key: LocalAIStorage.key())
            print("seconds=\(String(format: "%.2f", Date().timeIntervalSince(start))) input=\(response.inputTokens) output=\(response.outputTokens) characters=\(response.result.greeting.count) verified=\(response.result.evidence.count)")
            // Personal content remains in the restricted application data directory.
            try LocalAIStorage.save(response.result, name: "speed-test-\(CommandLine.arguments.last ?? "result").json")
        } catch { print("seconds=\(String(format: "%.2f", Date().timeIntervalSince(start))) error=\(error.localizedDescription)"); exit(1) }
    }
}
