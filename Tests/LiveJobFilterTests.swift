import Foundation

@main struct LiveJobFilterTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func listing(_ company: String, city: String, degree: String, deadline: String, update: String = "2026/11/17", extra: String = "") -> LiveJobListing {
        var fields = Array(repeating: "", count: 23)
        fields[0] = update; fields[1] = company; fields[2] = "民企"; fields[3] = "IT/互联网/游戏"
        fields[4] = "AI 产品经理 " + String(repeating: "完整招聘要求", count: 90) + " 长文末尾关键词"
        fields[5] = city; fields[6] = deadline; fields[7] = "2027届,2026届"; fields[8] = degree
        fields[9] = "秋招"; fields[10] = "公司官网"; fields[14] = "计算机、设计"; fields[15] = "有笔试"
        fields[18] = extra
        return LiveJobListing(fields: fields)
    }
    static func main() async throws {
        let a = listing("甲公司", city: "上海,北京", degree: "本科、硕士", deadline: "2026-11-17", extra: "补充专业")
        let b = listing("乙公司", city: "深圳", degree: "博士", deadline: "2026-11-16", update: "2026/11/16")
        let c = listing("丙公司", city: "全国多地", degree: "本科", deadline: "尽快投递", update: "2026/11/15")
        let d = listing("丁公司", city: "上海", degree: "本科/硕士", deadline: "2026-12-01", update: "2026/11/14")
        let index = LiveJobSearchIndex(jobs: [a,b,c,d])!
        func ids(_ filters: LiveJobFilterState, favorites: Set<String> = []) -> [String] {
            index.filter(filters, favorites: favorites, today: 20261117)!.jobs.map(\.id)
        }
        expect(index.options[3] == ["IT/互联网/游戏"], "slash-separated industry must remain intact")
        expect(Set(index.options[5]!) == ["上海", "北京", "深圳", "全国多地"], "location options must tokenize original cells")
        expect(Set(index.options[8]!) == ["本科", "硕士", "博士"], "education slash tokens")
        var f = LiveJobFilterState()
        expect(ids(f) == [a,b,c,d].map(\.id), "default excludes no records")
        f.selected[5] = ["上海", "深圳"]
        expect(ids(f) == [a,b,d].map(\.id), "within-field selection uses OR")
        f.selected[8] = ["硕士"]
        expect(ids(f) == [a,d].map(\.id), "between-field selection uses AND")
        f.company = "甲"; f.role = "产品"; f.major = "计算机"; f.query = "AI 长文末尾关键词"
        expect(ids(f) == [a.id], "keywords preserve entire long source text")
        f.onlyFavorites = true
        expect(ids(f).isEmpty && ids(f, favorites:[a.id]) == [a.id], "favorites intersects all filters")
        f = LiveJobFilterState(); f.deadline = .open
        expect(ids(f) == [a,d].map(\.id), "today included and unknown deadline not assumed open")
        f.deadline = .expired; expect(ids(f) == [b.id], "past date excluded today")
        f.deadline = .undated; expect(ids(f) == [c.id], "literal deadline stays undated")
        f.deadline = .all; f.deadlineFrom = "2026-11-17"; f.deadlineTo = "2026-11-17"
        expect(ids(f) == [a.id], "inclusive date range, unknown excluded")
        f = LiveJobFilterState(); f.updatedFrom = "2026-11-15"; f.updatedTo = "2026-11-16"
        expect(ids(f) == [b,c].map(\.id), "source update inclusive range")
        f.updatedTo = "2026-02-29"
        expect(f.dateError != nil && ids(f).isEmpty, "invalid calendar date must not broaden results")
        f.updatedTo = "2026-11-14"
        expect(f.dateError != nil && ids(f).isEmpty, "reversed ranges must not broaden results")
        f = LiveJobFilterState()
        f.rules = [LiveJobFieldRule(field: 18, operation: .notEmpty)]
        expect(ids(f) == [a.id], "all original fields supported including supplementary fields")
        f.rules.append(LiveJobFieldRule(field: 1, operation: .equals, value: "乙公司"))
        expect(ids(f).isEmpty, "custom rules use all by default")
        f.matchAnyRule = true
        expect(ids(f) == [a,b].map(\.id), "custom any evaluates only custom conditions")
        f.selected[5] = ["上海"]
        expect(ids(f) == [a.id], "facets remain AND with custom any group")
        f = LiveJobFilterState(); f.rules = [LiveJobFieldRule(field: 18, operation: .empty)]
        expect(ids(f) == [b,c,d].map(\.id), "empty checks actual raw cell")
        f.rules = [LiveJobFieldRule(field: 4, operation: .contains, value: "长文末尾关键词")]
        expect(ids(f).count == 4, "raw fields keep complete source values")
        f.rules = [LiveJobFieldRule(field: 1, operation: .contains, value: " ")]
        expect(ids(f).count == 4 && f.activeCount == 0, "unfinished conditions do not hide data")
        var roleFields = a.rawFields
        roleFields[4] = "ＡＩ - 产品经理（实习）"
        let fuzzyRole = LiveJobListing(fields: roleFields)
        roleFields[1] = "AI 产品公司"; roleFields[4] = "财务会计"
        let unrelatedRole = LiveJobListing(fields: roleFields)
        roleFields[1] = "技术公司"; roleFields[4] = "C++ 开发工程师"
        let cppRole = LiveJobListing(fields: roleFields)
        let roleIndex = LiveJobSearchIndex(jobs: [fuzzyRole, unrelatedRole, cppRole])!
        for keyword in ["产品", "ai产品", "实习 ai 产品", "产品，ＡＩ", "AI-产品经理"] {
            var search = LiveJobFilterState(); search.role = keyword
            expect(roleIndex.filter(search, favorites: [])!.jobs.map(\.id) == [fuzzyRole.id], "fuzzy role must match title only: " + keyword)
        }
        var search = LiveJobFilterState(); search.role = "产品 数据"
        expect(roleIndex.filter(search, favorites: [])!.jobs.isEmpty, "all role keywords are required")
        search.role = "产品"; search.selected[5] = ["深圳"]
        expect(roleIndex.filter(search, favorites: [])!.jobs.isEmpty, "role keywords intersect location filters")
        search = LiveJobFilterState(); search.role = "C++"
        expect(roleIndex.filter(search, favorites: [])!.jobs.map(\.id) == [cppRole.id], "technical symbols stay meaningful")
        search.role = "C#"
        expect(roleIndex.filter(search, favorites: [])!.jobs.isEmpty, "different technical symbols must not merge")
        search = LiveJobFilterState(); search.query = "ai产品"
        expect(roleIndex.filter(search, favorites: [])!.jobs.map(\.id) == [fuzzyRole.id], "global search also recognizes compact role text")
        search = LiveJobFilterState(); search.role = "  ，；  "
        expect(roleIndex.filter(search, favorites: [])!.jobs.count == 3, "empty keywords do not hide records")
        print("PASS role-only partial/multiword/width/case/spacing queries, technical symbols and combined filters")
        let worker = Task.detached { () -> Bool in
            do { try await Task.sleep(for: .milliseconds(30)) } catch {}
            return index.filter(LiveJobFilterState(), favorites: []) == nil
        }
        worker.cancel(); let cancelled = await worker.value; expect(cancelled, "cancelled searches return without scanning")
        print("PASS filter options, multi-select AND/OR, full text, favorites, date boundaries/missing/invalid, all23 raw fields, custom conditions, cancellation")
        if CommandLine.arguments.count > 1 {
            let text = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
            let snapshot = try LiveJobParser.parse(text, expectedRecordCount: 14249, headers: LiveJobParser.expectedHeaders)
            let start = Date()
            let full = LiveJobSearchIndex(jobs:snapshot.listings)!
            let elapsed = Date().timeIntervalSince(start)
            let all = full.filter(LiveJobFilterState(), favorites: [])!
            expect(all.jobs.count == 14137 && all.positions.count == 14137, "no arbitrary record cap")
            var real = LiveJobFilterState(); real.query = "上海 AI"
            let actual = full.filter(real, favorites: [])!.jobs.map(\.id)
            let expected = snapshot.listings.filter { job in
                let value = [job.company,job.title,job.city,job.industry,job.majorRequirements].joined(separator:" ")
                return ["上海","AI"].allSatisfy { value.localizedCaseInsensitiveContains($0) }
            }.map(\.id)
            expect(actual == expected, "existing search semantics preserved")
            print("PASS real fixture: \(all.jobs.count) records, \(actual.count) search results, index \(Int(elapsed*1000)) ms; no truncation")
        }
    }
}
