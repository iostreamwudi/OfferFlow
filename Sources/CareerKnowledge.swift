import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CareerKnowledgeItem: Codable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var content: String
    var category = "本地导入资料"
    var kind = "资料"
    var source = "手动记录"
    var updatedAt = Date()
}
@MainActor final class CareerKnowledgeStore: ObservableObject {
    static let shared = CareerKnowledgeStore()
    static let categories = ["当前目标与偏好","学习与经历","技能与成果","投递与面试","本地导入资料","资料来源"]
    @Published private(set) var items: [CareerKnowledgeItem] = LocalAIStorage.read("career-knowledge-v1.json",as:[CareerKnowledgeItem].self) ?? []
    func save(_ item:CareerKnowledgeItem) throws {
        var next=item;next.updatedAt=Date();var changed=items
        if let i=changed.firstIndex(where:{$0.id==item.id}){changed[i]=next}else{changed.insert(next,at:0)}
        try LocalAIStorage.save(changed,name:"career-knowledge-v1.json");items=changed
    }
    func remove(_ id:String) throws {let changed=items.filter{$0.id != id};try LocalAIStorage.save(changed,name:"career-knowledge-v1.json");items=changed}
    @discardableResult func remember(_ text:String, title:String = "记住这条", kind:String = "事实", source:String = "用户确认") throws -> CareerKnowledgeItem {
        let item=CareerKnowledgeItem(title:title,content:text,category:kind=="偏好" ? "当前目标与偏好":"学习与经历",kind:kind,source:source);try save(item);return item
    }
    func search(_ query:String) -> [CareerKnowledgeItem] {
        let words=query.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        return items.filter {item in words.allSatisfy { (item.title+"\n"+item.content+"\n"+item.source).localizedCaseInsensitiveContains($0) }}.sorted {$0.updatedAt>$1.updatedAt}
    }
    nonisolated static func context(for query: String, items: [CareerKnowledgeItem], limit: Int = 8) async throws -> String {
        let words=query.split(whereSeparator:{$0.isWhitespace||$0.isPunctuation}).map(String.init)
        let chars=Array(query.filter{!$0.isWhitespace && !$0.isPunctuation})
        let pairs=chars.count>1 ? (0..<(chars.count-1)).map{String(chars[$0...($0+1)])} : []
        let tokens = Set(words + pairs)
        // For long pasted questions, scan each document once for adjacent character pairs.
        // Re-running a localized substring scan for every pair grows with both input sizes.
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive], locale: .current) }
        let indexed = tokens.count > 96
        let pairTokens = indexed ? Set(tokens.lazy.map(fold).filter { $0.count == 2 }) : []
        let terms = indexed ? tokens.filter { fold($0).count != 2 } : tokens
        let ranked = try items.map { item in
            try Task.checkCancellation()
            let searchable = item.title + item.content
            var count = 0
            if indexed {
                var hits = Set<String>()
                var previous: Character?
                for c in fold(searchable) {
                    if let previous {
                        let pair = String(previous) + String(c)
                        if pairTokens.contains(pair) { hits.insert(pair) }
                    }
                    previous = c
                }
                count = hits.count
            }
            for token in terms {
                try Task.checkCancellation()
                if searchable.localizedCaseInsensitiveContains(token) { count += 1 }
            }
            return (item, count)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(limit)
        return ranked.map {"[资料 \($0.0.id)] \($0.0.title) · \($0.0.kind) · 来源：\($0.0.source)\n\($0.0.content)"}.joined(separator:"\n\n")
    }
    func syncProfile(_ profile:ApplicationProfile) throws {
        let source="OfferFlow 个人档案"
        let content=ResumeStudioStore.profileText(profile)
        guard !content.isEmpty else{return}
        var item=items.first(where:{$0.source==source}) ?? CareerKnowledgeItem(title:"个人档案摘要",content:"",category:"学习与经历",kind:"事实",source:source)
        guard item.content != content else{return};item.content=content;try save(item)
    }
    func importURLs(_ urls:[URL]) throws -> (added:Int, failures:[String]) {
        var files:[URL]=[];var failures:[String]=[]
        for url in urls {
            if (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true {
                if let enumerator=FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) {
                    for case let file as URL in enumerator where ["md","markdown","txt"].contains(file.pathExtension.lowercased()) {
                        let attrs=try? file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]);if attrs?.isRegularFile==true && attrs?.isSymbolicLink != true {files.append(file)}
                    }
                }
            } else {files.append(url)}
        }
        var changed=items;var added=0
        for file in files {
            do {
                guard ["md","markdown","txt"].contains(file.pathExtension.lowercased()) else{throw AIError.message("格式不支持")}
                let size=(try file.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
                guard size<=5_000_000 else{throw AIError.message("文件超过 5 MB")}
                let content=try String(contentsOf:file,encoding:.utf8)
                guard !content.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {continue}
                if changed.contains(where:{$0.source==file.path && $0.content==content}){continue}
                let item=CareerKnowledgeItem(title:file.deletingPathExtension().lastPathComponent,content:content,source:file.path)
                if let i=changed.firstIndex(where:{$0.source==file.path}){var update=item;update.id=changed[i].id;changed[i]=update}else{changed.append(item)}
                added+=1
            }catch{failures.append(file.lastPathComponent+"："+error.localizedDescription)}
        }
        try LocalAIStorage.save(changed,name:"career-knowledge-v1.json");items=changed;return (added,failures)
    }
}
struct CareerKnowledgeView: View {
    var profile: ApplicationProfile? = nil
    @ObservedObject private var store=CareerKnowledgeStore.shared
    @State private var search=""
    @State private var category="全部"
    @State private var selected=""
    @State private var draft=CareerKnowledgeItem(title:"",content:"")
    @State private var message=""
    @State private var delete=false
    private var filtered:[CareerKnowledgeItem]{store.search(search).filter{category=="全部" || $0.category==category}}
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Text("求职资料").font(.title2.bold());Spacer();Button("导入文件"){pick(folder:false)};Button("导入 Obsidian / 文件夹"){pick(folder:true)};Button("记住这条"){draft=CareerKnowledgeItem(title:"新记忆",content:"",category:"学习与经历",kind:"事实",source:"用户确认");selected=""};Button("新建资料"){draft=CareerKnowledgeItem(title:"",content:"");selected=""}}
            HStack {TextField("搜索标题、全文和来源",text:$search).textFieldStyle(.flow);Picker("分类",selection:$category){Text("全部").tag("全部");ForEach(CareerKnowledgeStore.categories,id:\.self){Text($0)}}}
            HSplitView {
                List(selection:$selected) {ForEach(filtered){item in VStack(alignment:.leading,spacing:5){Text(item.title).font(.headline);Text(item.kind+" · "+item.category).font(.caption).foregroundStyle(.secondary);Text(item.content.prefix(70)).font(.caption).lineLimit(2)}.tag(item.id)}}.frame(minWidth:190,idealWidth:250,maxWidth:340)
                VStack(alignment:.leading,spacing:12){TextField("标题",text:$draft.title).textFieldStyle(.flow);HStack{Picker("分类",selection:$draft.category){ForEach(CareerKnowledgeStore.categories,id:\.self){Text($0)}};Picker("性质",selection:$draft.kind){ForEach(["资料","事实","偏好","AI 建议"],id:\.self){Text($0)}}};TextField("来源",text:$draft.source).textFieldStyle(.flow);TextEditor(text:$draft.content).font(.system(size:14));Text("事实、偏好与 AI 建议分开保存。这里的记录不会自动覆盖网申个人档案。").font(.caption).foregroundStyle(.secondary);HStack{Button("保存"){perform{try store.save(draft);selected=draft.id;message="已保存"}}.buttonStyle(.flowPrimary).disabled(draft.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.content.isEmpty);Spacer();Button("删除",role:.destructive){delete=true}.disabled(!store.items.contains{$0.id==draft.id})}}.padding(.leading,16).frame(minWidth:450)
            }
            if !message.isEmpty{Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
        }.padding(24).onAppear{if let profile{perform{try store.syncProfile(profile)}}}.onChange(of:selected){_,id in if let item=store.items.first(where:{$0.id==id}){draft=item}}
        .alert("删除这条资料？",isPresented:$delete){Button("取消",role:.cancel){};Button("删除",role:.destructive){perform{try store.remove(draft.id);draft=CareerKnowledgeItem(title:"",content:"");selected=""}}}
    }
    private func perform(_ block:()throws->Void){do{try block()}catch{message=error.localizedDescription}}
    private func pick(folder:Bool){let panel=NSOpenPanel();panel.canChooseDirectories=folder;panel.canChooseFiles = !folder;panel.allowsMultipleSelection=true;if !folder{panel.allowedContentTypes=["md","markdown","txt"].compactMap{UTType(filenameExtension:$0)}};guard panel.runModal() == .OK else{return};perform{let result=try store.importURLs(panel.urls);message="已导入或更新 \(result.added) 条。"+(result.failures.isEmpty ? "":"\n"+result.failures.joined(separator:"\n"))}}
}
