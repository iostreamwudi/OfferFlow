import Foundation
@main struct ApplicationValueAdapterTests {
 @MainActor static func main() throws {
  let source="负责需求分析；完成方案评审；推动功能上线；结果尚待观察。"
  let good=try ApplicationValueAdapter.verifiedExcerpts(Data(#"{"excerpts":["负责需求分析","推动功能上线"]}"#.utf8),source:source,limit:20)
  precondition(good=="负责需求分析；推动功能上线")
  let fabricated=try ApplicationValueAdapter.verifiedExcerpts(Data(#"{"excerpts":["提升效率90%"]}"#.utf8),source:source,limit:20)
  precondition(fabricated==nil)
  let long=try ApplicationValueAdapter.verifiedExcerpts(Data(#"{"excerpts":["负责需求分析","推动功能上线"]}"#.utf8),source:source,limit:5)
  precondition(long==nil)
  let invalid=ApplicationAutofillFact(id:"family.0.phone",label:"联系电话",section:"family",entryIndex:0,value:"138xxxx0000")
  precondition(!ApplicationAutofillPlanner.validFact(invalid))
  let label=ApplicationFormField(id:"f0",label:"联系方式",section:"family",entryIndex:0,type:"text",options:[],required:true,hasValue:false)
  precondition(ApplicationAutofillPlanner.unmatchedOutcome(field:label,facts:[invalid]).status=="invalid-profile")
  print("PASS extractive length fitting, fabricated text rejected, masked phone identified")
 }
}
