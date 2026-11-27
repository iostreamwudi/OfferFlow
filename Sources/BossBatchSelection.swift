import SwiftUI

struct BossBatchSelection: View {
    @Environment(\.dismiss) private var dismiss
    let cards: [BossCard]
    let template: String
    let start: ([BossCard], Bool, Bool) -> Void
    @State private var selected = Set<String>()
    @State private var onePerCompany = false
    @State private var skipCompany = false
    @State private var search = ""
    private var visible: [BossCard] { cards.filter { search.isEmpty || ($0.company + $0.title).localizedCaseInsensitiveContains(search) } }
    private var chosen: [BossCard] { cards.filter { selected.contains($0.id) } }
    var body: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 16) {
            Text("批量发送招呼").font(.title2.weight(.semibold))
            Text("使用「" + template + "」为每个岗位准备招呼并发送。附件简历由你在 BOSS 中发送。") .font(.callout).foregroundStyle(.secondary)
            HStack { TextField("搜索公司或岗位", text: $search).textFieldStyle(.flow); Button("全选结果") { selected.formUnion(visible.map(\.id)) }; Button("清空") { selected = [] } }
            List {
                ForEach(visible) { card in
                    Toggle(isOn: Binding(get: { selected.contains(card.id) }, set: { if $0 { selected.insert(card.id) } else { selected.remove(card.id) } })) {
                        VStack(alignment: .leading, spacing: 4) { Text(card.title); Text(card.company).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
            }.frame(height: 290)
            Toggle("每家公司只处理一个岗位（按列表顺序）", isOn: $onePerCompany)
            Toggle("跳过已有沟通记录的整家公司", isOn: $skipCompany)
            Text("已发送或发送结果待核对的同一岗位始终跳过，避免重复发送。可以随时停止。") .font(.caption).foregroundStyle(.secondary)
            HStack { Button("取消") { dismiss() }; Spacer(); Text("已选 \(chosen.count) 个岗位").font(.caption); Button("开始发送招呼") { let values = chosen; dismiss(); start(values, onePerCompany, skipCompany) }.buttonStyle(.flowPrimary).disabled(chosen.isEmpty) }
        }.padding(24).frame(width: 600)
        .onAppear { selected = Set(cards.map(\.id)) }
    
        }
    }
}
