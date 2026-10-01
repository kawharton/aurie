import Foundation

/// Where the RevenueCat PUBLIC SDK key comes from, and the one place that
/// decides whether purchases are available at all.
///
/// The key is injected by build settings, never by source:
///
///   Config/AurieConfig.xcconfig  (TRACKED, the target's base config)
///     `#include?` Config/LocalSecrets.xcconfig  (GITIGNORED, machine-local)
///     REVENUECAT_API_KEY[config=Debug]   = $(REVENUECAT_TEST_API_KEY)
///     REVENUECAT_API_KEY[config=Release] = $(REVENUECAT_PRODUCTION_API_KEY)
///   -> Info.plist `RevenueCatAPIKey` = $(REVENUECAT_API_KEY)
///
/// RELEASE never references the Test Store key, so a Test Store key cannot
/// ship even when one is present on the building machine. A missing or empty
/// key is SAFE: purchases report themselves unavailable instead of failing
/// part-way through a transaction.
enum PurchaseConfiguration {

    /// RevenueCat's Test Store keys carry this prefix.
    private static let testStoreKeyPrefix = "test_"

    /// The usable key for THIS build configuration, or nil when purchases
    /// should be unavailable.
    static var apiKey: String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey")
                   as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty, or an unsubstituted "$(...)" placeholder when no xcconfig
        // value was supplied (e.g. a fresh clone with no LocalSecrets).
        guard !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
        #if !DEBUG
        // Belt and braces. The xcconfig already keeps the Test Store key out
        // of Release; this refuses it a second time at runtime in case the
        // build settings are ever rewired by hand.
        guard !raw.hasPrefix(testStoreKeyPrefix) else { return nil }
        #endif
        return raw
    }

    /// True when this build is talking to RevenueCat's Test Store rather than
    /// the real App Store. Used only for developer-facing labelling.
    static var isTestStore: Bool {
        apiKey?.hasPrefix(testStoreKeyPrefix) ?? false
    }
}
