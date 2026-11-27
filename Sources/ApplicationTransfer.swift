import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ApplicationTableIO {
    struct Table { var headers: [String]; var rows: [[String]]; var excel = false; var date1904 = false; var sheetName = "" }
    static func csv(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, afterQuote = false
        let chars = Array(text.replacingOccurrences(of: "\u{feff}", with: "")); var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" { if i+1 < chars.count && chars[i+1] == "\"" { field.append(c); i += 1 } else { quoted = false; afterQuote = true } }
                else { field.append(c) }
            } else if c == "\"" && field.isEmpty && !afterQuote { quoted = true }
            else if c == "," { row.append(field); field = ""; afterQuote = false }
            else if c == "\n" || c == "\r" { row.append(field); rows.append(row); row = []; field = ""; afterQuote = false; if c == "\r" && i+1 < chars.count && chars[i+1] == "\n" { i += 1 } }
            else { if afterQuote && !c.isWhitespace { throw AIError.message("CSV 引号后的内容无效。") }; if !afterQuote { field.append(c) } }
            i += 1
        }
        guard !quoted else { throw AIError.message("CSV 中有未闭合的引号。") }
        if !field.isEmpty || !row.isEmpty || afterQuote { row.append(field); rows.append(row) }
        return rows.filter { $0.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }
    }
    static func command(_ binary: String, _ args: [String], directory: URL? = nil, maxBytes: Int = 25_000_000) throws -> Data {
        let task = Process(); task.executableURL = URL(fileURLWithPath: binary); task.arguments = args; task.currentDirectoryURL = directory
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        try task.run(); var data = Data()
        while true { let chunk = pipe.fileHandleForReading.readData(ofLength: 65536); if chunk.isEmpty { break }; data.append(chunk); if data.count > maxBytes { task.terminate(); throw AIError.message("工作表内容过大，请拆分后导入。") } }
        task.waitUntilExit(); guard task.terminationStatus == 0 else { throw AIError.message("无法读取或生成表格文件。") }; return data
    }
    static func read(_ url: URL) throws -> Table {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 25_000_000 else { throw AIError.message("请选择 25MB 以内的表格。") }
        if url.pathExtension.lowercased() == "csv" {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw AIError.message("请将 CSV 保存为 UTF-8 或 UTF-16 编码。") }
            let matrix = try csv(text); guard let first = matrix.first else { throw AIError.message("表格为空。") }
            return Table(headers: first, rows: Array(matrix.dropFirst()))
        }
        guard url.pathExtension.lowercased() == "xlsx" else { throw AIError.message("支持 CSV 和 XLSX；旧版 XLS 请先另存为 XLSX。") }
        func member(_ name: String) throws -> Data { try command("/usr/bin/unzip", ["-p",url.path,name]) }
        let workbook = try XMLValues.parse(member("xl/workbook.xml"))
        guard let sheet = workbook.sheets.first, let relID = sheet["r:id"] else { throw AIError.message("Excel 没有可读取的工作表。") }
        let relations = try XMLValues.parse(member("xl/_rels/workbook.xml.rels"))
        guard let target = relations.relations.first(where: { $0["Id"] == relID && $0["TargetMode"] != "External" })?["Target"], !target.contains(".."), !target.contains(":") else { throw AIError.message("Excel 工作表引用无效。") }
        let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
        let shared = (try? XMLValues.parse(member("xl/sharedStrings.xml")).strings) ?? []
        let parsed = try XMLValues.parse(member(path))
        let cells = parsed.cells
        guard let maxRow = cells.keys.map({ $0.row }).max(), let maxColumn = cells.keys.map({ $0.column }).max(), maxRow <= 100_000, maxColumn <= 500, (maxRow + 1) * (maxColumn + 1) <= 2_000_000 else { throw AIError.message("工作表为空或维度过大。") }
        var matrix: [[String]] = []
        for row in 0...maxRow {
            var values = Array(repeating: "", count: maxColumn + 1)
            for col in 0...maxColumn { if let cell = cells[.init(row: row,column: col)] { values[col] = cell.type == "s" ? (Int(cell.value).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "") : cell.value } }
            if values.contains(where: { !$0.isEmpty }) { matrix.append(values) }
        }
        guard let first = matrix.first else { throw AIError.message("工作表为空。") }
        return Table(headers: first, rows: Array(matrix.dropFirst()), excel: true, date1904: workbook.date1904, sheetName: sheet["name"] ?? "首个工作表")
    }
    final class XMLValues: NSObject, XMLParserDelegate {
        struct Position: Hashable { var row: Int; var column: Int }
        struct Cell { var type: String; var value: String }
        var sheets: [[String:String]] = [], relations: [[String:String]] = [], strings: [String] = [], cells: [Position:Cell] = [:]
        var date1904 = false
        private var currentCell: Position?, cellType = "", cellValue = "", sharedValue = "", inShared = false, capturing = false
        static func parse(_ data: Data) throws -> XMLValues { if let text = String(data: data, encoding: .utf8), text.contains("<!DOCTYPE") || text.contains("<!ENTITY") { throw AIError.message("不支持包含实体声明的工作表。") }; let value = XMLValues(); let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = value; guard parser.parse() else { throw AIError.message("Excel XML 内容损坏。") }; return value }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]) {
            if name == "sheet" { sheets.append(attributes) }
            if name == "Relationship" { relations.append(attributes) }
            if name == "workbookPr" { date1904 = attributes["date1904"] == "1" || attributes["date1904"] == "true" }
            if name == "si" { inShared = true; sharedValue = "" }
            if name == "c", let address = attributes["r"] {
                var col = 0, digits = ""
                for c in address.uppercased() { if c.isNumber { digits.append(c) } else if let a = c.asciiValue, a >= 65, a <= 90 { col = col * 26 + Int(a - 64) } }
                if let row = Int(digits), row > 0, col > 0 { currentCell = Position(row: row-1, column: col-1) } else { currentCell = nil }
                cellType = attributes["t"] ?? "n"; cellValue = ""
            }
            if name == "t" || name == "v" { capturing = true }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if capturing { if inShared { sharedValue += string } else if currentCell != nil { cellValue += string } } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "t" || name == "v" { capturing = false }
            if name == "si" { strings.append(sharedValue); inShared = false }
            if name == "c" { if let currentCell { cells[currentCell] = Cell(type: cellType,value: cellValue) }; currentCell = nil }
        }
    }
    static func date(_ text: String, excel: Bool, date1904: Bool) -> Date? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = ISO8601DateFormatter().date(from: clean) { return date }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.isLenient = false
        for format in ["yyyy-MM-dd HH:mm:ss","yyyy-MM-dd","yyyy/MM/dd","yyyy年MM月dd日"] { formatter.dateFormat = format; if let date = formatter.date(from: clean) { return date } }
        if excel, let serial = Double(clean), (1...150000).contains(serial) { formatter.dateFormat = "yyyy-MM-dd"; return formatter.date(from: date1904 ? "1904-01-01" : "1899-12-30")?.addingTimeInterval(serial * 86400) }
        return nil
    }
    static func write(_ matrix: [[String]], to url: URL, xlsx: Bool) throws {
        if !xlsx {
            func quote(_ value: String) -> String { let trimmed = value.drop(while: { $0.isWhitespace }); let safe = ["=","+","-","@"].contains(String(trimmed.prefix(1))) ? "'" + value : value; return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            try ("\u{feff}" + matrix.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n")).write(to: url, atomically: true, encoding: .utf8); return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("career-xlsx-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        for directory in ["_rels","xl/_rels","xl/worksheets"] { try FileManager.default.createDirectory(at: folder.appendingPathComponent(directory), withIntermediateDirectories: true) }
        func write(_ path: String,_ text: String) throws { try text.write(to: folder.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        try write("[Content_Types].xml", "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>")
        try write("_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>")
        try write("xl/workbook.xml", "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"投递记录\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>")
        try write("xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>")
        func escaped(_ text: String) -> String { text.filter { $0 == "\n" || $0 == "\t" || $0 == "\r" || $0.unicodeScalars.allSatisfy { $0.value >= 32 } }.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
        func column(_ index: Int) -> String { var n = index + 1, result = ""; while n > 0 { n -= 1; result = String(UnicodeScalar(65 + n % 26)!) + result; n /= 26 }; return result }
        let rows = matrix.enumerated().map { row, values in "<row r=\"\(row+1)\">" + values.enumerated().map { col, text in "<c r=\"\(column(col))\(row+1)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escaped(text))</t></is></c>" }.joined() + "</row>" }.joined()
        try write("xl/worksheets/sheet1.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>\(rows)</sheetData></worksheet>")
        let archive = folder.appendingPathComponent("output.xlsx")
        _ = try command("/usr/bin/zip", ["-q","-r",archive.path,"[Content_Types].xml","_rels","xl"], directory: folder)
        try Data(contentsOf: archive).write(to: url, options: .atomic)
    }
}

struct ApplicationTransferView: View {
    @ObservedObject var store: Store
    var jobIDs: Set<String>? = nil
    @State private var table: ApplicationTableIO.Table?
    @State private var mapping: [String:Int] = [:]
    @State private var overwrite = false
    @State private var message = ""
    @State private var busy = false
    @State private var outputXLSX = false
    @State private var onlyErrors = false
    @State private var previewLimit = 100
    @Environment(\.dismiss) private var dismiss
    private let fields = ["公司","岗位","阶段","备注","跟进日期","更新时间","原链接","城市"]
    private var rows: [(number: Int, value: ApplicationImportRow?, error: String)] {
        guard let table else { return [] }; var seen = Set<String>()
        return table.rows.enumerated().map { index, values in
            func value(_ name: String) -> String { guard let col = mapping[name], values.indices.contains(col) else { return "" }; return values[col].trimmingCharacters(in: .whitespacesAndNewlines) }
            let company = value("公司"), title = value("岗位"), key = company.lowercased() + "\u{0}" + title.lowercased()
            guard !company.isEmpty, !title.isEmpty else { return (index+2,nil,"公司或岗位为空") }
            guard !seen.contains(key) else { return (index+2,nil,"文件内公司＋岗位重复，保留首行") }
            let rawStage = value("阶段")
            let aliases: [String:ApplicationStage] = ["已投递":.submitted,"已投":.submitted,"简历挂":.screenRejected,"一面挂":.oneFail,"二面挂":.twoFail,"三面挂":.threeFail,"offer":.offer]
            guard let stage = ApplicationStage.allCases.first(where: { $0.rawValue == rawStage || $0.label == rawStage }) ?? aliases[rawStage.lowercased()] ?? (rawStage.isEmpty ? .submitted : nil) else { return (index+2,nil,"未知阶段：" + rawStage) }
            let follow = ApplicationTableIO.date(value("跟进日期"), excel: table.excel, date1904: table.date1904), updated = ApplicationTableIO.date(value("更新时间"), excel: table.excel, date1904: table.date1904)
            if (!value("跟进日期").isEmpty && follow == nil) || (!value("更新时间").isEmpty && updated == nil) { return (index+2,nil,"日期无法解析") }
            let link = value("原链接")
            if !link.isEmpty { guard let url = URL(string: link), ["https","http"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil else { return (index+2,nil,"原链接无效") } }
            seen.insert(key)
            return (index+2,ApplicationImportRow(company: company,title: title,stage: stage,notes: value("备注"),followUpAt: follow,updatedAt: updated,sourceURL: link.isEmpty ? nil : link,city: value("城市")),"")
        }
    }
    var body: some View {
        FlowSurface {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("投递记录导入 / 导出").font(.title2.bold()); Spacer(); Button("关闭") { dismiss() } }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack { Button("选择 CSV / XLSX") { choose() }.disabled(busy); FlowSelect(title: "导出格式", selection: $outputXLSX, options: [(false,"CSV"),(true,"XLSX")]).frame(width: 160); Button("导出当前范围") { export() }.disabled(busy); if busy { ProgressView().controlSize(.small) } }
            Text("导出 \(exportRows.count) 条投递记录。XLSX 导入读取首个工作表，第一行为列名；CSV 支持 UTF-8 / UTF-16。").font(.caption).foregroundStyle(.secondary)
            if let table {
                Text("\(table.sheetName.isEmpty ? "CSV" : table.sheetName) · \(table.rows.count) 行").font(.headline)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())]) {
                        ForEach(fields,id: \.self) { field in VStack(alignment: .leading, spacing: 6) { Text(field).font(.caption).foregroundStyle(.secondary); FlowSelect(title: field, selection: Binding(get: { mapping[field] ?? -1 }, set: { mapping[field] = $0 }), options: [(-1,"不导入")] + table.headers.enumerated().map { ($0.offset, "\($0.offset+1). \($0.element)") }) } }
                    }
                    Toggle("更新已有同公司＋岗位的记录（默认跳过）", isOn: $overwrite)
                    Text("有效 \(rows.filter { $0.value != nil }.count) 行，错误或重复 \(rows.filter { $0.value == nil }.count) 行；预览前 \(previewLimit) 行").font(.caption)
                    Toggle("只查看错误与重复行", isOn: $onlyErrors)
                    ForEach(Array(rows.filter { !onlyErrors || $0.value == nil }.prefix(previewLimit)), id: \.number) { row in HStack { Text("第 \(row.number) 行").frame(width: 70,alignment: .leading); if let value = row.value { Text(value.company + " · " + value.title); Spacer(); Text(value.stage.label) } else { Text(row.error).foregroundStyle(.orange) } }.padding(.vertical,4) }
                }
                if rows.count > previewLimit { Button("显示更多行") { previewLimit += 100 } }
                Button("导入有效记录") { commit() }.buttonStyle(.flowPrimary).disabled(busy || rows.allSatisfy { $0.value == nil })
            }
            Spacer(minLength: 0)
        }.padding(24).frame(minWidth: 850,minHeight: 620)
    
        }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText, UTType(filenameExtension: "xlsx")!]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; message = ""
        Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await Task.detached { try ApplicationTableIO.read(url) }.value
                table = result; mapping = [:]
                let aliases = ["公司":["公司","公司名称","企业"],"岗位":["岗位","职位","职位名称","岗位名称"],"阶段":["阶段","状态","求职进展","投递状态"],"备注":["备注","说明"],"跟进日期":["跟进日期","下次跟进"],"更新时间":["更新时间","投递日期","投递时间"],"原链接":["原链接","链接","网申链接"],"城市":["城市","工作地点"]]
                for field in fields { mapping[field] = result.headers.firstIndex { (aliases[field] ?? [field]).contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? -1 }
            } catch { message = error.localizedDescription }
        }
    }
    private func commit() {
        let valid = rows.compactMap(\.value)
        if store.importApplications(valid, overwriteExisting: overwrite) { message = store.notice.isEmpty ? "导入已保存。" : store.notice; table = nil } else { message = store.notice }
    }
    private var exportRows: [[String]] {
        let formatter = ISO8601DateFormatter()
        return store.jobs.filter { store.applications[$0.id] != nil && (jobIDs == nil || jobIDs!.contains($0.id)) }.map { job in
            let record = store.applications[job.id]!
            return [job.company,job.title,record.stage.rawValue,record.notes,record.followUpAt.map { formatter.string(from:$0) } ?? "",formatter.string(from:record.updatedAt),job.sourceURL ?? "",job.city]
        }
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = outputXLSX ? "投递记录.xlsx" : "投递记录.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let matrix = [fields] + exportRows, xlsx = outputXLSX; busy = true
        Task { @MainActor in defer { busy = false }; do { try await Task.detached { try ApplicationTableIO.write(matrix, to: url, xlsx: xlsx) }.value; message = "已导出 \(matrix.count-1) 条记录。" } catch { message = error.localizedDescription } }
    }
}
