import AppKit
import SwiftUI
import UserNotifications

@MainActor final class CareerCalendarStore: ObservableObject {
  static let shared = CareerCalendarStore()
  @Published private(set) var events: [CareerCalendarEvent] = []
  @Published var error: String?
  @Published var notificationStatus = "提醒需开启系统通知权限"
  init() {
    events = LocalAIStorage.read("calendar-events-v1.json", as: [CareerCalendarEvent].self) ?? []
    Task { await restoreReminders() }
  }
  @discardableResult func save(_ event: CareerCalendarEvent) -> Bool {
    guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      event.end >= event.start
    else {
      error = "请填写标题，结束时间不能早于开始时间。"
      return false
    }
    let previous = events.first(where: { $0.id == event.id })
    var next = events
    var value = event
    value.updatedAt = Date()
    if let i = next.firstIndex(where: { $0.id == value.id }) {
      next[i] = value
    } else {
      next.append(value)
    }
    do {
      try LocalAIStorage.save(next, name: "calendar-events-v1.json")
      events = next
      error = nil
      CareerImportantEventStore.shared.append(
        event: value, action: value.cancelled ? "取消日程" : previous == nil ? "新增日程" : "更新日程")
      Task { await restoreReminders() }
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  func remove(_ id: String) {
    let removed = events.first(where: { $0.id == id })
    do {
      let next = events.filter { $0.id != id }
      try LocalAIStorage.save(next, name: "calendar-events-v1.json")
      events = next
      error = nil
      if let removed { CareerImportantEventStore.shared.append(event: removed, action: "删除日程") }
      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
        "career-event-" + id
      ])
    } catch { self.error = error.localizedDescription }
  }
  func enableNotifications() async {
    do {
      let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound, .badge,
      ])
      notificationStatus = allowed ? "系统提醒已开启" : "系统通知未授权，日历仍可使用"
      await restoreReminders()
    } catch { self.error = error.localizedDescription }
  }
  func restoreReminders() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    guard
      settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    else { return }
    let pending = await center.pendingNotificationRequests()
    center.removePendingNotificationRequests(
      withIdentifiers: pending.filter { $0.identifier.hasPrefix("career-event-") }.map(\.identifier)
    )
    notificationStatus = "系统提醒已开启"
    for event in events where !event.cancelled && event.reminderMinutes >= 0 {
      let date = event.start.addingTimeInterval(-Double(event.reminderMinutes) * 60)
      guard date > Date() else { continue }
      let content = UNMutableNotificationContent()
      content.title = event.title
      content.body = [event.company, event.role, event.location].filter { !$0.isEmpty }.joined(
        separator: " · ")
      content.sound = .default
      let trigger = UNCalendarNotificationTrigger(
        dateMatching: Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute], from: date), repeats: false)
      do {
        try await center.add(
          UNNotificationRequest(
            identifier: "career-event-" + event.id, content: content, trigger: trigger))
      } catch { self.error = "日历已保存，系统提醒设置失败：" + error.localizedDescription }
    }
  }
  func replaceDerived(prefix: String, with desired: [CareerCalendarEvent]) {
    let old = events.filter { $0.sourceID?.hasPrefix(prefix) == true }
    func signature(_ list: [CareerCalendarEvent]) -> String {
      list.sorted { $0.id < $1.id }.map { "\($0.id)|\($0.title)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)|\($0.cancelled)|\($0.company)|\($0.role)" }.joined(separator: "\n")
    }
    guard signature(old) != signature(desired) else { return }
    let next = FlowCalendarProjection.replacing(events, prefix: prefix, desired: desired)
    do { try LocalAIStorage.save(next, name: "calendar-events-v1.json"); events = next; error = nil; Task { await restoreReminders() } }
    catch { self.error = "日历同步失败：" + error.localizedDescription }
  }
  static func ics(_ events: [CareerCalendarEvent]) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    func escape(_ value: String) -> String {
      value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: ",", with: "\\,")
        .replacingOccurrences(of: "\r", with: "")
    }
    var lines = [
      "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//OfferFlow//Calendar//ZH", "CALSCALE:GREGORIAN",
    ]
    for e in events {
      lines += [
        "BEGIN:VEVENT", "UID:\(e.id)@careerai.local",
        "DTSTAMP:\(formatter.string(from:e.updatedAt))",
        "DTSTART:\(formatter.string(from:e.start))", "DTEND:\(formatter.string(from:e.end))",
        "SUMMARY:\(escape(e.title))", "LOCATION:\(escape(e.location))",
        "DESCRIPTION:\(escape([e.company,e.role,e.notes].joined(separator:"\n")))",
        "STATUS:\(e.cancelled ? "CANCELLED" : "CONFIRMED")", "END:VEVENT",
      ]
    }
    return (lines + ["END:VCALENDAR", ""]).joined(separator: "\r\n")
  }
  func export() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "求职日历.ics"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try Self.ics(events).write(to: url, atomically: true, encoding: .utf8) } catch {
      self.error = error.localizedDescription
    }
  }
}
struct CareerCalendarView: View {
    @EnvironmentObject private var journey: FlowJourney
    @State private var agenda = false
    @State private var agendaDay: Date?
    @ObservedObject var store: Store
    var openMail: () -> Void = {}
    @ObservedObject private var calendar = CareerCalendarStore.shared
    @State private var focus = Date()
    @State private var editor: CareerCalendarEvent?
    private var gregorian: Calendar { var value = Calendar(identifier: .gregorian); value.firstWeekday = 2; return value }
    var body: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 20) {
                Text("我的日历").font(.system(size: 24, weight: .semibold))
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("上个月")
                Text(focus.formatted(.dateTime.year().month(.wide))).font(.system(size: 17, weight: .medium)).frame(minWidth: 135)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("下个月")
                Spacer()
                Button(agenda ? "月历" : "近期事项") { agendaDay = nil; agenda.toggle() }
                Button("今天") { focus = Date() }
                FlowActionMenu(title: "更多日历操作", icon: "ellipsis", iconOnly: true, actions: [.init(title: "开启日程提醒", icon: "bell") { Task { await calendar.enableNotifications() } }, .init(title: "导出日历", icon: "square.and.arrow.up") { calendar.export() }])
                Button("新建", systemImage: "plus") { editor = CareerCalendarEvent() }.buttonStyle(.flowPrimary)
            }
            HStack(spacing: 12) {
                Image(systemName: "envelope").foregroundStyle(.secondary)
                Text("连接邮箱，将笔试、测评与面试通知整理进日历。").foregroundStyle(.secondary)
                Spacer()
                Button("查看求职邮箱") { openMail() }
            }.padding(16).background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 10))
            if let error = calendar.error { Text(error).foregroundStyle(.red) }
            if !calendar.notificationStatus.contains("已开启") {
                HStack { Text(calendar.notificationStatus).font(.caption).foregroundStyle(.secondary); Button("开启提醒") { Task { await calendar.enableNotifications() } } }
            }
            if agenda {
                VStack(alignment: .leading) {
                    if let day = agendaDay { HStack { Text(day.formatted(date: .complete, time: .omitted)); Spacer(); Button("查看全部近期事项") { agendaDay = nil } } }
                    ScrollView { FlowAgenda(calendar: calendar, onSelect: { editor = $0 }, day: agendaDay) }
                }
            } else {
            let monthCalendar = gregorian
            let eventsByDay = Dictionary(grouping: calendar.events.sorted { $0.start < $1.start }) { monthCalendar.startOfDay(for: $0.start) }
            GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { name in
                            Text(name).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 38)
                        }
                    }.background(Color(white: 0.98))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                        ForEach(days, id: \.self) { day in dayCell(day, events: eventsByDay[monthCalendar.startOfDay(for: day)] ?? [], height: max(64, (geometry.size.height - 40) / 6)) }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.1)))
            }
            }
            }
        }.padding(24).background(.white)
            .onAppear { consumeIntent() }
            .onChange(of: journey.revision) { _, _ in consumeIntent() }
            .sheet(item: $editor) { event in CareerEventEditor(store: store, event: event, calendar: calendar) }
    
        }
    }
    private func dayCell(_ day: Date, events: [CareerCalendarEvent], height: CGFloat) -> some View {
        let today = gregorian.isDateInToday(day)
        let current = gregorian.isDate(day, equalTo: focus, toGranularity: .month)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(day.formatted(.dateTime.month(.defaultDigits).day())).font(.system(size: 12, weight: today ? .semibold : .regular)).foregroundStyle(today ? Color.primary : Color.secondary)
                Spacer()
                if today { Circle().fill(Color.primary).frame(width: 5, height: 5) }
            }
            ForEach(Array(events.prefix(height >= 110 ? 2 : 1))) { event in
                Button { editor = event } label: {
                    Text((event.cancelled ? "已取消 · " : "") + event.start.formatted(.dateTime.hour().minute()) + " " + event.title)
                        .font(.system(size: 11)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(5).background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain).foregroundStyle(event.cancelled ? .secondary : .primary)
            }
            if events.count > (height >= 110 ? 2 : 1) {
                Button("查看当天全部") { focus = day; agendaDay = day; agenda = true }.font(.caption).buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }.padding(6).frame(maxWidth: .infinity).frame(height: height, alignment: .topLeading)
            .background(current ? Color.white : Color(white: 0.98)).contentShape(Rectangle())
            .onTapGesture { var event = CareerCalendarEvent(); event.start = gregorian.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day; event.end = event.start.addingTimeInterval(3600); editor = event }
            .overlay(Rectangle().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5).allowsHitTesting(false))
            .overlay { if today { Rectangle().strokeBorder(Color(white: 0.15), lineWidth: 2).allowsHitTesting(false) } }
            .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (today ? "，今天" : ""))
    }
    private var days: [Date] {
        guard let month = gregorian.dateInterval(of: .month, for: focus), let week = gregorian.dateInterval(of: .weekOfYear, for: month.start) else { return [] }
        return (0..<42).compactMap { gregorian.date(byAdding: .day, value: $0, to: week.start) }
    }
    private func consumeIntent() {
        guard let request = journey.intent, request.route == "calendar" else { return }
        if let id = request.eventID, let event = calendar.events.first(where: { $0.id == id }) { editor = event; journey.intent = nil; return }
        guard request.title != nil else { return }
        var event = CareerCalendarEvent(); event.title = request.title ?? "面试"; event.company = request.company ?? ""; event.role = request.role ?? ""; event.jobID = request.jobID ?? ""
        if let text = request.startISO, let date = ISO8601DateFormatter().date(from: text) { event.start = date }
        event.end = request.endISO.flatMap { ISO8601DateFormatter().date(from: $0) } ?? event.start.addingTimeInterval(3600)
        if request.startISO == nil { event.notes = "请核对开始与结束时间" }
        editor = event; journey.intent = nil
    }
    private func shift(_ value: Int) { focus = gregorian.date(byAdding: .month, value: value, to: focus) ?? focus }
}
private struct CareerEventEditor: View {
  @ObservedObject var store: Store
  @State var event: CareerCalendarEvent
  @ObservedObject var calendar: CareerCalendarStore
  @Environment(\.dismiss) var dismiss
  var body: some View {
        FlowSurface {
    VStack(alignment: .leading, spacing: 14) {
      Text("日程详情").font(.title2.bold())
      TextField("标题", text: $event.title)
      FlowSelect(title: "关联公司与岗位", selection: $event.jobID, options: [("", "不关联岗位")] + store.jobs.map { ($0.id, $0.company + " · " + $0.title) }).onChange(of: event.jobID) { _, id in
        if let job = store.jobs.first(where: { $0.id == id }) {
          event.company = job.company
          event.role = job.title
        }
      }
      TextField("公司", text: $event.company)
      TextField("岗位", text: $event.role)
      FlowSelect(title: "日程类型", selection: $event.kind, options: ["面试", "笔试", "测评", "投递截止", "跟进", "复习", "其他"].map { ($0, $0) })
      HStack(spacing: 12) {
        FlowDateTimeField(title: "开始", selection: $event.start)
        FlowDateTimeField(title: "结束", selection: $event.end)
      }
      TextField("地点 / 会议链接", text: $event.location)
      TextField("备注", text: $event.notes, axis: .vertical).lineLimit(3...6)
      FlowSelect(title: "提前提醒", selection: $event.reminderMinutes, options: [(-1, "不提醒"), (0, "开始时"), (15, "提前 15 分钟"), (30, "提前 30 分钟"), (60, "提前 1 小时"), (1440, "提前 1 天")])
      Toggle("已取消", isOn: $event.cancelled).toggleStyle(.switch).controlSize(.small)
      if let error = calendar.error { Text(error).foregroundStyle(.red) }
      HStack {
        Button("删除", role: .destructive) {
          if let source = event.sourceID, source.hasPrefix("followup-"), let record = store.applications[event.jobID] { _ = store.updateApplication(event.jobID, stage: nil, notes: record.notes, followUpAt: nil) }
          if let source = event.sourceID, source.hasPrefix("review-") { InterviewCoachStore.shared.setReview(String(source.dropFirst(7)), date: nil) }
          calendar.remove(event.id)
          if calendar.error == nil { dismiss() }
        }
        Spacer()
        Button("取消") { dismiss() }
        Button("保存") {
          if let source = event.sourceID, source.hasPrefix("followup-"), let record = store.applications[event.jobID] {
            guard store.updateApplication(event.jobID, stage: nil, notes: record.notes, followUpAt: event.cancelled ? nil : event.start) else { return }
          }
          if let source = event.sourceID, source.hasPrefix("review-") { InterviewCoachStore.shared.setReview(String(source.dropFirst(7)), date: event.cancelled ? nil : event.start) }
          if calendar.save(event) { dismiss() }
        }.buttonStyle(.flowPrimary)
      }
    }.padding(24).frame(width: 600)
  
        }
    }
}

struct FlowAgenda: View {
    @ObservedObject var calendar: CareerCalendarStore
    var onSelect: (CareerCalendarEvent) -> Void
    var limit = 50
    var day: Date? = nil
    private var upcoming: [CareerCalendarEvent] { Array(calendar.events.filter { !$0.cancelled && (day == nil ? $0.end >= Calendar.current.startOfDay(for: Date()) : Calendar.current.isDate($0.start, inSameDayAs: day!)) }.sorted { $0.start < $1.start }.prefix(limit)) }
    var body: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 8) {
            if upcoming.isEmpty { Text("近期没有安排。面试、跟进和复习会集中显示在这里。") .font(.callout).foregroundStyle(.secondary).padding(12) }
            ForEach(upcoming) { event in
                Button { onSelect(event) } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) { Text(event.start.formatted(date: .abbreviated, time: .omitted)); Text(event.start.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary) }.font(.caption).frame(width: 90, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) { Text(event.title).font(.system(size: 13, weight: .medium)); Text(event.role).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.padding(12).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
        }
    
        }
    }
}
