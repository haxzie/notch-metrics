import Foundation
import MetricsCore
import Testing

@testable import MetricsAPI

/// The catalogue is what lets a provider ship without an app release, so the
/// shapes it can arrive in are worth pinning.
struct ConnectorCatalogueTests {
    /// A server that has never heard of notifications must still decode.
    ///
    /// This is the regression that would blank every widget for every user on
    /// an older Worker: one missing key failing the decode of the whole
    /// catalogue. The field is optional for exactly this reason.
    @Test("a catalogue with no notifications key decodes")
    func decodesWithoutNotifications() throws {
        let json = """
            {"id":"stripe","name":"Stripe","category":"revenue","tagline":"",
             "docsUrl":"https://example.com","accentColor":"#111111",
             "authMode":"api_key","fields":[],"metrics":[],
             "status":"stable","minAppVersion":"0.1.0","connections":[]}
            """
        let entry = try JSONDecoder().decode(ConnectorEntry.self, from: Data(json.utf8))
        #expect(entry.notifications == nil)
        #expect(entry.id == "stripe")
    }

    @Test("notification definitions decode off the catalogue")
    func decodesNotifications() throws {
        let json = """
            {"id":"stripe","name":"Stripe","category":"revenue","tagline":"",
             "docsUrl":"https://example.com","accentColor":"#111111",
             "authMode":"api_key","fields":[],"metrics":[],
             "notifications":[
               {"id":"payment_received","kind":"event","label":"New payment",
                "shortLabel":"New payment","severity":"success",
                "methodology":"A charge that succeeded.","defaultEnabled":false,
                "userConfigurable":true,"minIntervalSeconds":60},
               {"id":"metric_threshold_crossed","kind":"threshold",
                "label":"MRR crosses a figure","shortLabel":"Threshold",
                "severity":"info","methodology":"Checked against MRR.",
                "defaultEnabled":false,"userConfigurable":true,
                "minIntervalSeconds":3600}
             ],
             "status":"stable","minAppVersion":"0.1.0","connections":[]}
            """
        let entry = try JSONDecoder().decode(ConnectorEntry.self, from: Data(json.utf8))
        let definitions = try #require(entry.notifications)
        #expect(definitions.count == 2)
        #expect(definitions[0].severity == .success)
        // What the pane keys the "needs a figure" warning off.
        #expect(!definitions[0].isThreshold)
        #expect(definitions[1].isThreshold)
    }

    @Test("an unfamiliar notification kind is still rendered, not dropped")
    func unknownKindSurvives() throws {
        // `kind` is a plain String with a computed `isThreshold`, not an enum:
        // a kind invented on the server must degrade to a plain toggle rather
        // than fail the catalogue.
        let json = """
            {"id":"schedule","kind":"a_kind_from_the_future","label":"Something",
             "shortLabel":"Something","severity":"info","methodology":"x",
             "defaultEnabled":false,"userConfigurable":true,"minIntervalSeconds":60}
            """
        let definition = try JSONDecoder().decode(AlertDefinition.self, from: Data(json.utf8))
        #expect(definition.kind == "a_kind_from_the_future")
        #expect(!definition.isThreshold)
    }
}
