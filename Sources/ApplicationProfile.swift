import Foundation
import SwiftUI
import Darwin
import AppKit
import Combine

struct ApplicationAutofillFact: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let section: String
    let entryIndex: Int
    let value: String
}
struct ApplicationProfileField: Identifiable, Sendable {
    let key: String
    let label: String
    var multiline = false
    var placeholder = ""
    var id: String { key }
}
struct ApplicationProfileSection: Identifiable, Sendable {
    let id: String
    let title: String
    let icon: String
    let repeated: Bool
    let fields: [ApplicationProfileField]
}
enum ApplicationProfileCatalog {
    private static func fields(_ text: String) -> [ApplicationProfileField] {
        text.split(separator: "|").map { item in
            let pair = item.split(separator: ":", maxSplits: 1).map(String.init)
            let long = pair[1].hasSuffix("*")
            return ApplicationProfileField(key: pair[0], label: long ? String(pair[1].dropLast()) : pair[1], multiline: long)
        }
    }
    static let sections: [ApplicationProfileSection] = [
        .init(id: "basic", title: "基本信息", icon: "person", repeated: false, fields: fields("name:姓名|englishName:英文名|phone:手机号码|email:电子邮箱|gender:性别|birthDate:出生日期|nationality:国籍|ethnicity:民族|politicalStatus:政治面貌|maritalStatus:婚姻状况|documentType:证件类型|documentNumber:证件号码|nativePlace:籍贯（省 / 市 / 区县）|birthPlace:出生地|householdCity:户籍所在地|preEnrollmentHouseholdCity:入学前户口所在地（省 / 市 / 区县）|householdType:户籍性质|currentCity:现居城市|residentialAddress:现居住地址|address:通讯地址|postalCode:邮政编码|wechat:微信号|qq:QQ 号码|sourcePlace:生源地|specialties:特长*|emergencyName:紧急联系人|emergencyRelation:紧急联系人关系|emergencyPhone:紧急联系人电话|height:身高|weight:体重|health:健康状况|highestDegree:最高学历|highestAcademicDegree:最高学位|studyType:学习形式|highestLanguageExam:最高通过的语言等级考试|professionalQualification:职称、职业资格|graduationCohort:毕业届别|graduationDate:毕业时间|workYears:工作年限|website:个人网站|portfolio:作品集链接|github:GitHub 地址")),
        .init(id: "intention", title: "求职意向", icon: "scope", repeated: false, fields: fields("position:期望职位|industry:期望行业|city:期望城市|employmentType:求职类型|currentStatus:当前求职状态|expectedSalary:期望薪资|currentSalary:当前薪资|availability:到岗时间|internshipDays:每周实习天数|internshipMonths:可实习时长|relocation:是否接受调剂或异地|travel:是否接受出差|workPermit:工作许可|referral:内推人或内推码|sourceChannel:招聘信息来源|internshipAvailable:是否可实习")),
        .init(id: "education", title: "教育经历", icon: "graduationcap", repeated: true, fields: fields("school:学校名称|college:院系|major:专业|minor:辅修专业|majorCategory:专业类别|isOverseas:是否海外教育经历|degree:学历|academicDegree:学位|studyType:培养方式|startDate:入学时间|endDate:毕业时间|city:学校所在地|gpa:成绩 GPA|gpaScale:GPA 满分|ranking:成绩排名|courses:主修课程*|research:研究方向*|thesis:毕业论文|supervisor:导师|honors:教育荣誉*")),
        .init(id: "highSchool", title: "高中经历", icon: "building.columns", repeated: true, fields: fields("school:学校名称|startDate:开始时间|endDate:结束时间|city:学校所在地")),
        .init(id: "work", title: "工作与实习", icon: "briefcase", repeated: true, fields: fields("company:公司名称|department:部门|position:职位名称|employmentType:工作性质|industry:所属行业|city:工作地点|startDate:开始时间|endDate:结束时间|responsibilities:工作职责*|achievements:工作成果*|salary:薪资|preTaxMonthlySalary:职位月薪（税前）|hasReferee:是否有证明人|departureReason:离职原因|supervisor:证明人姓名|supervisorPosition:证明人职务|directReports:下属人数|supervisorPhone:证明人联系方式")),
        .init(id: "project", title: "项目经历", icon: "square.stack.3d.up", repeated: true, fields: fields("name:项目名称|role:担任角色|company:所属单位|startDate:开始时间|endDate:结束时间|description:项目背景*|responsibilities:个人职责*|achievements:项目成果*|technology:使用技术*|decisions:方案选择与取舍*|challenges:困难与解决过程*|evaluation:评估方法与证据*|lessons:不足与复盘*|url:项目链接")),
        .init(id: "portfolio", title: "作品集", icon: "photo.on.rectangle.angled", repeated: true, fields: fields("name:作品名称|url:作品链接|description:作品描述*")),
        .init(id: "campus", title: "在校经历", icon: "building.columns", repeated: true, fields: fields("name:组织或活动名称|role:担任职务|startDate:开始时间|endDate:结束时间|description:活动内容*|achievements:活动成果*")),
        .init(id: "award", title: "获奖情况", icon: "trophy", repeated: true, fields: fields("name:奖项名称|level:获奖级别|rank:获奖等级|organization:颁奖单位|date:获奖时间|description:奖项说明*")),
        .init(id: "competition", title: "竞赛经历", icon: "flag.checkered", repeated: true, fields: fields("name:竞赛名称|date:参赛时间|role:担任角色|result:竞赛成果*|description:竞赛描述*")),
        .init(id: "language", title: "外语能力", icon: "character.bubble", repeated: true, fields: fields("name:语种|englishLevel:英语水平|level:熟练程度|exam:考试名称|score:考试成绩|date:考试时间|listening:听说能力|reading:读写能力")),
        .init(id: "computer", title: "计算机与专业技能", icon: "desktopcomputer", repeated: true, fields: fields("name:技能名称|level:熟练程度|years:使用年限|description:技能说明*")),
        .init(id: "certificate", title: "资格证书", icon: "checkmark.seal", repeated: true, fields: fields("name:证书名称|type:证书种类|level:证书等级|organization:颁发机构|number:证书编号|date:取得时间|expiryDate:有效期|description:证书说明*")),
        .init(id: "family", title: "家庭情况", icon: "person.2", repeated: true, fields: fields("name:姓名|relationship:与本人关系|birthDate:出生日期|politicalStatus:政治面貌|company:工作单位|position:职务|phone:联系电话")),
        .init(id: "paper", title: "论文期刊", icon: "doc.text", repeated: true, fields: fields("name:论文名称|journal:发表期刊或会议|journalLevel:期刊级别|impactFactor:影响因子|date:发表时间|authorOrder:作者排序|status:发表状态|doi:DOI|url:论文链接|description:论文摘要*")),
        .init(id: "patent", title: "专利", icon: "lightbulb", repeated: true, fields: fields("name:专利名称|type:专利类型|number:专利号|date:申请或授权时间|inventorOrder:发明人排序|status:专利状态|achievements:专利成果*|description:专利说明*")),
        .init(id: "evaluation", title: "自我评价与兴趣", icon: "text.bubble", repeated: false, fields: fields("summary:自我评价*|strengths:个人优势*|interests:兴趣爱好*|careerPlan:职业规划*|motivation:通用求职动机*|additional:其他补充说明*")),
        .init(id: "custom", title: "其他问答", icon: "slider.horizontal.3", repeated: true, fields: fields("question:问题或字段名称|answer:回答内容*"))
    ]
    static func section(_ id: String) -> ApplicationProfileSection? { sections.first { $0.id == id } }
    static func field(section: String, key: String) -> ApplicationProfileField? { self.section(section)?.fields.first { $0.key == key } }
}
struct ApplicationProfileEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var values: [String: String] = [:]
    var resumeSourceFingerprint: String? = nil
}
struct ApplicationProfileAttachment: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var name: String
    var path: String
    var kind: String
}
struct ApplicationProfile: Codable, Equatable, Sendable {
    var version = 1
    var updatedAt = Date()
    var values: [String: String] = [:]
    var entries: [String: [ApplicationProfileEntry]] = [:]
    var attachments: [ApplicationProfileAttachment] = []
    var resumeFilename = ""
    var defaultResumeAttachmentID: String? = nil
    func facts(forSourceURL sourceURL: String) -> [ApplicationAutofillFact] {
        var scoped = self
        scoped.entries["custom"] = (entries["custom"] ?? []).filter { $0.values["sourceURL"] == nil || $0.values["reuseScope"] == "general" || $0.values["sourceURL"] == sourceURL }.map { entry in
            var copy = entry; copy.values.removeValue(forKey: "sourceURL"); return copy
        }
        return scoped.facts
    }
    var facts: [ApplicationAutofillFact] {
        var result: [ApplicationAutofillFact] = []
        for section in ApplicationProfileCatalog.sections {
            let records = section.repeated ? (entries[section.id] ?? []).map(\.values) : [values]
            for (index, record) in records.enumerated() {
                if section.id == "custom" {
                    if record["sourceURL"] != nil && record["reuseScope"] != "general" { continue }
                    let question = record["question", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                    let answer = record["answer", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !question.isEmpty, !answer.isEmpty { result.append(.init(id: "custom.\(index).answer", label: question, section: record["sourceSection"] ?? section.id, entryIndex: Int(record["sourceEntryIndex"] ?? "") ?? index, value: answer)) }
                    continue
                }
                for field in section.fields {
                    let key = section.repeated ? field.key : "\(section.id).\(field.key)"
                    let value = record[key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { result.append(.init(id: section.repeated ? "\(section.id).\(index).\(field.key)" : key, label: field.label, section: section.id, entryIndex: index, value: value)) }
                }
            }
        }
        // Derive only mechanically provable facts; never infer declarations or salary units.
        func add(_ id: String, _ label: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !result.contains(where: { $0.id == id }) else { return }
            let parts = id.split(separator: ".")
            result.append(.init(id: id, label: label, section: String(parts[0]), entryIndex: parts.count > 2 ? Int(parts[1]) ?? 0 : 0, value: value))
        }
        let dayFormatter = DateFormatter(); dayFormatter.locale = Locale(identifier: "en_US_POSIX"); dayFormatter.dateFormat = "yyyy-MM-dd"
        add("basic.applicationDate", "填表日期", dayFormatter.string(from: Date()))
        let contact = (entries["family"] ?? []).filter {
            $0.values["name"] == values["basic.emergencyName"] && $0.values["phone"] == values["basic.emergencyPhone"] && !($0.values["phone"] ?? "").isEmpty
        }
        if contact.count == 1 { add("basic.emergencyRelation", "紧急联系人关系", contact[0].values["relationship"]) }
        let ranks = ["博士": 5, "博士研究生": 5, "硕士": 4, "硕士研究生": 4, "研究生": 4, "本科": 3, "专科": 2, "高中": 1]
        let education = (entries["education"] ?? []).sorted { ranks[$0.values["degree"] ?? "", default: 0] > ranks[$1.values["degree"] ?? "", default: 0] }
        if let highest = education.first {
            add("basic.highestAcademicDegree", "最高学位", highest.values["academicDegree"])
            add("basic.studyType", "学习形式", highest.values["studyType"])
            add("basic.graduationDate", "毕业时间", highest.values["endDate"])
            add("basic.highestDegree", "最高学历", highest.values["degree"])
            if let end = highest.values["endDate"], end.count >= 4, let year = Int(end.prefix(4)), (2000...2100).contains(year) {
                add("basic.graduationCohort", "毕业届别", "\(year)届高校毕业生")
            }
        }
        add("basic.professionalQualification", "职称、职业资格", (entries["certificate"] ?? []).compactMap { $0.values["name"] }.joined(separator: "；"))
        let awards = (entries["award"] ?? []).map { $0.values }
        if (entries["campus"] ?? []).allSatisfy({ $0.values.values.allSatisfy(\.isEmpty) }) {
            add("campus.0.description", "校园经历", awards.map { [$0["date"], $0["name"], $0["level"]].compactMap { $0 }.joined(separator: " · ") }.joined(separator: "；"))
        }
        let scholarships = awards.compactMap { $0["name"] }.filter { $0.contains("奖学金") }
        for tier in ["特等", "一等", "二等", "三等"] {
            if scholarships.contains(where: { $0.contains(tier) }) { add("campus.0.scholarship", "所获最高奖学金", (awards.first { ($0["name"] ?? "").contains(tier) && ($0["name"] ?? "").contains("奖学金") }?["level"] ?? "") + tier + "奖学金"); break }
        }
        for (index, entry) in (entries["work"] ?? []).enumerated() {
            let combined = [entry.values["department"], entry.values["position"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / ")
            add("work.\(index).departmentPosition", "部门/职位", combined)
        }
        let awardRanks = ["国家级": 5, "全国": 5, "省级": 4, "省部级": 4, "市级": 3, "校级": 2, "院级": 1]
        let levels = awards.compactMap { $0["level"] }.filter { awardRanks[$0] != nil }.sorted { awardRanks[$0]! > awardRanks[$1]! }
        add("campus.0.highestHonor", "最高个人荣誉", levels.first)
        return result
    }
    func completion(_ section: ApplicationProfileSection) -> (filled: Int, total: Int) {
        let records = section.repeated ? entries[section.id, default: []].map(\.values) : [values]
        let total = max(1, records.count) * section.fields.count
        let filled = records.reduce(0) { count, row in count + section.fields.filter {
            !(row[section.repeated ? $0.key : "\(section.id).\($0.key)"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count }
        return (filled, total)
    }
}

struct ApplicationProfileStorage {
    let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CareerAI-Demo")) { self.directory = directory }
    var url: URL { directory.appendingPathComponent("application-profile-v1.json") }
    func importAttachment(from source: URL, kind: String) throws -> ApplicationProfileAttachment {
        let id = UUID().uuidString
        let folder = directory.appendingPathComponent("Attachments").appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = folder.appendingPathComponent(source.lastPathComponent)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.copyItem(at: source, to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
        return .init(id: id, name: source.lastPathComponent, path: target.path, kind: kind)
    }
    func load() throws -> ApplicationProfile {
        guard FileManager.default.fileExists(atPath: url.path) else { return ApplicationProfile() }
        let value = try JSONDecoder().decode(ApplicationProfile.self, from: Data(contentsOf: url))
        guard value.version == 1 else { throw ProfileError.message("网申档案版本不兼容，原文件已保留。") }
        return value
    }
    func save(_ profile: ApplicationProfile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(profile)
        let temporary = directory.appendingPathComponent(".application-profile-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ProfileError.message("无法创建网申档案文件。")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
enum ProfileError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
@MainActor final class ApplicationProfileStore: ObservableObject {
    @Published var profile: ApplicationProfile { didSet { scheduleSave() } }
    @Published private(set) var status = "资料保存在本机"
    @Published private(set) var hasSaveError = false
    private let storage: ApplicationProfileStorage
    private var saveTask: Task<Void, Never>?
    private var loadFailure = false
    private var terminationSubscription: AnyCancellable?
    var autofillFacts: [ApplicationAutofillFact] { profile.facts }
    init(directory: URL? = nil) {
        storage = directory.map(ApplicationProfileStorage.init(directory:)) ?? ApplicationProfileStorage()
        do {
            profile = try storage.load()
            // Old auto-discovery generated unanswered UI fragments such as 年/月.
            // Retain every user answer and every manually-created question.
            let count = profile.entries["custom"]?.count ?? 0
            profile.entries["custom"]?.removeAll { $0.values["sourceURL"] != nil && $0.values["answer", default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if count != (profile.entries["custom"]?.count ?? 0) { try storage.save(profile) }
        }
        catch { profile = ApplicationProfile(); status = error.localizedDescription + " 原档案已保留，请修复文件后重启。"; hasSaveError = true; loadFailure = true }
        terminationSubscription = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.save() }
    }
    private func scheduleSave() {
        guard !loadFailure else { return }
        status = "正在保存…"
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.save()
        }
    }
    @discardableResult func save() -> Bool {
        guard !loadFailure else { return false }
        saveTask?.cancel(); saveTask = nil
        var saved = profile; saved.updatedAt = Date()
        do { try storage.save(saved); status = "已保存到本机"; hasSaveError = false; return true }
        catch { status = "保存失败，请重试：\(error.localizedDescription)"; hasSaveError = true; return false }
    }
    @discardableResult func moveEntry(_ section: String, id: String, by offset: Int) -> Bool {
        guard ApplicationProfileCatalog.section(section)?.repeated == true,
              offset == -1 || offset == 1,
              var entries = profile.entries[section], let from = entries.firstIndex(where: { $0.id == id }),
              entries.indices.contains(from + offset) else { return false }
        entries.swapAt(from, from + offset)
        profile.entries[section] = entries
        return save()
    }
    @discardableResult func captureNewField(label: String, section: String, entryIndex: Int, sourceURL: String) -> Bool {
        let question = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question != "未命名字段", question.count <= 160,
              let url = URL(string: sourceURL), ["http", "https"].contains(url.scheme ?? ""),
              question.range(of: "密码|验证码|短信码|同意|隐私|协议|条款|授权|承诺|声明|知悉|知晓|已阅读|已了解|签名|password|captcha|otp|consent|agree|signature|acknowledge", options: [.regularExpression, .caseInsensitive]) == nil else { return false }
        let records = profile.entries["custom"] ?? []
        func normalized(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).components(separatedBy: CharacterSet.alphanumerics.inverted).joined() }
        guard !records.contains(where: { normalized($0.values["question"] ?? "") == normalized(question) && $0.values["sourceURL"] == sourceURL && $0.values["sourceSection"] == section && $0.values["sourceEntryIndex"] == String(entryIndex) }) else { return false }
        profile.entries["custom", default: []].append(ApplicationProfileEntry(values: ["question":question, "answer":"", "sourceURL":sourceURL, "sourceSection":section, "sourceEntryIndex":String(entryIndex)]))
        return true
    }
    func addEntry(_ section: String) { profile.entries[section, default: []].append(ApplicationProfileEntry()) }
    func removeEntry(_ section: String, id: String) { profile.entries[section]?.removeAll { $0.id == id } }
}
