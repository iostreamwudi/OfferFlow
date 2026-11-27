import SwiftUI

struct FlowPreparationView: View {
    @ObservedObject var profile: ApplicationProfileStore
    @AppStorage("offerflow.preparationCollapsed") private var collapsed = false
    @State private var configured = false
    @State private var materialLabel = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("求职准备").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(collapsed ? "展开" : "暂时收起") { collapsed.toggle() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            if !collapsed {
                HStack(spacing: 14) {
                    Button { FlowIntent(route: "profile").post() } label: {
                        Label(CandidateMaterials.effective(profile: profile.profile) == nil ? "添加简历" : "资料已就绪", systemImage: "doc.text")
                    }
                    Button { FlowIntent(route: "settings").post() } label: { Label(configured ? "AI 已配置" : "连接 AI", systemImage: "slider.horizontal.3") }
                    Text("按需准备，也可以先浏览岗位").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("期望岗位", text: Binding(get: { profile.profile.values["intention.position"] ?? "" }, set: { profile.profile.values["intention.position"] = $0 })).textFieldStyle(.flow)
                    TextField("期望城市", text: Binding(get: { profile.profile.values["intention.city"] ?? "" }, set: { profile.profile.values["intention.city"] = $0 })).textFieldStyle(.flow).frame(width: 140)
                    Button("查看岗位") { profile.save(); FlowIntent(route: "liveJobs", role: profile.profile.values["intention.position"], keyword: profile.profile.values["intention.city"]).post() }.buttonStyle(.flowPrimary)
                }
                if !materialLabel.isEmpty { Text("默认资料：" + materialLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }.padding(16).background(Color(white: 0.975), in: RoundedRectangle(cornerRadius: 12))
            .onAppear { refresh() }
            .onChange(of: profile.profile) { _, _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .flowMaterialsChanged)) { _ in refresh() }
    }
    private func refresh() { configured = (try? LocalAIStorage.key()) != nil; materialLabel = CandidateMaterials.label(profile: profile.profile) }
}
