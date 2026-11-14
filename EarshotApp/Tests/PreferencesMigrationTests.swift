// Tests for PrefsMigration: settings saved under an old bundle ID are copied once into the current one.
// Run: bash EarshotApp/Tests/run.sh. Every expected answer is written out by hand.
// The test domains use random names, so the real com.gaberger.earshot settings are never read or written.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

/// A fresh domain with a random name: the target defaults, and a name for each old ID.
func fresh(_ tag: String) -> String { "PrefsMigrationTests-\(tag)-\(UUID().uuidString)" }

func target() -> (UserDefaults, String) {
    let name = fresh("new")
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return (d, name)
}

func seed(_ defaults: UserDefaults, _ name: String, _ values: [String: Any]) {
    defaults.setPersistentDomain(values, forName: name)
}

@main struct PreferencesMigrationTests {
    static func main() {
        // MARK: the real sources, newest first
        let ids = PrefsMigration.sources.map(\.id)
        checkTrue("the newest old ID is com.gaberger.earshot", ids.first == "com.gaberger.earshot", "\(ids)")
        checkTrue("the oldest old ID is local.whisper.transcribe", ids.last == "local.whisper.transcribe", "\(ids)")
        checkTrue("there are exactly two old IDs", ids.count == 2, "\(ids)")
        checkTrue("the oldest keeps its original marker key, so earlier migrations are not repeated",
                  PrefsMigration.sources.last?.marker == "migratedFromOldBundleID")
        checkTrue("every source has its own marker",
                  Set(PrefsMigration.sources.map(\.marker)).count == PrefsMigration.sources.count)

        // MARK: one old ID
        do {
            let (d, _) = target()
            let old = fresh("old")
            seed(d, old, ["summaryTemplate": "sales", "speakerCount": 3])
            PrefsMigration.run(from: [(old, "m1")], into: d)
            checkTrue("a string setting is copied", d.string(forKey: "summaryTemplate") == "sales")
            checkTrue("an int setting is copied", d.integer(forKey: "speakerCount") == 3)
            checkTrue("the marker is set", d.bool(forKey: "m1"))
            d.removePersistentDomain(forName: old)
        }

        // MARK: a setting made since is kept
        do {
            let (d, _) = target()
            let old = fresh("old")
            seed(d, old, ["summaryTemplate": "sales", "autoStopMinutes": 10])
            d.set("quick", forKey: "summaryTemplate")
            PrefsMigration.run(from: [(old, "m1")], into: d)
            checkTrue("a value already set is not replaced", d.string(forKey: "summaryTemplate") == "quick")
            checkTrue("an unset value next to it is still copied", d.integer(forKey: "autoStopMinutes") == 10)
            d.removePersistentDomain(forName: old)
        }

        // MARK: runs once per old ID
        do {
            let (d, _) = target()
            let old = fresh("old")
            seed(d, old, ["speakerCount": 2])
            PrefsMigration.run(from: [(old, "m1")], into: d)
            d.removeObject(forKey: "speakerCount")
            seed(d, old, ["speakerCount": 5])
            PrefsMigration.run(from: [(old, "m1")], into: d)
            checkTrue("a second run copies nothing", d.object(forKey: "speakerCount") == nil)
            d.removePersistentDomain(forName: old)
        }

        // MARK: two old IDs, newest first
        do {
            let (d, _) = target()
            let newer = fresh("newer"), older = fresh("older")
            seed(d, newer, ["summaryTemplate": "sales"])
            seed(d, older, ["summaryTemplate": "minutes", "identifySpeakers": false])
            PrefsMigration.run(from: [(newer, "m1"), (older, "m2")], into: d)
            checkTrue("the newer ID wins a key both have", d.string(forKey: "summaryTemplate") == "sales")
            checkTrue("a key only the older ID has is copied",
                      d.object(forKey: "identifySpeakers") != nil && d.bool(forKey: "identifySpeakers") == false)
            checkTrue("both markers are set", d.bool(forKey: "m1") && d.bool(forKey: "m2"))
            d.removePersistentDomain(forName: newer); d.removePersistentDomain(forName: older)
        }

        // MARK: the newer domain already migrated from the older one
        do {
            let (d, _) = target()
            let newer = fresh("newer"), older = fresh("older")
            // Settings someone deleted in com.gaberger.earshot must not come back from local.whisper.transcribe.
            seed(d, newer, ["m2": true, "speakerCount": 4])
            seed(d, older, ["summaryTemplate": "minutes"])
            PrefsMigration.run(from: [(newer, "m1"), (older, "m2")], into: d)
            checkTrue("the newer domain's settings are copied", d.integer(forKey: "speakerCount") == 4)
            checkTrue("the older domain is skipped, because the newer one carried its marker",
                      d.object(forKey: "summaryTemplate") == nil)
            d.removePersistentDomain(forName: newer); d.removePersistentDomain(forName: older)
        }

        // MARK: nothing to copy
        do {
            let (d, name) = target()
            PrefsMigration.run(from: [(fresh("absent"), "m1")], into: d)
            let keys = Set((d.persistentDomain(forName: name) ?? [:]).keys)
            checkTrue("a missing old domain sets only the marker", keys == ["m1"], "\(keys)")
        }

        print(failures == 0 ? "PreferencesMigrationTests: all \(checks) passed" : "PreferencesMigrationTests: \(failures) of \(checks) FAILED")
        if checks < 17 { print("FAIL: expected at least 17 checks, ran \(checks)"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
