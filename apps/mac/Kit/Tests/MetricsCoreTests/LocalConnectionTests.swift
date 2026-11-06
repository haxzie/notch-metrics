import Foundation
import Testing

@testable import MetricsCore

@Suite("local connections in settings")
struct LocalConnectionTests {
    /// The property `AppSettings` goes out of its way to have: a release that
    /// adds a field must not make every existing user's settings file fail to
    /// decode and silently reset their launch-at-login, their display choice
    /// and their connections along with it.
    @Test("a file written before connections existed still decodes")
    func oldFile() throws {
        let json = #"{"schemaVersion":1,"launchAtLogin":false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.localConnections.isEmpty)
        #expect(settings.launchAtLogin == false)
    }

    /// Same reasoning one level down. `LocalConnection` is inside
    /// `settings.json`, so a connection written by an older build must not
    /// take the whole file with it.
    @Test("a connection written before credentialFields existed still decodes")
    func olderConnection() throws {
        let json = """
            {"localConnections":[{"id":"c1","provider":"stripe","label":"Acme",
            "unavailableMetrics":[],"connectedAt":768960000}]}
            """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        let connection = try #require(settings.localConnections.first)
        #expect(connection.provider == "stripe")
        #expect(connection.credentialFields.isEmpty)
    }

    @Test("round-trips through the file it is stored in")
    func roundTrip() throws {
        var settings = AppSettings()
        settings.localConnections = [
            LocalConnection(
                id: "c1", provider: "stripe", label: "Acme Inc", currency: "USD",
                unavailableMetrics: ["mrr"], credentialFields: ["secret_key"])
        ]
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)

        let connection = try #require(back.localConnections.first)
        #expect(connection.id == "c1")
        #expect(connection.currency == "USD")
        #expect(connection.credentialFields == ["secret_key"])
        // A restricted key that cannot read subscriptions. The widget browser
        // greys these out rather than offering a tile that can only ever fail.
        #expect(connection.unavailableMetrics == ["mrr"])
    }

    /// Two Stripe accounts are two connections, and the Keychain is keyed on
    /// the connection for exactly this reason: keyed on the provider, the
    /// second key would overwrite the first.
    @Test("two accounts for one provider get separate keychain entries")
    func twoAccounts() {
        let first = LocalConnection(provider: "stripe", label: "Acme")
        let second = LocalConnection(provider: "stripe", label: "Other")
        #expect(first.id != second.id)
        #expect(
            SecretKey.connection(first.id, "secret_key")
                != SecretKey.connection(second.id, "secret_key"))
    }

    /// The prefix is what `deleteAll(matching:)` wipes on disconnect. If it
    /// overlapped the plugin namespace, removing a connection would take a
    /// custom app's secrets with it.
    @Test("the connection namespace does not overlap the plugin one")
    func namespaces() {
        #expect(SecretKey.connectionPrefix("stripe") == "connection.stripe.")
        #expect(SecretKey.pluginPrefix("stripe") == "plugin.stripe.")
        #expect(!SecretKey.connection("x", "k").account.hasPrefix(SecretKey.pluginPrefix("x")))
    }

    /// Disconnecting has to take the key with it: there is no server-side row
    /// to revoke, so a settings entry removed on its own would leave a live
    /// Stripe key on disk with nothing in the app able to find or remove it.
    @Test("wiping by prefix takes every field of one connection and no other")
    func wipe() throws {
        let store = InMemorySecretStore()
        let mine = LocalConnection(provider: "shopify", label: "Mine")
        let theirs = LocalConnection(provider: "stripe", label: "Theirs")

        try store.set("shpat_token", for: .connection(mine.id, "access_token"))
        try store.set("my-store.myshopify.com", for: .connection(mine.id, "shop_domain"))
        try store.set("rk_live_other", for: .connection(theirs.id, "secret_key"))

        try store.deleteAll(matching: SecretKey.connectionPrefix(mine.id))

        #expect(try store.string(for: .connection(mine.id, "access_token")) == nil)
        #expect(try store.string(for: .connection(mine.id, "shop_domain")) == nil)
        #expect(try store.string(for: .connection(theirs.id, "secret_key")) == "rk_live_other")
    }
}
