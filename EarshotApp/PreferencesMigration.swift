import Foundation

/// Copies settings saved under the app's earlier bundle IDs into the current one, once per old ID.
enum PrefsMigration {
    /// Newest first, so a newer ID's value wins a key that both have. Each marker is set once that ID
    /// has been copied. The oldest keeps the marker it always had, so a domain copied before carries it.
    static let sources: [(id: String, marker: String)] = [
        ("com.gaberger.earshot", "migratedFromComGabergerEarshot"),  // 1.0 – 1.2.1
        ("local.whisper.transcribe", "migratedFromOldBundleID"),     // before the Earshot name
    ]

    /// Copies each old domain's settings without replacing any value already set.
    static func run(from sources: [(id: String, marker: String)] = sources, into defaults: UserDefaults = .standard) {
        for (id, marker) in sources where !defaults.bool(forKey: marker) {
            for (key, value) in defaults.persistentDomain(forName: id) ?? [:] where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            defaults.set(true, forKey: marker)
        }
    }
}
