#if DEBUG
import Foundation

/// AURIE_STORE_RECOVERY_SELFTEST=1 — proves the partial-decode recovery
/// contract against the REAL `Store`, which cannot be unit-tested in the
/// offline harness because it imports UIKit.
///
/// Scenario: `auries.json` holds `[a, bad, c]` where `bad` is missing the
/// required `seed`. The app must load ONLY the survivors, and the ORIGINAL
/// three-record file must be quarantined BEFORE any survivor-only save can
/// overwrite it.
///
/// Runs on a scratch copy of the store directory's files: the real
/// auries.json is moved aside and restored, so a developer's collection is
/// never destroyed by running the selftest.
enum StoreRecoverySelftest {

    private static func rec(_ id: String, dropSeed: Bool = false) -> [String: Any] {
        var r: [String: Any] = [
            "id": id, "name": "Test\(id)", "family": "moss", "body": "round",
            "category": "food", "bornFrom": "apple",
            "parts": ["bodyId": 1, "eyesId": 1, "mouthId": 1, "limbsId": 1],
            "slots": [:] as [String: Any],
            "baseColor": ["r": 10, "g": 20, "b": 30],
            "auraColor": ["r": 40, "g": 50, "b": 60],
            "line": "hello", "traits": [] as [String], "hatchedAt": 0,
            "seed": 12345,
        ]
        if dropSeed { r.removeValue(forKey: "seed") }
        return r
    }

    static func run() {
        guard ProcessInfo.processInfo
            .environment["AURIE_STORE_RECOVERY_SELFTEST"] == "1" else { return }
        var pass = 0, fail = 0
        func check(_ name: String, _ ok: Bool) {
            if ok { pass += 1 } else { fail += 1 }
            NSLog("AURIE_STORE %@ %@", ok ? "PASS" : "FAIL", name)
        }

        let fm = FileManager.default
        let dir = Store.directory
        let live = dir.appendingPathComponent("auries.json")
        let backup = dir.appendingPathComponent("auries.corrupt.json")
        let stash = dir.appendingPathComponent("auries.selftest-stash.json")

        // Preserve whatever is really there, and start from a clean slate.
        try? fm.removeItem(at: stash)
        if fm.fileExists(atPath: live.path) {
            try? fm.moveItem(at: live, to: stash)
        }
        try? fm.removeItem(at: backup)
        defer {
            try? fm.removeItem(at: live)
            try? fm.removeItem(at: backup)
            if fm.fileExists(atPath: stash.path) {
                try? fm.moveItem(at: stash, to: live)
            }
            NSLog("AURIE_STORE DONE pass=%d fail=%d", pass, fail)
        }

        let planted = [rec("a"), rec("bad", dropSeed: true), rec("c")]
        guard let data = try? JSONSerialization.data(withJSONObject: planted),
              (try? data.write(to: live)) != nil else {
            check("could plant the [a, bad, c] fixture", false)
            return
        }

        // Load through the REAL Store.
        let store = Store()

        check("loads the two valid survivors, skips the bad record",
              store.auries.count == 2)
        check("survivors are exactly a and c",
              store.auries.map(\.id).sorted() == ["a", "c"])
        check("a partial decode is NOT treated as an unreadable file",
              store.auriesFileUnreadable == false)
        check("original file was QUARANTINED before any save",
              fm.fileExists(atPath: backup.path))

        // The quarantined copy must still hold all THREE original records,
        // including the unreadable one, so nothing is unrecoverable.
        if let bdata = try? Data(contentsOf: backup),
           let rows = try? JSONSerialization.jsonObject(with: bdata) as? [[String: Any]] {
            check("quarantined copy holds all 3 original records", rows.count == 3)
            check("quarantined copy still contains the BAD record",
                  rows.contains { $0["seed"] == nil })
        } else {
            check("quarantined copy holds all 3 original records", false)
            check("quarantined copy still contains the BAD record", false)
        }

        // Now force a survivor-only save and prove the recovery copy endures.
        store.settings.featuredAurieId = store.auries.first?.id
        if var survivor = store.auries.first {
            survivor.name = "Renamed"
            store.update(survivor)
        }
        if let ldata = try? Data(contentsOf: live),
           let rows = try? JSONSerialization.jsonObject(with: ldata) as? [[String: Any]] {
            check("live file is now survivor-only (2 records)", rows.count == 2)
        } else {
            check("live file is now survivor-only (2 records)", false)
        }
        if let bdata = try? Data(contentsOf: backup),
           let rows = try? JSONSerialization.jsonObject(with: bdata) as? [[String: Any]] {
            check("recovery copy SURVIVES the survivor-only save (still 3)",
                  rows.count == 3)
        } else {
            check("recovery copy SURVIVES the survivor-only save (still 3)", false)
        }
    }
}
#endif
