import SwiftUI

struct CareerCalendarChange: Codable, Identifiable {
  var id = UUID().uuidString
  var eventID: String
  var title: String
  var company: String
  var role: String
  var action: String
  var date = Date()
  var read = false
}
@MainActor final class CareerImportantEventStore: ObservableObject {
  static let shared = CareerImportantEventStore()
  @Published private(set) var changes: [CareerCalendarChange]
  @Published var error: String?
  init() {
    changes = LocalAIStorage.read("calendar-changes-v1.json", as: [CareerCalendarChange].self) ?? []
  }
  func append(event: CareerCalendarEvent, action: String) {
    let next =
      [
        CareerCalendarChange(
          eventID: event.id, title: event.title, company: event.company, role: event.role,
          action: action)
      ] + changes
    save(next)
  }
  func markRead(_ id: String) {
    var next = changes
    if let i = next.firstIndex(where: { $0.id == id }) { next[i].read = true }
    save(next)
  }
  private func save(_ next: [CareerCalendarChange]) {
    do {
      try LocalAIStorage.save(next, name: "calendar-changes-v1.json")
      changes = next
      error = nil
    } catch { self.error = error.localizedDescription }
  }
}
struct CareerImportantEventsView: View {
  @ObservedObject var store: Store
  var openMail: (() -> Void)? = nil
  var openCalendar: (() -> Void)? = nil
  @ObservedObject private var mail = CareerMailStore.shared
  @ObservedObject private var events = CareerImportantEventStore.shared
  @StateObject private var profile = ApplicationProfileStore()
  @State private var onlyPending = true
  @State private var showMail = false
  @State private var showCalendar = false
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("重要事件").font(.largeTitle.bold())
        Spacer()
        Toggle("仅待处理", isOn: $onlyPending)
        Button("邮箱") { goMail(nil) }
        Button("日历") { goCalendar() }
      }
      Text("求职邮件中的待确认通知与日历变更集中显示。只有确认关联后才会修改投递进度。").foregroundStyle(.secondary)
      if let error = events.error { Text(error).foregroundStyle(.red) }
      List {
        Section("邮件通知") {
          let candidates = mail.archive.insights.filter { !onlyPending || !$0.applied }
          if candidates.isEmpty { Text("暂无待确认求职通知。同步邮箱并识别通知后将在这里出现。").foregroundStyle(.secondary) }
          ForEach(candidates.reversed()) { item in
            HStack(alignment: .top) {
              Image(systemName: item.applied ? "checkmark.circle" : "envelope.badge")
              VStack(alignment: .leading, spacing: 6) {
                Text(item.title.isEmpty ? "求职邮件通知" : item.title).font(.headline)
                Text(
                  [item.company, item.role, item.stage, item.startISO].filter { !$0.isEmpty }
                    .joined(separator: " · "))
                Text(item.evidence).font(.caption).lineLimit(3).foregroundStyle(.secondary)
                Text(item.applied ? "已关联" : "待核对公司、岗位与时间").font(.caption)
              }
              Spacer()
              Button(item.applied ? "查看原邮件" : "核对通知") { goMail(item.messageID) }
            }.padding(.vertical, 6)
          }
        }
        Section("日历变更") {
          ForEach(events.changes.filter { !onlyPending || !$0.read }) { change in
            HStack {
              Image(systemName: "calendar.badge.clock")
              VStack(alignment: .leading) {
                Text(change.action + " · " + change.title).font(.headline)
                Text(
                  [change.company, change.role, change.date.formatted()].filter { !$0.isEmpty }
                    .joined(separator: " · ")
                ).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Button("查看日历") { goCalendar() }
              if !change.read { Button("标记已读") { events.markRead(change.id) } }
            }.padding(.vertical, 6)
          }
        }
        Section("邮箱同步状态") {
          ForEach(mail.archive.accounts) { account in
            VStack(alignment: .leading) {
              Text(account.address)
              Text(mail.syncStatus[account.id] ?? "尚未在本次启动中同步").font(.caption).foregroundStyle(
                .secondary)
            }
          }
        }
      }
    }.padding(24).sheet(isPresented: $showMail) {
      CareerMailView(store: store, profile: profile).frame(minWidth: 1000, minHeight: 720)
    }.sheet(isPresented: $showCalendar) {
      CareerCalendarView(store: store).frame(minWidth: 1000, minHeight: 720)
    }
  }
  private func goMail(_ id: String?) {
    mail.focusedMessageID = id
    if let openMail { openMail() } else { showMail = true }
  }
  private func goCalendar() { if let openCalendar { openCalendar() } else { showCalendar = true } }
}
