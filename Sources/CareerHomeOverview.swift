import SwiftUI

struct CareerHomeOverview: View {
    @ObservedObject var store: Store
    @ObservedObject var work: CareerWorkStore
    @ObservedObject var liveJobs: LiveJobsSession
    @ObservedObject private var calendar = CareerCalendarStore.shared
    @ObservedObject private var mail = CareerMailStore.shared
    @ObservedObject private var changes = CareerImportantEventStore.shared
    let open: (String) -> Void
    private var upcoming: [CareerCalendarEvent] {
        calendar.events.filter { !$0.cancelled && $0.end >= Date() }.sorted { $0.start < $1.start }
    }
    private var pending: Int { mail.archive.insights.filter { !$0.applied }.count + changes.changes.filter { !$0.read }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                card("岗位库", liveJobs.jobs.count, "liveJobs")
                card("待处理事件", pending, "events")
                card("未完成任务", work.data.tasks.filter { $0.status != "已完成" }.count, "tasks")
                card("进行中申请", store.applications.values.filter { record in record.isOpen && store.jobs.contains { $0.id == record.jobID && $0.source != "示例岗位" } }.count, "applications")
            }
            HStack {
                Image(systemName: "calendar").foregroundStyle(.secondary)
                if let event = upcoming.first {
                    Text("近期安排：\(event.start.formatted(date: .abbreviated, time: .shortened)) · \(event.title) · \(event.company) \(event.role)").lineLimit(1)
                } else { Text("近期没有日程，可以从日历新建，或从邮箱通知关联。").foregroundStyle(.secondary) }
                Spacer(); Button("查看日历") { open("calendar") }
            }.font(.callout)
        }.padding(.horizontal, 20).padding(.top, 18)
    }
    private func card(_ label: String, _ count: Int, _ route: String) -> some View {
        Button { open(route) } label: {
            HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(count.formatted()).font(.title3.weight(.semibold)) }
                .padding(12).frame(maxWidth: .infinity).background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
