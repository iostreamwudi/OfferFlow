import Foundation

struct ApplicationJourneySnapshot: Decodable {
    struct Action: Decodable { var id: String; var label: String; var kind: String; var context: String? = nil; var allowedKinds: [String]? = nil }
    var scope: String
    var fingerprint: String
    var actions: [Action]
    var validation: [String]
    var hasFields: Bool
    var needsLogin: Bool
    var headings: [String]? = nil
    var activeSections: [String]? = nil
    var progress: String? = nil
    var modalContext: String? = nil
    var resumeSection: String? = nil
    var recoverySection: String? {
        if let resumeSection, !resumeSection.isEmpty { return resumeSection }
        // Long Moka-style forms expose every section in one document and may
        // use no semantic heading at all. Resume by rescanning that document.
        return hasFields ? "当前表单" : nil
    }
}

/// Missing profile facts are deliberately not inputs to traversal: a missing
/// required field may block this website's Next button, but not other sections.
enum ApplicationJourneyPolicy {
    static func key(_ action: ApplicationJourneySnapshot.Action, in page: ApplicationJourneySnapshot) -> String {
        // A tab/accordion is visited once per route, even if the active tab changes.
        if Set(action.allowedKinds ?? [action.kind]).isSubset(of: ["tab", "expand", "edit"]) {
            let route = (try? JSONSerialization.jsonObject(with: Data(page.scope.utf8)) as? [Any])?.first as? String ?? page.scope
            return route + "|" + action.id
        }
        return (page.progress ?? page.fingerprint) + "|" + action.id
    }
    static func available(in page: ApplicationJourneySnapshot, attempted: Set<String>, started: Bool) -> [ApplicationJourneySnapshot.Action] {
        guard !(page.needsLogin && !page.hasFields) else { return [] }
        return page.actions.filter { action in
            !attempted.contains(key(action, in: page))
                && (started || page.hasFields || (page.modalContext != nil && ["save", "save-next"].contains(action.kind)) || ["expand", "edit", "tab"].contains(action.kind) || (action.kind == "semantic" && !(action.context ?? "").isEmpty && Set(action.allowedKinds ?? []).isSubset(of: ["expand", "edit", "tab"])))
        }
    }
    static func next(in page: ApplicationJourneySnapshot, attempted: Set<String>, started: Bool, actionOrder: [String]? = nil) -> ApplicationJourneySnapshot.Action? {
        guard !(page.needsLogin && !page.hasFields) else { return nil }
        let order = actionOrder ?? ["edit", "expand", "scroll", "save", "save-next", "next", "tab"]
        let priorities = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return page.actions.enumerated().compactMap { index, observed -> (Int, ApplicationJourneySnapshot.Action)? in
            var action = observed
            // A real profile tab or collapsed region can be inspected without
            // inferring anything about the applicant, even with an unusual title.
            if action.kind == "semantic", let kinds = action.allowedKinds, kinds.count == 1, ["tab", "expand"].contains(kinds[0]) { action.kind = kinds[0] }
            guard priorities[action.kind] != nil, !attempted.contains(key(observed, in: page)),
                  started || page.hasFields || (page.modalContext != nil && ["save", "save-next"].contains(action.kind)) || ["expand", "edit", "tab"].contains(action.kind) else { return nil }
            return (index, action)
        }.sorted { a, b in
            let pa = priorities[a.1.kind]!, pb = priorities[b.1.kind]!
            return pa == pb ? a.0 < b.0 : pa < pb
        }.first?.1
    }
}
