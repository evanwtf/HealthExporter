import Foundation
import Testing

/// The tests run inside the app (`TEST_HOST`), so `Bundle.main` is the app
/// bundle with the Info.plist that Xcode generates from `INFOPLIST_KEY_*`.
struct InfoPlistTests {

    /// Without this key, App Store Connect holds every upload at "Missing
    /// Compliance" and internal testers never get the build. The app makes no
    /// network calls and uses no encryption beyond what iOS provides.
    @Test func declaresNoNonExemptEncryption() {
        let value = Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool
        #expect(value == false)
    }
}
