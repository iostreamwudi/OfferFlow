import Foundation
@main struct ApplicationJourneyModelSmoke {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        guard CommandLine.arguments.contains("--live-model") else { fatalError("This check requires --live-model and uses the configured model.") }
        let edit = ApplicationJourneyAgent.Observation(headings:["个人档案"], activeSections:[], knownPending:0, missingOrUncertain:0, validationCount:0, actions:[.init(id:"edit-profile",label:"补全个人档案",kind:"semantic",context:"个人档案",allowedKinds:["edit","expand"])], recentActions:[])
        let first = try await ApplicationJourneyAgent.choose(edit)
        print("first decision:", first as Any)
        precondition(ApplicationJourneyAgent.resolve(first, candidates:[.init(id:"edit-profile",label:"补全个人档案",kind:"semantic",context:"个人档案",allowedKinds:["edit","expand"])]) != nil)
        let blocked = ApplicationJourneyAgent.Observation(headings:["申请资料"], activeSections:["个人信息"], knownPending:0, missingOrUncertain:1, validationCount:1, actions:[.init(id:"other",label:"更多内容",kind:"semantic",context:"补充资料",allowedKinds:["tab"])], recentActions:[.init(action:"前往另一组材料",kind:"next",effect:"validation-blocked")])
        let second = try await ApplicationJourneyAgent.choose(blocked)
        print("second decision:", second as Any)
        precondition(ApplicationJourneyAgent.resolve(second, candidates:[.init(id:"other",label:"更多内容",kind:"semantic",context:"补充资料",allowedKinds:["tab"])]) != nil)
        print("PASS configured live model: chooses profile edit from unfamiliar caption; continues accessible section after required information blocks Next")
    }
}
