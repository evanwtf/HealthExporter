# macOS Self-Hosted Runner Recovery — How-To

A recovery runbook for the `MacMiniM6_01` self-hosted GitHub Actions runner
(labels `self-hosted, macOS, ARM64`) that runs the iOS tests and builds and
uploads TestFlight releases. It replaced `MacMiniM4_01` on 2026-10-05.

Use this document when the `release-testflight.yml` workflow starts failing in
ways consistent with a missing secret, a missing private key, a stale provisioning profile, a
broken keychain ACL, or a stuck runner process. The most common trigger is a
macOS account password reset on the Mac mini (especially a reset done via
Recovery / Apple ID, where you did not know the old password), but the same
recovery steps apply whenever signing material on the runner gets lost.

## Contents

1. [Symptoms — when to use this doc](#1-symptoms--when-to-use-this-doc)
2. [Background — what a password reset breaks](#2-background--what-a-password-reset-breaks)
3. [Inventory the damage](#3-inventory-the-damage)
4. [Recovery procedure](#4-recovery-procedure)
5. [Verify end-to-end](#5-verify-end-to-end)
6. [Prevention for next time](#6-prevention-for-next-time)
7. [Reference — workflow, secrets, paths](#7-reference--workflow-secrets-paths)

---

## 1. Symptoms — when to use this doc

Any of the following in a `release-testflight.yml` run usually points here:

- The `Check required secrets` step fails with `Missing secret <NAME>`. A
  repository secret is not set, or the organization secret
  `MACOS_KEYCHAIN_PASSWORD` does not list `HealthExporter` in its selected
  repositories. See Section 7.

- The `Unlock signing keychain` step fails with
  `security: SecKeychainUnlock /Users/evanhoffman/Library/Keychains/login.keychain-db:
  The user name or passphrase you entered is not correct.` and the job exits 51
  before touching anything else. The `MACOS_KEYCHAIN_PASSWORD` GitHub secret no
  longer matches what the local keychain expects — see Section 4.1.
- The `Archive` step fails with
  `error: Revoke certificate: Your account already has an Apple Development
  signing certificate for this machine, but its private key is not installed
  in your keychain.`
- The `Archive` step fails with
  `error: No signing certificate "iOS Development" found: No "iOS Development"
  signing certificate matching team ID "94S5PZTVPY" with a private key was
  found.`
- The `Export IPA` step fails with
  `error: exportArchive No signing certificate "iOS Distribution" found`.
- The `Export IPA` step fails with `errSecInternalComponent` from `codesign`
  while re-signing `HealthExporter.app`.
- The `Install App Store profile` step fails with `No ACTIVE App Store
  profile named 'HealthExporter App Store'`. The profile does not exist or
  has expired. An Admin creates it once (Section 4.4). An HTTP 401 or 403
  from that step means the API key secrets are wrong or the key was revoked.
- The `Export IPA` step fails with `error: exportArchive Cloud signing
  permission error`. The export options were switched to automatic signing.
  An App Manager API key cannot use cloud-managed distribution certificates,
  so automatic export fails. Keep `signingStyle = manual` in
  [`ci/ExportOptions.plist`](../ci/ExportOptions.plist).
- A queued job stays queued for many minutes with `MacMiniM6_01` showing
  "Offline" in https://github.com/organizations/evanwtf/settings/actions/runners
  even though `Runner.Listener` is in `ps`.

If you only see one symptom, you may only need part of this runbook. Read
Section 3 to scope the damage before running the full procedure.

## 2. Background — what a password reset breaks

The TestFlight workflow depends on three independent things on the runner:

1. The `login.keychain-db` keychain file, unlockable with the password stored
   in the `MACOS_KEYCHAIN_PASSWORD` GitHub secret.
2. The signing certificates **and their private keys** inside that keychain
   (`Apple Development` and `Apple Distribution`, both team `94S5PZTVPY`).
3. The `HealthExporter App Store` provisioning profile. The archive signs
   automatically for development. The export signs manually
   ([`ci/ExportOptions.plist`](../ci/ExportOptions.plist)) with the runner's
   local `Apple Distribution` identity and that named profile. The workflow
   step `Install App Store profile` runs
   [`ci/install_profile.swift`](../ci/install_profile.swift), which downloads
   the ACTIVE profile by name through the App Store Connect API key and
   writes it to `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`
   on every run. The script only reads; it never creates or changes anything
   on the Apple account. The profile must name the runner's
   `Apple Distribution` cert and include both the HealthKit and the Clinical
   Health Records capabilities.

   Automatic export is not an option: an App Manager key cannot use
   cloud-managed distribution certificates, so it fails with
   `Cloud signing permission error`.

A macOS account password reset can break each of these in a different way:

- **Login keychain unlock password.** A normal "change password" from System
  Settings keeps the keychain unlock password in sync with the new account
  password. A Recovery / Apple ID reset does **not** — the keychain unlock
  password stays at the *old* macOS password. The `MACOS_KEYCHAIN_PASSWORD`
  GitHub secret tracks the keychain unlock password, not the macOS account
  password, so a Recovery reset typically leaves the secret valid.
- **Private keys.** iCloud Keychain syncs certificates across devices but
  **does not** sync the matching private keys (they are non-exportable by
  design). After a reset, the cert may come back via iCloud while the private
  key is permanently gone. `security find-identity -v -p codesigning` will
  return `0 valid identities found`.
- **Provisioning profiles.** Profile files in `~/Library/Developer/Xcode/...`
  are not encrypted by the keychain, so they usually survive on disk. But
  every profile binds to a specific cert, so once the matching cert is gone
  (or you revoke it on developer.apple.com), the profile is dead too.
  An Admin must then re-issue `HealthExporter App Store` against the new
  cert (Section 4.4).
- **Keychain partition list ACL.** New private keys imported into a keychain
  by Xcode → Manage Certificates have a restrictive default ACL that forces
  a GUI confirmation the first time a non-Xcode tool (notably `codesign` and
  `productbuild`) tries to use them. CI has no GUI, so the call fails with
  `errSecInternalComponent`.
- **Runner process.** The launchd-managed `Runner.Listener` can survive the
  reset but lose its broker connection and stop polling. The process is alive
  in `ps`, but the org's runner page shows it as Offline.

## 3. Inventory the damage

Run these on the Mac mini to figure out what is actually broken before doing
any cert work:

```sh
# 1. Is the runner process running?
ps aux | grep Runner.Listener | grep -v grep

# 2. Does the keychain still unlock?
security unlock-keychain ~/Library/Keychains/login.keychain-db
# (Type the OLD macOS password first; that is what the keychain remembers.)

# 3. Do we have any usable signing identities?
security find-identity -v -p codesigning

# 4. Which provisioning profiles are on disk?
for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
  printf '%s  ' "$(basename "$f")"
  security cms -D -i "$f" 2>/dev/null | plutil -extract Name raw -o - -
done
```

Interpreting the output:

- (1) If the process is gone or shows Offline in the org runners page, jump
  to Section 4.6 — restart the runner. To see why it lost the connection in
  the first place, check the most recent diag log:

  ```sh
  ls -lt ~/actions-runner/_diag/Runner_*.log | head -1
  tail -50 "$(ls -t ~/actions-runner/_diag/Runner_*.log | head -1)"
  ```
- (2) If `unlock-keychain` errors, the keychain file got replaced or the
  password really did change. Try the new macOS password; if that works,
  rotate the GitHub secret as described in Section 4.1.
- (3) If `0 valid identities found`, you have lost both private keys and need
  to do the full cert+profile recovery (Sections 4.2, 4.3, 4.4).
- (4) Expect `HealthExporter App Store`. The workflow downloads it on every
  run, so an old copy on disk does no harm, but you can delete copies that
  reference a revoked cert.

## 4. Recovery procedure

**Order of operations** — the full sequence assuming both private keys are
gone and the cached profile is stale (the worst case, and the case the
runbook was first written from):

| Step | What you do | Where |
| ---- | ----------- | ----- |
| 4.1 | Rotate `MACOS_KEYCHAIN_PASSWORD` if the keychain unlock password changed | Local + `gh` |
| 4.2 | Revoke the orphaned Apple Development and Apple Distribution certs | developer.apple.com → Certificates |
| 4.3 | Re-create the Apple Distribution cert and private key via Xcode → Manage Certificates | Mac mini (GUI) |
| 4.4 | An Admin creates or re-issues the `HealthExporter App Store` profile against the runner's Distribution cert | developer.apple.com → Profiles |
| 4.5 | Set the keychain partition list so `codesign` can use the new keys without a GUI prompt | Mac mini shell |
| 4.6 | Restart the runner via `~/actions-runner/svc.sh` if it is stuck | Mac mini shell |
| 5   | Dispatch the workflow and watch it green-light | `gh` |

Do these steps in order. Skip any that are already healthy per Section 3 (for
example, if `security find-identity -v -p codesigning` already lists both
identities, skip 4.2 and 4.3).

### 4.1. Rotate `MACOS_KEYCHAIN_PASSWORD` if and only if the unlock password changed

If `security unlock-keychain` only succeeds with the **new** macOS password
(i.e. the keychain unlock password was migrated by a normal "change password"
flow), update the GitHub secret to match:

```sh
gh secret set MACOS_KEYCHAIN_PASSWORD --repo evanwtf/HealthExporter
```

Otherwise — and this is the common case after a Recovery / Apple ID reset —
**do not touch this secret**. The keychain still unlocks with the old password
that the secret already holds.

### 4.2. Revoke the orphaned certificates

Go to https://developer.apple.com/account/resources/certificates/list. Revoke
every Apple Development and Apple Distribution certificate associated with
this Mac mini whose private key is missing locally. These are the ones whose
expiration dates match the runner's original provisioning date (and any
re-issues since). Do **not** revoke:

- The `Distribution Managed` cert. That one is Apple-managed via the App
  Store Connect API key and rotates on its own.
- Any cert that belongs to a different machine (e.g. a development cert tied
  to your laptop). Verify by running `security find-identity -v -p codesigning`
  on that other machine — if it lists the cert, leave it alone.

### 4.3. Re-create the certificates

On the Mac mini, open Xcode → **Settings → Accounts** → select your Apple ID →
**Manage Certificates…** → "+" → choose **Apple Distribution**. Xcode
generates a CSR, submits it via the App Store Connect API, downloads the new
cert, and imports the private key into `login.keychain-db` in one shot.

You do not need to do this for Apple Development: the TestFlight workflow
already passes `-allowProvisioningUpdates -authenticationKeyPath …` to
`xcodebuild`, which re-creates the Development cert via the App Store Connect
API key automatically on the next CI run.

Verify:

```sh
security find-identity -v -p codesigning
```

Expect two valid identities for team `94S5PZTVPY`: `Apple Development` and
`Apple Distribution`.

### 4.4. Create or renew the `HealthExporter App Store` profile

This is an Admin step in the Apple Developer portal. Nothing is installed on
the runner: the workflow downloads the profile by name on every run. Do it
once, again when the profile expires (once a year), and after the
`Apple Distribution` cert changes.

1. Check that the App ID `com.evanhoffman.HealthExporter` has both
   **HealthKit** and **HealthKit / Clinical Health Records** ticked.
2. Go to Certificates, Identifiers & Profiles → **Profiles** → **+**.
3. Choose **App Store Connect** (distribution), then the App ID
   `com.evanhoffman.HealthExporter`.
4. Choose the certificate `Apple Distribution: EVAN DAVID HOFFMAN` that the
   runner has (the one that expires 2027-05-25).
5. Name it exactly `HealthExporter App Store` and click **Generate**.

To renew, edit the existing profile, select the current cert, and save. Keep
the exact name. Then re-dispatch the dry run (Section 5).

### 4.5. Fix the keychain partition list

New private keys added by Xcode → Manage Certificates start with a
restrictive ACL that blocks `codesign` from CI. Open the gate once for every
key in the login keychain:

```sh
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k '<keychain-unlock-password>' \
  ~/Library/Keychains/login.keychain-db
```

The command dumps the updated attributes of each key it modifies — that
verbose output is normal, not an error. If macOS pops a GUI confirmation
dialog the first time you run it, click **Always Allow**.

### 4.6. Restart the runner if it is stuck

If `Runner.Listener` is alive in `ps` but the org runner page shows the
runner Offline (or queued jobs sit unpicked), bounce the service:

```sh
cd ~/actions-runner
./svc.sh stop
./svc.sh start
./svc.sh status
```

After a few seconds the runner page should flip to **Idle** and any queued
job should start. The launchd label of the service is
`actions.runner.evanwtf.MacMiniM6_01`; check it with:

```sh
launchctl print "gui/$(id -u)/actions.runner.evanwtf.MacMiniM6_01" | head -20
```

## 5. Verify end-to-end

First dispatch a dry run. It tests, archives and exports a signed IPA, but
does not upload it:

```sh
gh workflow run release-testflight.yml --repo evanwtf/HealthExporter -f upload=false
gh run watch "$(gh run list --repo evanwtf/HealthExporter \
  --workflow=release-testflight.yml --limit 1 --json databaseId \
  --jq '.[0].databaseId')" --repo evanwtf/HealthExporter
```

Steps to look at, in order: `Check required secrets` → `Run iOS tests` →
`Unlock signing keychain` → `Install App Store profile` → `Archive` →
`Export IPA`. The dry run skips
`Upload IPA for Internal TestFlight`. When those steps are green, upload the
newest tag if its upload failed (App Store Connect rejects a build number it
already has):

```sh
gh workflow run release-testflight.yml --repo evanwtf/HealthExporter --ref vX.Y.Z
```

If the upload also goes green the runner is fully recovered. Otherwise the
next merge to `main` proves it: the bump workflow dispatches the upload. End-to-end runtime is normally
~2–3 minutes when nothing is wrong (no app code changes); a from-scratch
build is closer to ~10–15 minutes.

If `Export IPA` is the only step that fails with `errSecInternalComponent`,
you skipped Section 4.5 — run it and re-dispatch.

## 6. Prevention for next time

Things that would have cut this incident from "an hour of cert rebuilding" to
"a single import" if they had been in place beforehand:

- **Export the signing identities to a `.p12` and store it somewhere safe**
  (1Password, encrypted USB, Time Machine, an offline encrypted volume). In
  Keychain Access, right-click the `Apple Distribution …` identity → **Export
  Items…** → choose `.p12`, set a strong password, save. Repeat for the
  Apple Development identity if you want to also bypass automatic
  provisioning. Restoring is one `security import … -k login.keychain-db -P
  <password> -T /usr/bin/codesign` away.
- **Disable iCloud Keychain syncing of code-signing certificates** so a
  cross-device iCloud event cannot resurrect a cert whose private key is
  gone — that resurrected-but-keyless cert is exactly what makes the portal
  refuse to re-issue automatically and forces the manual revoke step.
- **Use a Mac-mini-specific local user password manager entry** so you do not
  forget the macOS password in the first place. The keychain unlock password
  stored in `MACOS_KEYCHAIN_PASSWORD` must match the local account password
  if you ever change it from System Settings; if they drift, log in once via
  GUI and follow the "Update Keychain Password" prompt so they re-sync.
- **Consider `fastlane match`** as a longer-term solution. It stores
  encrypted certs and profiles in a private git repository so any machine can
  rehydrate the full signing state with one command. We do not use it today,
  but if you find yourself rebuilding signing material more than once, it is
  worth the migration.

## 7. Reference — workflow, secrets, paths

- Workflow: [`.github/workflows/release-testflight.yml`](../.github/workflows/release-testflight.yml).
  It has no schedule.
  [`bump-build-number.yml`](../.github/workflows/bump-build-number.yml)
  dispatches it on the new `vX.Y.Z` tag after every merge to `main`, after it
  creates the GitHub release.
- Test script: [`ci/run_ios_tests.sh`](../ci/run_ios_tests.sh)
- Export options: [`ci/ExportOptions.plist`](../ci/ExportOptions.plist)
  (`signingStyle = manual`, `signingCertificate = Apple Distribution`,
  profile `HealthExporter App Store`)
- Profile download: [`ci/install_profile.swift`](../ci/install_profile.swift)
  (read-only App Store Connect API call)
- Required secrets:
  - Organization secret `MACOS_KEYCHAIN_PASSWORD` — the login keychain unlock
    password. Its selected repositories must include `HealthExporter`.
  - Repository secrets `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`,
    `ASC_API_KEY_P8` — an App Store Connect API key with the App Manager
    role. One team key serves all the team's apps.
- Provisioning profile directory:
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`
  (modern Xcode location; the old `~/Library/MobileDevice/Provisioning Profiles/`
  is still honored but no longer the default)
- Runner directory: `~/actions-runner/` — `./svc.sh` controls the launchd
  service; runner logs are in `~/actions-runner/_diag/Runner_*.log`
- Apple Developer portal:
  - Certificates: https://developer.apple.com/account/resources/certificates/list
  - Profiles: https://developer.apple.com/account/resources/profiles/list
- Org runners page: https://github.com/organizations/evanwtf/settings/actions/runners
