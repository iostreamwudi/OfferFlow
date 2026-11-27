import Foundation
import SwiftUI
import AppKit
import WebKit

extension BossSession {
    func restoreBatchBook() {
        let url = LocalAIStorage.directory.appendingPathComponent("boss-batch-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            var restored = try JSONDecoder().decode(BossBatchBook.self, from: Data(contentsOf: url))
            for index in restored.items.indices {
                switch restored.items[index].state {
                case .sending:
                    restored.items[index].state = .uncertain
                    restored.items[index].detail = "上次退出时正在发送，请在 BOSS 核对；不会自动重发。"
                case .queued, .reading, .generating, .opening:
                    restored.items[index].state = .stopped
                    restored.items[index].detail = "上次任务已中断；重新点击批量投递可处理尚未发送的公司。"
                default: break
                }
            }
            try restored.persist()
            batchBook = restored
        } catch { batchLoadError = "批量记录无法读取或保存，已停用批量投递，以免重复发送。请检查本机存储。" }
    }

    func saveBatchItem(_ id: String, state: BossBatchState, detail: String = "", job: Job? = nil, greeting: String? = nil) throws {
        guard let index = batchBook.items.firstIndex(where: { $0.id == id }) else { throw AIError.message("批量任务记录缺失。") }
        // Update memory first: even a disk failure must retain an uncertain send in this session.
        batchBook.items[index].state = state
        batchBook.items[index].detail = detail
        batchBook.items[index].updatedAt = Date()
        if let job { batchBook.items[index].job = job }
        if let greeting { batchBook.items[index].greeting = greeting }
        do { try batchBook.persist() }
        catch {
            batchLoadError = "批量记录保存失败，任务已停止；请核对最后一项发送结果后再处理存储问题。"
            throw error
        }
    }

    func stopBatch() {
        guard batchRunning else { return }
        batchStopping = true
        // An in-flight send must finish observation; cancelling it would lose the result.
        if !batchBook.current.contains(where: { $0.state == .sending }) { batchTask?.cancel() }
        communicationStatus = "正在停止；如已点击发送，会先记录当前项的发送结果。"
    }

    func checkBatchContinuation() throws {
        try Task.checkCancellation()
        if batchStopping { throw CancellationError() }
    }

    func resolveBatchResult(_ id: String, sent: Bool) {
        guard !batchRunning, batchLoadError.isEmpty,
              let item = batchBook.items.first(where: { $0.id == id }), item.state == .uncertain else { return }
        do {
            try saveBatchItem(id, state: sent ? .sent : .failed,
                              detail: sent ? "用户已在 BOSS 核对并确认已发送。" : "用户已在 BOSS 核对并确认未发送；再次点击批量投递时可重新处理。")
            if sent, let job = item.job {
                guard store?.recordActivity(job: job, stage: .drafted) == true, store?.confirmSent(job) == true else {
                    throw AIError.message("核对结果已保留，求职管理更新失败；不会重复发送。")
                }
            }
        } catch { say(error.localizedDescription, error: true) }
    }

    func syncBatchSentRecords() {
        guard let store else { return }
        for item in batchBook.items where item.state == .sent {
            guard let job = item.job, store.application(for: job)?.sentAt == nil else { continue }
            if store.recordActivity(job: job, stage: .drafted), !store.confirmSent(job) {
                say("批量发送记录已保留，但求职管理同步失败，请检查本机存储。", error: true)
            }
        }
    }

    func startBatch(_ source: [BossCard], onePerCompany: Bool = true, skipContactedCompany: Bool = false) {
        guard !batchRunning, !communicating, batchLoadError.isEmpty, !source.isEmpty else { return }
        guard let store else { say("求职管理尚未就绪。", error: true); return }
        do {
            let greetingContext = try BossGreetingContext()
            let prepared = BossBatchPolicy.prepare(source, book: batchBook, jobs: store.jobs, applications: store.applications, onePerCompany: onePerCompany, skipContactedCompany: skipContactedCompany)
            var next = batchBook
            next.currentIDs = prepared.map(\.id)
            next.items += prepared
            try next.persist()
            batchBook = next
            selectionTask?.cancel(); selectionTicket = UUID(); cancelCommunication()
            batchRunning = true; batchStopping = false; isError = false
            webView.window?.makeFirstResponder(nil)
            let queue = next.current.filter { $0.state == .queued }
            batchTask = Task { [weak self] in
                guard let self else { return }
                defer {
                    self.batchRunning = false; self.batchStopping = false; self.batchTask = nil
                    let current = self.batchBook.current
                    self.communicationStatus = "批量任务结束：已发送 \(current.filter { $0.state == .sent }.count)，待核对 \(current.filter { $0.state == .uncertain }.count)，跳过 \(current.filter { $0.state == .skipped }.count)，未完成 \(current.filter { [BossBatchState.failed, .stopped, .queued].contains($0.state) }.count)。"
                }
                await self.preserveCurrentGreeting()
                for (offset, item) in queue.enumerated() {
                    do {
                        try self.checkBatchContinuation()
                        self.communicationStatus = "批量投递 \(offset + 1)/\(queue.count) · \(item.card.company) · \(item.card.title)"
                        try await self.processBatchItem(item, context: greetingContext)
                        try self.checkBatchContinuation()
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } catch {
                        let state = self.batchBook.items.first(where: { $0.id == item.id })?.state
                        if state == .sending {
                            try? self.saveBatchItem(item.id, state: .uncertain, detail: "发送动作已开始，但结果无法确认。请在 BOSS 核对，不自动重试。")
                        } else if state != .sent && state != .skipped && state != .uncertain && state != .failed {
                            try? self.saveBatchItem(item.id, state: error is CancellationError ? .stopped : .failed, detail: error is CancellationError ? "用户停止任务，未点击发送。" : error.localizedDescription)
                        }
                        // Stop on unknown page, verification, or persistence errors. No blind retry loop.
                        self.batchStopping = true
                        break
                    }
                }
                for item in self.batchBook.current where item.state == .queued {
                    try? self.saveBatchItem(item.id, state: .stopped, detail: "任务停止，尚未处理；再次点击批量投递可继续未发送的公司。")
                }
            }
        } catch { say(error.localizedDescription, error: true) }
    }

    func processBatchItem(_ item: BossBatchItem, context: BossGreetingContext) async throws {
        guard let raw = BossSite.canonical(item.card.url), let url = URL(string: raw) else { throw AIError.message("岗位链接无效。") }
        try saveBatchItem(item.id, state: .reading)
        selectedCard = item.card; generatedGreeting = nil; communicationJob = nil
        load(url)
        let job = try await waitForJob(raw)
        try checkBatchContinuation()
        guard BossSite.canonical(job.sourceURL ?? "") == raw,
              BossBatchBook.companyKey(job.company) == BossBatchBook.companyKey(item.card.company),
              BossBatchBook.companyKey(job.title) == BossBatchBook.companyKey(item.card.title) else {
            throw AIError.message("详情与列表中的公司或岗位不一致，请人工核对。")
        }
        communicationJob = job; draft = job
        let readiness = try await chatAction("batchPreflight", job: job, text: "")
        if readiness == "already_contacted" {
            try saveBatchItem(item.id, state: .skipped, detail: "BOSS 显示已沟通过，不重复打招呼。", job: job); return
        }
        guard readiness == "ready" else { throw AIError.message("BOSS 沟通入口尚不可用（\(readiness)），请核对登录、验证码或平台提示。") }
        try saveBatchItem(item.id, state: .generating, job: job)
        let response: AIResponse
        do { response = try await context.generate(job: job) }
        catch {
            try checkBatchContinuation()
            try saveBatchItem(item.id, state: .failed, detail: "定制生成未完成：\(error.localizedDescription)")
            return // Model failure affects only this company; never send a generic fallback.
        }
        try checkBatchContinuation()
        guard !response.result.greeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.message("生成内容为空，停止发送。") }
        generatedGreeting = response
        cacheGreeting(job: job, response: response)
        guard store?.recordActivity(job: job, stage: .drafted) == true else { throw AIError.message("求职管理记录保存失败，停止发送。") }
        try saveBatchItem(item.id, state: .opening, job: job, greeting: response.result.greeting)
        try checkBatchContinuation()
        guard try await chatAction("batchOpen", job: job, text: "") == "opening" else { throw AIError.message("岗位页面已变化或已有沟通，请核对后再继续。") }
        var ready = false
        for _ in 0..<40 {
            try checkBatchContinuation()
            let status = try await chatAction("batchProbe", job: job, text: response.result.greeting)
            if status == "ready" { ready = true; break }
            if status == "occupied" || status == "already_contacted" {
                try saveBatchItem(item.id, state: .skipped, detail: "聊天中已有消息或其他草稿，保留原内容。")
                return
            }
            if status == "gated" { throw AIError.message("BOSS 要求验证或提示沟通限制，请处理后再继续。") }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        guard ready else { throw AIError.message("未能可靠核对目标聊天，未发送。") }
        guard try await chatAction("batchFill", job: job, text: response.result.greeting) == "filled" else { throw AIError.message("未能填入目标聊天，未发送。") }
        try checkBatchContinuation()
        cacheGreeting(job: job, response: response, text: response.result.greeting, filled: true)
        webView.window?.makeFirstResponder(nil)
        // Write-ahead record MUST succeed before the only send action in this task.
        try saveBatchItem(item.id, state: .sending, detail: "正在触发一次发送，并等待页面结果。")
        try checkBatchContinuation()
        let status = try await chatAction("batchSend", job: job, text: response.result.greeting)
        guard status == "send_started" else {
            // Script explicitly reports it did not click. A thrown JS/navigation error stays uncertain.
            try saveBatchItem(item.id, state: .failed, detail: "发送前核对未通过（\(status)），未点击发送。")
            throw AIError.message("发送前核对未通过，请检查当前 BOSS 页面。")
        }
        // Do not honour stop until this in-flight send has an observed result or times out.
        var observations = 0
        for _ in 0..<24 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let result = try await chatAction("batchReceipt", job: job, text: response.result.greeting)
            if result == "sent_visible" { observations += 1 } else { observations = 0 }
            if result == "send_failed" { break }
            if observations >= 3 {
                try saveBatchItem(item.id, state: .sent, detail: "聊天页面连续显示本条已发送消息；不代表对方已读。")
                guard store?.confirmSent(job) == true else { throw AIError.message("消息已发送，求职管理更新失败；批量记录已保留，不会重发。") }
                return
            }
        }
        try saveBatchItem(item.id, state: .uncertain, detail: "已点击发送，但未取得可靠页面回显，请人工核对；不会自动重发。")
        throw AIError.message("当前消息结果待核对，已停止后续投递。")
    }
}

struct BossBatchReport: View {
    @ObservedObject var session: BossSession
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("批量投递记录").font(.title2.bold())
                Spacer()
                if session.batchRunning { Button("停止任务", role: .destructive) { session.stopBatch() }.disabled(session.batchStopping) }
                Button("关闭") { dismiss() }
            }
            Text("逐家公司读取完整 JD，按启动时的 AI 或手动模板设置准备并发送招呼。按启动时选择的岗位和同公司策略处理；已发送或结果待核对的岗位会跳过。附件简历仍由你在 BOSS 中发送。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if !session.batchLoadError.isEmpty { Text(session.batchLoadError).foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(session.batchBook.items.reversed()) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("\(item.card.company) · \(item.card.title)").bold(); Spacer(); Text(item.state.label).foregroundStyle(item.state == .sent ? Color.green : Color.secondary) }
                            if !item.detail.isEmpty { Text(item.detail).foregroundStyle(.secondary) }
                            if !item.greeting.isEmpty { Text(item.greeting).textSelection(.enabled) }
                            if item.state == .uncertain {
                                Text("先在 BOSS 查看实际聊天记录，再登记核对结果。")
                                    .font(.caption).foregroundStyle(.orange)
                                HStack {
                                    Button("打开岗位核对") {
                                        session.openDetail(item.card)
                                        dismiss()
                                    }
                                    Button("我已核对：已发送") { session.resolveBatchResult(item.id, sent: true) }
                                    Button("我已核对：未发送") { session.resolveBatchResult(item.id, sent: false) }
                                }.disabled(session.batchRunning || !session.batchLoadError.isEmpty)
                            }
                            Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }.font(.system(size: 12)).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }.padding(24).frame(width: 760, height: 620)
    }
}
