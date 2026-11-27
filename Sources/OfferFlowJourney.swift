import SwiftUI
import AppKit

@MainActor final class FlowJourney: ObservableObject {
    var intent: FlowIntent?
    @Published private(set) var revision = 0
    func accept(_ value: FlowIntent) { intent = value; revision += 1 }
}

struct ApplicationLaunchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: FlowIntent
    let launch: (String, String, String) -> Bool
    @State private var company = ""
    @State private var role = ""
    @State private var error = ""
    private var choices: [String] {
        ApplicationRecording.roleChoices(request.role ?? "")
    }
    var body: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 18) {
            Text("记录到投递管理").font(.title2.weight(.semibold))
            Text("确认公司和具体岗位后加入投递管理。填写不会自动记录；是否已投递由你确认。") .font(.callout).foregroundStyle(.secondary)
            TextField("公司", text: $company).textFieldStyle(.flow)
            TextField("具体岗位名称", text: $role).textFieldStyle(.flow)
            if choices.count > 1 {
                FlowSelect(title: "从招聘项目中选择", selection: $role, options: [("", "选择岗位，也可以直接输入")] + choices.map { ($0, $0) })
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack { Button("取消") { dismiss() }; Spacer(); Button("确认记录") {
                if launch(company, role, request.url ?? "") { dismiss() } else { error = "无法保存申请，请检查公司、岗位和网址。" }
            }.buttonStyle(.flowPrimary).disabled(company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.buttonStyle(.flowSecondary).padding(28).frame(width: 500)
        .onAppear { company = request.company ?? ""; role = choices.count == 1 ? choices[0] : "" }
    
        }
    }
}

/// Application follow-ups are derived, so editing/removing them cannot create duplicates.
@MainActor enum FlowReminders {
    static func synchronize(store: Store, calendar supplied: CareerCalendarStore? = nil) {
        let calendar = supplied ?? .shared
        let desired = FlowCalendarProjection.followups(jobs: store.jobs, applications: store.applications, existing: calendar.events)
        calendar.replaceDerived(prefix: "followup-", with: desired)
    }
}

struct FlowStepper: View {
    let title: String
    @Binding var value: Int
    var range = 1...20
    var body: some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(.secondary)
            Button { value = max(range.lowerBound, value - 1) } label: { Image(systemName: "minus").frame(width: 22, height: 24) }.disabled(value <= range.lowerBound).accessibilityLabel("减少" + title)
            Text("\(value)").monospacedDigit().frame(minWidth: 22)
            Button { value = min(range.upperBound, value + 1) } label: { Image(systemName: "plus").frame(width: 22, height: 24) }.disabled(value >= range.upperBound).accessibilityLabel("增加" + title)
        }.font(.system(size: 13))
    }
}
