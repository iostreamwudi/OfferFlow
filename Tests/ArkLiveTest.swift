import Foundation

@main struct ArkLiveTest {
    @MainActor static func main() async {
        do {
            let folder = LocalAIStorage.directory
            guard let resume = LocalAIStorage.read("resume.json", as: ResumeMaterial.self) else { throw AIError.message("未导入简历") }
            let snapshot = try JSONDecoder().decode(Store.Snapshot.self, from: Data(contentsOf: folder.appendingPathComponent("workspace.json")))
            guard let job = snapshot.jobs.first(where: { $0.sourceURL?.contains("4bb2203e2d31a7f20nx82d68F1tZ") == true }) else { throw AIError.message("缺少测试岗位") }
            let response = try await ArkClient.generate(job: job, resume: resume, settings: LocalAIStorage.read("ark-settings.json", as: ArkSettings.self) ?? ArkSettings(), key: LocalAIStorage.key())
            try LocalAIStorage.save(response.result, name: "last-ai-test.json")
            print("模型：\(response.model)；input tokens：\(response.inputTokens)，output tokens：\(response.outputTokens)")
            print("打招呼语：\(response.result.greeting)")
            print("原文引用核验通过：\(response.result.evidence.count)条。未执行任何 BOSS 发送操作。")
        } catch { print("真实模型测试失败：\(error.localizedDescription)"); exit(1) }
    }
}
