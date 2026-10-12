// Download an ACTIVE provisioning profile by name from the App Store Connect
// API and install it for Xcode. Read-only: it never creates or changes
// anything on the Apple account.
//
// Usage: xcrun swift ci/install_profile.swift "<profile name>"
// Env:   ASC_KEY_PATH (the .p8 file), ASC_API_KEY_ID, ASC_API_ISSUER_ID
//
// The script never prints the key, the token or the profile content.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func makeToken(keyPath: String, keyID: String, issuerID: String) -> String {
    guard let pem = try? String(contentsOfFile: keyPath, encoding: .utf8) else {
        fail("Cannot read the API key file at ASC_KEY_PATH.")
    }
    guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
        fail("The file at ASC_KEY_PATH is not a P-256 private key in PEM form.")
    }
    let now = Int(Date().timeIntervalSince1970)
    let header: [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
    let payload: [String: Any] = [
        "iss": issuerID, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1",
    ]
    guard
        let headerJSON = try? JSONSerialization.data(withJSONObject: header),
        let payloadJSON = try? JSONSerialization.data(withJSONObject: payload)
    else {
        fail("Cannot encode the token.")
    }
    let signingInput = base64URL(headerJSON) + "." + base64URL(payloadJSON)
    guard let signature = try? key.signature(for: Data(signingInput.utf8)) else {
        fail("Cannot sign the token.")
    }
    return signingInput + "." + base64URL(signature.rawRepresentation)
}

let arguments = CommandLine.arguments
guard arguments.count == 2, !arguments[1].isEmpty else {
    fail("usage: xcrun swift ci/install_profile.swift \"<profile name>\"")
}
let profileName = arguments[1]

let env = ProcessInfo.processInfo.environment
let missing = ["ASC_KEY_PATH", "ASC_API_KEY_ID", "ASC_API_ISSUER_ID"]
    .filter { (env[$0] ?? "").isEmpty }
if !missing.isEmpty {
    fail("Missing environment variable(s): " + missing.joined(separator: ", "))
}

let token = makeToken(
    keyPath: env["ASC_KEY_PATH"]!,
    keyID: env["ASC_API_KEY_ID"]!,
    issuerID: env["ASC_API_ISSUER_ID"]!
)

var components = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/profiles")!
components.queryItems = [
    URLQueryItem(name: "filter[name]", value: profileName),
    URLQueryItem(name: "filter[profileState]", value: "ACTIVE"),
    URLQueryItem(name: "fields[profiles]", value: "name,uuid,profileContent,expirationDate"),
]
// URLComponents leaves "[" and "]" in query names; percent-encode them.
components.percentEncodedQuery = components.percentEncodedQuery?
    .replacingOccurrences(of: "[", with: "%5B")
    .replacingOccurrences(of: "]", with: "%5D")

var request = URLRequest(url: components.url!)
request.httpMethod = "GET"
request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")

let (body, response): (Data, URLResponse)
do {
    (body, response) = try await URLSession.shared.data(for: request)
} catch {
    fail("Request to the App Store Connect API failed: \(error.localizedDescription)")
}
let status = (response as? HTTPURLResponse)?.statusCode ?? 0
guard status == 200 else {
    let text = String(data: body, encoding: .utf8) ?? "<non-UTF-8 body>"
    fail("App Store Connect API returned HTTP \(status): \(text)")
}

struct ProfilesResponse: Decodable {
    struct Profile: Decodable {
        struct Attributes: Decodable {
            let name: String?
            let uuid: String?
            let profileContent: String?
            let expirationDate: String?
        }
        let attributes: Attributes
    }
    let data: [Profile]
}

guard let decoded = try? JSONDecoder().decode(ProfilesResponse.self, from: body) else {
    fail("Cannot parse the App Store Connect API response.")
}

// The API filter is not an exact match; check the name here. Take the profile
// that expires last when there are several.
typealias Attributes = ProfilesResponse.Profile.Attributes
func isUsable(_ a: Attributes) -> Bool {
    a.name == profileName && a.uuid != nil && a.profileContent != nil
}
func expiresBefore(_ a: Attributes, _ b: Attributes) -> Bool {
    (a.expirationDate ?? "") < (b.expirationDate ?? "")
}
let matches: [Attributes] = decoded.data.map { $0.attributes }
    .filter(isUsable)
    .sorted(by: expiresBefore)
guard let profile = matches.last, let uuid = profile.uuid,
      let content = profile.profileContent
else {
    fail(
        "No ACTIVE App Store profile named '\(profileName)'. An Admin must create it "
            + "in the Apple Developer portal for com.evanhoffman.HealthExporter with the "
            + "'Apple Distribution' certificate; see docs/macos-runner-recovery.md."
    )
}
guard let profileData = Data(base64Encoded: content) else {
    fail("The profileContent of '\(profileName)' is not valid base64.")
}

let directory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles")
do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try profileData.write(to: directory.appendingPathComponent(uuid + ".mobileprovision"))
} catch {
    fail("Cannot write the profile: \(error.localizedDescription)")
}

print("Installed profile '\(profileName)'")
print("  uuid:    \(uuid)")
print("  expires: \(profile.expirationDate ?? "unknown")")
