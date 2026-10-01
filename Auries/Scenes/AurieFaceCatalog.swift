import Foundation

/// The ONE place expression ids become Blender asset names.
///
/// Nothing else in the app builds a face asset string. `AurieNode` asks this
/// catalog and renders whatever it returns, so a missing or mis-named asset
/// shows up here as a validation failure instead of as a creature silently
/// wearing the wrong face — which is exactly how the first pass shipped a
/// blink that quietly displayed OPEN eyes for nine of the ten expressions.
enum AurieFaceCatalog {

    struct Face {
        let cheeks: String
        let mouth: String
        let eyes: String
        /// The catchlight sparkles, exported as their own layer so the app can
        /// slide ONLY the sparkles toward a finger (the dark eye stays put).
        /// nil when the expression has no sparkle to move (arc/heavy-lid eyes:
        /// delighted, sleepy, yawn) or the body was not re-exported with the
        /// split — the eye then simply does not track.
        let sparkles: String?
        /// Closed-eye layer for blink, or nil when blinking is meaningless
        /// (Delighted's eyes are already drawn as closed arcs).
        let blinkEyes: String?
    }

    /// Reaction faces with their own artwork. Reactions that borrow a base
    /// expression (bounce → happy, startled → surprised, curious look →
    /// curious, excited hop → delighted) deliberately have no entry: they
    /// resolve through the base table, so nothing is duplicated.
    /// "dizzy" is deliberately ABSENT. Its baked catchlight layer draws two
    /// oversized highlights per eye, which reads as a multi-pupil alien stare.
    /// Nothing in the app may request it; spinning uses Delighted's closed
    /// arcs instead. Removing it here also takes it out of `allFaceIds`, so it
    /// cannot be reached by any random or catalogue-driven path.
    static let reactionFaceIds = ["yawn", "calm"]

    /// Every face id the app can legitimately ask for.
    static var allFaceIds: [String] {
        BaseExpression.allCases.map(\.rawValue) + reactionFaceIds
    }

    /// Blink is an EYE-layer swap, never a whole second face. Measured on
    /// the exported layers: yawn/calm/worried differ from Happy's closed
    /// eyes by <9/255 and could share it, while shy, dizzy, curious, sleepy
    /// and pouty differ by 95–150 because their lids/gaze already sit
    /// elsewhere. Since a blink layer is ~4 KB, each expression keeps its
    /// own rather than trading correctness for 11 KB.
    static func face(_ id: String, body: String) -> Face? {
        guard let layers = AurieBlenderAssets.bodies[body]?.layers
        else { return nil }
        let prefix = "face_\(id)"
        guard layers["\(prefix)_eyes"] != nil else { return nil }
        return Face(cheeks: "\(prefix)_cheeks",
                    mouth: "\(prefix)_mouth",
                    eyes: "\(prefix)_eyes",
                    sparkles: layers["\(prefix)_catch"] != nil
                        ? "\(prefix)_catch" : nil,
                    blinkEyes: layers["\(prefix)_blink_eyes"] != nil
                        ? "\(prefix)_blink_eyes" : nil)
    }

    // MARK: - Validation

    struct Report {
        var missing: [String] = []          // face id -> no artwork at all
        var missingLayers: [String] = []     // face id -> incomplete set
        var missingBlink: [String] = []      // no closed-eye layer
        var ok: [String] = []
        var isComplete: Bool {
            missing.isEmpty && missingLayers.isEmpty
        }
    }

    /// Checks that every base expression and every unique reaction face
    /// resolves to a complete layer set. Blink is reported separately
    /// because Delighted legitimately has none.
    static func validate(body: String) -> Report {
        var report = Report()
        for id in allFaceIds {
            guard let face = face(id, body: body) else {
                report.missing.append(id)
                continue
            }
            let set = AurieBlenderAssets.bodies[body]?.layers ?? [:]
            let layers = [face.cheeks, face.mouth, face.eyes]
            if layers.contains(where: { set[$0] == nil }) {
                report.missingLayers.append(id)
                continue
            }
            if face.blinkEyes == nil, id != BaseExpression.delighted.rawValue {
                report.missingBlink.append(id)
            }
            report.ok.append(id)
        }
        return report
    }

    /// Called once when a Blender skin is built. DEBUG shouts about an
    /// incomplete library (a build/verification error); RELEASE stays quiet
    /// and lets the per-face fallback keep the app running.
    static func validateAndLog(body: String) {
        let r = validate(body: body)
        #if DEBUG
        NSLog("AURIE_FACES body=%@ ok=%d missing=%@ incomplete=%@ noBlink=%@",
              body, r.ok.count,
              r.missing.isEmpty ? "none" : r.missing.joined(separator: ","),
              r.missingLayers.isEmpty ? "none"
                  : r.missingLayers.joined(separator: ","),
              r.missingBlink.isEmpty ? "none"
                  : r.missingBlink.joined(separator: ","))
        assert(r.isComplete,
               "Blender face library for \(body) is incomplete: "
               + "missing \(r.missing), partial \(r.missingLayers)")
        #endif
    }
}
