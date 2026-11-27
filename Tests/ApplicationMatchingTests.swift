import Foundation

@main struct ApplicationMatchingTests {
    static func field(_ label: String, section: String = "basic", index: Int = 0, type: String = "text", hasValue: Bool = false, id: String = "field") -> ApplicationFormField {
        .init(id: id, label: label, section: section, entryIndex: index, type: type, options: [], required: false, hasValue: hasValue)
    }
    static func require(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
    static func main() throws {
        var captured = ApplicationProfile()
        captured.entries["custom"] = [.init(values: ["question": "专项计划类别", "answer": "测试类别", "sourceURL": "https://source.invalid/apply", "sourceSection": "basic", "sourceEntryIndex": "0"])]
        require(ApplicationAutofillPlanner.plan(fields: [field("专项计划类别：")], facts: captured.facts(forSourceURL: "https://source.invalid/apply")).first?.value == "测试类别", "Captured answer reaches the matching planner")
        require(ApplicationAutofillPlanner.plan(fields: [field("专项计划类别")], facts: captured.facts(forSourceURL: "https://other.invalid/apply")).isEmpty, "Another application cannot use scoped answer")
        let historical = ApplicationAutofillFact(id: "basic.preEnrollmentHouseholdCity", label: "入学前户口所在地（省 / 市 / 区县）", section: "basic", entryIndex: 0, value: "测试省测试市测试区")
        require(ApplicationAutofillPlanner.plan(fields: [field("入学前的户口所在地", type: "combobox")], facts: [historical]).first?.value == historical.value, "New historical address aliases match independently")
        let identity = ApplicationAutofillFact(id: "basic.documentNumber", label: "证件号码", section: "basic", entryIndex: 0, value: "TEST-ID-NOT-REAL")
        let identityType = ApplicationAutofillFact(id: "basic.documentType", label: "证件类型", section: "basic", entryIndex: 0, value: "居民身份证")
        let name = ApplicationAutofillFact(id: "basic.name", label: "姓名", section: "basic", entryIndex: 0, value: "测试候选人")
        let facts = [identity, identityType, name]
        for label in ["身份证号", "身份证号码", "证件号码", "证件号", "身份证件号码", "居民身份证号码", "本人身份证号码", "document number"] {
            let planned = ApplicationAutofillPlanner.plan(fields: [field(label)], facts: facts)
            require(planned.count == 1 && planned[0].factID == identity.id, "Exact applicant identity alias")
        }
        let composite = [field("证件类型", index: 0, type: "combobox", id: "type"), field("证件号码", index: 1, id: "number")]
        let planned = ApplicationAutofillPlanner.plan(fields: composite, facts: facts)
        require(planned.count == 2 && planned.first { $0.fieldID == "number" }?.factID == identity.id, "Compound control occurrence does not imply another person")
        require(ApplicationAutofillPlanner.plan(fields: [field("证件号码", type: "combobox")], facts: facts).isEmpty, "Ambiguous type selector must not receive identity number")
        require(ApplicationAutofillPlanner.plan(fields: [field("证件号码", hasValue: true)], facts: facts).first?.value == identity.value, "Known profile replaces an existing ID")
        print("PASS ID aliases, compound occurrence, selector/number separation and existing values")

        for scope in ["family", "work", "education", ""] {
            require(ApplicationAutofillPlanner.plan(fields: [field("身份证号码", section: scope)], facts: facts).isEmpty, "Do not lend applicant ID to another/unknown owner")
        }
        for label in ["家属身份证号码", "证明人身份证号码", "紧急联系人证件号", "公司注册号码"] {
            require(ApplicationAutofillPlanner.plan(fields: [field(label)], facts: facts).isEmpty, "Identity must not match unrelated label")
        }
        let familyIdentity = ApplicationAutofillFact(id: "family.1.documentNumber", label: "证件号码", section: "family", entryIndex: 1, value: "FAMILY-TEST-ID")
        require(ApplicationAutofillPlanner.plan(fields: [field("证件号码", section: "family", index: 1)], facts: facts + [familyIdentity]).first?.factID == familyIdentity.id, "Family owner can use only own record")
        require(ApplicationAutofillPlanner.plan(fields: [field("证件号码", section: "family", index: 0)], facts: [familyIdentity]).isEmpty, "Repeated people retain exact index")
        let highest = ApplicationAutofillFact(id: "basic.highestDegree", label: "最高学历", section: "basic", entryIndex: 0, value: "硕士")
        require(!ApplicationAutofillPlanner.allowed(field("最高学历", section: "family"), fact: highest), "Highest degree exception must not cross into family")
        print("PASS family/referee/unknown owner boundaries and repeated-person separation")

        func status(_ f: ApplicationFormField, _ values: [ApplicationAutofillFact]) -> String { ApplicationAutofillPlanner.unmatchedOutcome(field: f, facts: values).status }
        require(status(field("证件号码", index: 1), []) == "missing-profile", "Known missing ID is specifically missing profile")
        require(status(field("证件号码", index: 1), facts) == "unmatched", "Present ID cannot be described as absent")
        require(status(field("证件号码", hasValue: true), []) == "missing-profile", "Existing result reason")
        require(status(field("是否接受公司特殊安排"), facts) == "unmatched", "Unknown meaning is not missing profile")
        require(status(field("证件号码", section: "family"), facts) == "unmatched", "Wrong owner is unresolved instead of wrong missing-claim")
        require(status(field("姓名", section: ""), []) == "unmatched", "Unknown section is unresolved")
        for label in ["本人已知悉上述要求", "本人承诺信息真实", "本人保证信息真实", "本人已经知晓以上内容", "我已阅读并同意隐私协议", "I acknowledge these terms"] {
            require(status(field(label, type: "checkbox"), facts) == "manual-consent", "Consent manually acknowledged")
            require(ApplicationAutofillPlanner.manualOutcome(label: label, id: "manual").status == "manual-consent", "Excluded manual fields retain consent-specific reason")
            require(!ApplicationAutofillPlanner.allowed(field(label), fact: identity), "No automatic consent")
        }
        require(status(field("短信验证码"), facts) == "manual", "OTP is manual, not profile missing or consent")
        print("PASS distinct missing-profile/unmatched/preserved/manual-consent/manual reasons")

        let badJSON = Data("{\"matches\":[{\"fieldID\":\"field\",\"factID\":\"basic.documentNumber\",\"confidence\":1}]}".utf8)
        let familyMapping = try ApplicationAutofillPlanner.decodeMappings(badJSON, fields: [field("证件号码", section: "family")], facts: facts)
        require(familyMapping.isEmpty, "Model cannot bypass owner protection")
        let unrelatedMapping = try ApplicationAutofillPlanner.decodeMappings(badJSON, fields: [field("其他说明")], facts: facts)
        require(unrelatedMapping.isEmpty, "Model cannot spill identity into unrelated labels")
        let correctMapping = try ApplicationAutofillPlanner.decodeMappings(badJSON, fields: [field("证件号码", index: 1)], facts: facts)
        require(correctMapping.first?.factID == identity.id, "Scoped compound ID supported by model-selected IDs too")
        let wrongKindJSON = Data("{\"matches\":[{\"fieldID\":\"field\",\"factID\":\"basic.name\",\"confidence\":1}]}".utf8)
        let wrongKind = try ApplicationAutofillPlanner.decodeMappings(wrongKindJSON, fields: [field("证件号码")], facts: facts)
        require(wrongKind.isEmpty, "Model cannot put name into identity-number field")
        print("PASS model mapping cannot bypass identity scope or field semantics")
        var profile = ApplicationProfile()
        profile.values = ["basic.emergencyName": "家属甲", "basic.emergencyPhone": "TEST-PHONE"]
        profile.entries["family"] = [.init(values: ["name": "家属甲", "phone": "TEST-PHONE", "relationship": "母亲"])]
        profile.entries["education"] = [.init(values: ["degree": "硕士", "academicDegree": "硕士", "endDate": "2027-06"]), .init(values: ["degree": "本科", "academicDegree": "学士", "endDate": "2024-06"])]
        profile.entries["award"] = [.init(values: ["name": "三等奖学金", "level": "校级", "date": "2024-10"])]
        let derived = profile.facts
        require(derived.first { $0.id == "basic.emergencyRelation" }?.value == "母亲", "Contact relation must come from exact name AND phone")
        require(derived.first { $0.id == "basic.highestAcademicDegree" }?.value == "硕士", "Highest academic degree from highest education record")
        require(derived.first { $0.id == "basic.graduationCohort" }?.value == "2027届高校毕业生", "Graduation cohort comes from date, not current year")
        require(derived.first { $0.id == "campus.0.scholarship" }?.value == "校级三等奖学金", "Keep both scholarship scope and rank")
        profile.values["basic.emergencyPhone"] = "DIFFERENT"
        require(!profile.facts.contains { $0.id == "basic.emergencyRelation" }, "A name alone cannot identify contact relation")
        require(!derived.contains { $0.id.contains("annualSalary") || $0.id.contains("criminal") }, "Do not invent salary conversions or legal declarations")
        let place = ApplicationAutofillFact(id: "basic.nativePlace", label: "籍贯（省 / 市 / 区县）", section: "basic", entryIndex: 0, value: "测试省测试市测试区")
        require(ApplicationAutofillPlanner.plan(fields: [field("籍贯", type: "combobox")], facts: [place]).first?.value == place.value, "Detailed profile caption still maps to website native place")
        print("PASS evidence-derived facts and unknown-information boundaries")

    }
}
