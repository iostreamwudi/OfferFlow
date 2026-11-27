import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct AISettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: Store
    @State private var model = "doubao-seed-2-1-pro-260915"
    @State private var key = ""
    @State private var keyExists = false
    @State private var resume = ResumeMaterial(filename: "", name: "", text: "")
    @State private var message = ""
    var body: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI 设置").font(.system(size: 23, weight: .bold))
            Text("配置一次，供对话、打招呼、资料解析和陪练共用").font(.system(size: 12)).foregroundStyle(muted)
            TextField("模型 ID", text: $model).textFieldStyle(.flow).accessibilityLabel("豆包模型 ID")
            SecureField(keyExists ? "API Key 已保存在本机；输入新 Key 可替换" : "输入 API Key", text: $key).textFieldStyle(.flow)
            Text("Key 单独保存在本机受限文件中，不会写入项目源码或传给 BOSS。").font(.system(size: 10)).foregroundStyle(muted)
            Text("默认资料：" + CandidateMaterials.label()).font(.callout).foregroundStyle(.secondary)
            Button("管理个人资料与简历") { dismiss(); FlowIntent(route: "profile").post() }
            Text("填写服务商提供的模型 ID 与 API Key。简历可稍后添加；不会因为没有简历而阻止保存。") .font(.caption).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(.red) }
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("保存设置") {
                do {
                    if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try LocalAIStorage.write(Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8), name: "ark-api-key") }
                    try LocalAIStorage.save(ArkSettings(model: model.trimmingCharacters(in: .whitespacesAndNewlines)), name: "ark-settings.json")
                    NotificationCenter.default.post(name: .flowMaterialsChanged, object: nil)
                    dismiss()
                } catch { message = "设置保存失败，请检查本机存储权限。" }
            }.buttonStyle(.flowPrimary).disabled(model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!keyExists && key.isEmpty)) }
        }.padding(28).frame(width: 540).tint(accent)
            .onAppear {
                model = (LocalAIStorage.read("ark-settings.json", as: ArkSettings.self) ?? ArkSettings()).model
                keyExists = (try? LocalAIStorage.key()) != nil
                if let material = LocalAIStorage.read("resume.json", as: ResumeMaterial.self) { resume = material }
            }
    
        }
    }
    func importPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let document = PDFDocument(url: url), let text = document.string, text.count >= 100 else { message = "未能从 PDF 读取足够文字，请使用含可选中文字的简历。"; return }
        resume = ResumeMaterial(filename: url.lastPathComponent, name: url.deletingPathExtension().lastPathComponent.components(separatedBy: "_").first ?? "", text: text.precomposedStringWithCompatibilityMapping)
        message = ""
    }
}
