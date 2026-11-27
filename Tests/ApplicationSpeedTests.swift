import Foundation
@main struct ApplicationSpeedTests {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("careerai-speed-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ApplicationFieldMappingCache(directory: directory)
        let field = ApplicationFormField(id:"f0",label:"你的称呼",section:"basic",entryIndex:0,type:"text",options:[],required:true,hasValue:false)
        let fact = ApplicationAutofillFact(id:"basic.name",label:"姓名",section:"basic",entryIndex:0,value:"PRIVATE TEST VALUE")
        let source = "https://example.invalid/application?job=one"
        let key = cache.key(field:field,fields:[field],facts:[fact],source:source)
        precondition(cache.assignment(key:key,field:field,facts:[fact]) == nil)
        precondition(cache.shouldResolve(key) && !cache.shouldResolve(key))
        cache.beginRun(); precondition(cache.shouldResolve(key))
        cache.verified([(key,fact.id)])
        let reload = ApplicationFieldMappingCache(directory:directory)
        let changedValue = ApplicationAutofillFact(id:fact.id,label:fact.label,section:fact.section,entryIndex:0,value:"UPDATED PRIVATE VALUE")
        precondition(reload.assignment(key:key,field:field,facts:[changedValue])?.value == changedValue.value)
        var changed = field; changed.options = [.init(value:"a",label:"选项 A")]
        precondition(key != cache.key(field:changed,fields:[changed],facts:[fact],source:source))
        changed = field; changed.section = "family"
        precondition(key != cache.key(field:changed,fields:[changed],facts:[fact],source:source))
        precondition(key != cache.key(field:field,fields:[field],facts:[fact],source:source+"2"))
        let otherFact = ApplicationAutofillFact(id:"basic.englishName",label:"英文名",section:"basic",entryIndex:0,value:"Test")
        precondition(key != cache.key(field:field,fields:[field],facts:[fact,otherFact],source:source))
        changed = field; changed.id = "f9"
        precondition(key == cache.key(field:changed,fields:[changed],facts:[fact],source:source))
        changed.hasValue = true
        precondition(reload.assignment(key:key,field:changed,facts:[fact])?.value == fact.value)
        let raw = try String(contentsOf: directory.appendingPathComponent("verified-form-mappings-v1.json"),encoding:.utf8)
        precondition(!raw.contains(fact.value) && !raw.contains(source) && !raw.contains(field.label))
        reload.invalidate([key]); precondition(reload.assignment(key:key,field:field,facts:[fact]) == nil)
        precondition(ApplicationFieldMappingCache(directory:directory).assignment(key:key,field:field,facts:[fact]) == nil)
        print("PASS mapping reuse: verified-only, current profile values, schema/options/owner/source/catalogue invalidation, known profile replaces existing content, bounded retry, persistent invalidation, no private values in cache")
    }
}
