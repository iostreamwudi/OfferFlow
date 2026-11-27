import Foundation

struct CareerCalendarEvent: Codable, Identifiable, Equatable {
  var id = UUID().uuidString
  var title = ""
  var jobID = ""
  var company = ""
  var role = ""
  var kind = "面试"
  var start = Date()
  var end = Date().addingTimeInterval(3600)
  var location = ""
  var notes = ""
  var reminderMinutes = 30
  var cancelled = false
  var sourceID: String? = nil
  var updatedAt = Date()
}
enum FlowCalendarProjection {
    static func followups(jobs: [Job], applications: [String: ApplicationRecord], existing: [CareerCalendarEvent]) -> [CareerCalendarEvent] {
        jobs.compactMap { job in
            guard let record = applications[job.id], record.isOpen, let date = record.followUpAt else { return nil }
            return event(source: "followup-" + job.id, company: job.company, role: job.title, kind: "跟进", date: date, duration: 900, jobID: job.id, existing: existing)
        }
    }
    static func event(source: String, company: String, role: String, kind: String, date: Date, duration: TimeInterval, jobID: String = "", existing: [CareerCalendarEvent]) -> CareerCalendarEvent {
        var value = existing.first { $0.sourceID == source } ?? CareerCalendarEvent()
        value.sourceID = source; value.title = kind + " · " + company; value.company = company; value.role = role; value.kind = kind; value.jobID = jobID
        value.start = date; value.end = date.addingTimeInterval(duration); value.cancelled = false
        return value
    }
    static func replacing(_ existing: [CareerCalendarEvent], prefix: String, desired: [CareerCalendarEvent]) -> [CareerCalendarEvent] {
        existing.filter { $0.sourceID?.hasPrefix(prefix) != true } + desired
    }
}
