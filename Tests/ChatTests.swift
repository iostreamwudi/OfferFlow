import Foundation
import AppKit
import WebKit

@MainActor final class ChatRunner: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    let adapter: String
    init(adapter: String) { self.adapter = adapter; super.init(); web.navigationDelegate = self }
    func start() {
        web.loadHTMLString("<html><body><input placeholder='搜索30天内的联系人'><section><h2>测试公司</h2><h3 class='job-name'>AI产品经理</h3><div contenteditable='true'></div><button onclick='window.sent=true'>发送</button></section></body></html>", baseURL: URL(string: "https://www.zhipin.com/web/geek/chat?jobId=abc"))
    }
    func action(_ operation: String, id: String = "abc", overwrite: Bool = false, cleanURL: Bool = false, text: String = "您好，我有相关项目经历，希望进一步交流。") async throws -> String {
        let args: [String: Any] = ["operation": operation, "jobURL": "https://www.zhipin.com/job_detail/\(id).html", "company": "测试公司", "title": "AI产品经理", "text": text, "overwrite": overwrite]
        let json = String(data: try JSONSerialization.data(withJSONObject: args), encoding: .utf8)!
        let script = adapter.replacingOccurrences(of: "location.href", with: cleanURL ? "'https://www.zhipin.com/web/geek/chat'" : "'https://www.zhipin.com/web/geek/chat?jobId=abc'")
        let value = try await web.evaluateJavaScript("(\(script))(\(json))") as! [String: Any]
        return value["status"] as! String
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                let wrong = try await action("fill", id: "other")
                precondition(wrong == "wrong_conversation")
                let fill = try await action("fill")
                precondition(fill == "filled")
                let cleanURL = try await action("fill", cleanURL: true)
                precondition(cleanURL == "filled")
                let captured = try await action("capture", cleanURL: true)
                precondition(captured == "captured")
                let capturedText = try await web.evaluateJavaScript("document.querySelector('[contenteditable]').innerText") as! String
                precondition(capturedText == "您好，我有相关项目经历，希望进一步交流。")
                let sent = try await web.evaluateJavaScript("Boolean(window.sent)") as! Bool
                precondition(!sent)
                _ = try await web.evaluateJavaScript("document.querySelector('[contenteditable]').textContent='用户自己的草稿'")
                let occupied = try await action("fill")
                precondition(occupied == "occupied")
                let replace = try await action("fill", overwrite: true)
                precondition(replace == "filled")
                let multiline = "您好，关注贵公司。\n\n项目匹配优势。\n每周实习5天，连续6个月。"
                // Same words with flattened whitespace must not count as a filled draft.
                _ = try await action("fill", overwrite: true, text: multiline.replacingOccurrences(of: "\n", with: " "))
                let flattened = try await action("fill", text: multiline)
                precondition(flattened == "occupied")
                let sendMismatch = try await action("batchSend", text: multiline)
                precondition(sendMismatch == "draft_changed")
                for text in [multiline, "首行\n末行\n", "\n开头空行\n\n结尾", "文字 <script>window.sent=true</script> & 符号\n第二行"] {
                    let status = try await action("fill", overwrite: true, text: text)
                    precondition(status == "filled")
                    let rendered = try await web.evaluateJavaScript("document.querySelector('[contenteditable]').innerText") as! String
                    precondition(rendered == text, "Line breaks changed")
                }
                let stillUnsent = try await web.evaluateJavaScript("Boolean(window.sent)") as! Bool
                precondition(!stillUnsent)
                print("PASS multiline/blank/trailing lines, literal HTML, formatting mismatch and zero sends")
                _ = try await web.evaluateJavaScript("document.querySelector('h2').textContent='另一个公司'")
                let identity = try await action("fill")
                precondition(identity == "identity_unverified")
                print("PASS chat identity verification, draft fill, existing draft protection, explicit replacement, and zero sends")
                exit(0)
            } catch { print("FAIL chat tests: \(error.localizedDescription)"); exit(1) }
        }
    }
}
@main struct ChatTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let sample: [String: Any] = ["status":"completed", "model":"test", "output":[["type":"message","content":[["type":"output_text","text":"{\"greeting\":\"您好，我有RAG项目经验，希望进一步沟通。\",\"evidence\":[{\"requirement\":\"RAG应用\",\"resume_quote\":\"负责RAG检索优化\"}]}" ]]]]]
        let data = try JSONSerialization.data(withJSONObject: sample)
        _ = try ArkClient.parseOutput(data, resume: "负责RAG检索优化", jd: "负责RAG应用")
        do { _ = try ArkClient.parseOutput(data, resume: "并没有相关经历", jd: "负责RAG应用"); preconditionFailure("Invented evidence must fail") } catch AIError.message {}
        print("PASS real-response parsing and fabricated-evidence rejection")
        let sources = EvidenceSources(resume: "负责RAG检索优化\n主导产品需求评审", jd: "负责RAG应用\n推动跨团队产品交付")
        func referenced(_ resumeID: String, _ requirementID: String = "J1") throws -> Data {
            let content: [String: Any] = ["greeting": "您好，我有RAG项目经验，希望进一步沟通。", "evidence": [["requirement_id": requirementID, "resume_id": resumeID]]]
            let text = String(data: try JSONSerialization.data(withJSONObject: content), encoding: .utf8)!
            return try JSONSerialization.data(withJSONObject: ["status":"completed", "output":[["content":[["type":"output_text","text":text]]]]])
        }
        let indexed = try ArkClient.parseOutput(referenced("R1"), resume: sources.resume.joined(separator: "\n"), jd: sources.jd.joined(separator: "\n"), sources: sources)
        precondition(indexed.result.evidence[0].resume_quote == "负责RAG检索优化")
        precondition(indexed.result.evidence[0].requirement == "负责RAG应用")
        for invalid in ["R0", "R999", "J1", "R01", "R1.extra"] {
            do { _ = try ArkClient.parseOutput(referenced(invalid), resume: sources.resume.joined(), jd: sources.jd.joined(), sources: sources); preconditionFailure("Invalid source ID accepted") } catch AIError.message {}
        }
        do { _ = try ArkClient.parseOutput(referenced("R1", "R1"), resume: sources.resume.joined(), jd: sources.jd.joined(), sources: sources); preconditionFailure("Cross-source ID accepted") } catch AIError.message {}
        do { _ = try ArkClient.parseOutput(referenced("R1"), resume: "其他材料", jd: sources.jd.joined(), sources: sources); preconditionFailure("Mismatched source accepted") } catch AIError.message {}
        print("PASS indexed evidence restores exact original text, rejects fabricated IDs, cross-source IDs, and mismatched materials")
        var book = JobGreetingBook()
        let a = Job(title: "岗位A", company: "公司A", city: "上海", salary: "20K", experience: "1年", tags: [], jd: "JD A", sourceURL: "https://www.zhipin.com/job_detail/a.html")
        let b = Job(title: "岗位B", company: "公司B", city: "上海", salary: "20K", experience: "1年", tags: [], jd: "JD B", sourceURL: "https://www.zhipin.com/job_detail/b.html")
        let original = GeneratedGreeting(greeting: "A的模型草稿", evidence: [])
        let response = AIResponse(result: original, model: "test", inputTokens: 10, outputTokens: 10)
        book.save(job: a, response: response, editorText: "A在BOSS里手动修改的草稿", filled: true)
        book.save(job: b, response: AIResponse(result: GeneratedGreeting(greeting: "B的模型草稿", evidence: []), model: "test", inputTokens: 20, outputTokens: 20))
        book.save(job: a, response: response)
        let restored = try JSONDecoder().decode(JobGreetingBook.self, from: JSONEncoder().encode(book))
        precondition(restored.entries.count == 2)
        precondition(restored.draft(for: a.sourceURL!)!.editorText == "A在BOSS里手动修改的草稿")
        precondition(restored.draft(for: b.sourceURL!)!.result.greeting == "B的模型草稿")
        precondition(restored.draft(for: a.sourceURL!)!.filled)
        precondition(restored.draft(for: a.sourceURL!)!.generatedAt != nil && restored.draft(for: a.sourceURL!)!.filledAt != nil)
        let historical = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored.draft(for: a.sourceURL!)!)) as! [String: Any]
        var legacy = historical; legacy.removeValue(forKey: "generatedAt"); legacy.removeValue(forKey: "filledAt")
        let oldDraft = try JSONDecoder().decode(JobGreetingDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldDraft.filled && oldDraft.generatedAt == nil && oldDraft.filledAt == nil)
        print("PASS per-job draft isolation, user edits preserved, and restoration after serialization")
        let runner = ChatRunner(adapter: try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8))
        runner.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("FAIL chat tests timed out"); exit(1) }
        withExtendedLifetime(runner) { RunLoop.main.run() }
    }
}
