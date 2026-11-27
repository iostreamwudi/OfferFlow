import Foundation

struct FlowIntent: Codable, Equatable, Identifiable {
    var id: String { [route, jobID, url, company, role, eventID, sessionID].compactMap { $0 }.joined(separator: "|") }
    var route: String
    var jobID: String? = nil
    var eventID: String? = nil
    var sessionID: String? = nil
    var company: String? = nil
    var role: String? = nil
    var round: String? = nil
    var keyword: String? = nil
    var url: String? = nil
    var title: String? = nil
    var startISO: String? = nil
    var endISO: String? = nil
    func post() { NotificationCenter.default.post(name: .flowIntent, object: self) }
}
extension Notification.Name {
    static let flowIntent = Notification.Name("OfferFlow.intent")
    static let flowMaterialsChanged = Notification.Name("OfferFlow.materialsChanged")
}
