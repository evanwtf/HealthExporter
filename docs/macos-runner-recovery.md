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
- The `Archive` or `Export IPA` step fails with `No profiles for
  'com.evanhoffman.HealthExporter' were found`. Automatic signing could not
  get a profile through the App Store Connect API key — check that the key
  still exists and has the App Manager role (Section 4.4).
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
3. An App Store provisioning profile for `com.evanhoffman.HealthExporter`.
   The archive and [`ci/ExportOptions.plist`](../ci/ExportOptions.plist) both
   use automatic signing, so `xcodebuild` fetches or creates the
   Xcode-managed `iOS Team Store Provisioning Profile:
   com.evanhoffman.HealthExporter` through the App Store Connect API key
   (`-allowProvisioningUpdates`). It caches the profile in
   `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. The profile
   must include both the HealthKit and the Clinical Health Records
   capabilities. Automatic signing was once seen to return a stale cached
   profile without one of them; App Store Connect ingest then rejects the
   IPA. Section 4.4 covers that case.

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
  Automatic signing re-creates the Xcode-managed profile on the next run.
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
- (4) Expect `iOS Team Store Provisioning Profile:
  com.evanhoffman.HealthExporter`. If it appears more than once, or the
  export fails after a cert change, delete the cached copies (Section 4.4).
  A leftover `HealthExporter App Store` profile is from the old manual
  export and is unused; you can delete it.

## 4. Recovery procedure

**Order of operations** — the full sequence assuming both private keys are
gone and the cached profile is stale (the worst case, and the case the
runbook was first written from):

| Step | What you do | Where |
| ---- | ----------- | ----- |
| 4.1 | Rotate `MACOS_KEYCHAIN_PASSWORD` if the keychain unlock password changed | Local + `gh` |
| 4.2 | Revoke the orphaned Apple Development and Apple Distribution certs | developer.apple.com → Certificates |
| 4.3 | Re-create the Apple Distribution cert and private key via Xcode → Manage Certificates | Mac mini (GUI) |
| 4.4 | Check the App ID capabilities and the API key, then delete stale cached profiles | developer.apple.com, App Store Connect, Mac mini |
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

### 4.4. Let automatic signing re-create the profile

There is no profile to install by hand. `xcodebuild` uses the App Store
Connect API key to fetch or create the Xcode-managed App Store profile for
the current `Apple Distribution` cert. Check three things:

1. On https://developer.apple.com/account/resources/identifiers/list, the App
   ID `com.evanhoffman.HealthExporter` has both **HealthKit** and
   **HealthKit / Clinical Health Records** ticked.
2. In App Store Connect → Users and Access → Integrations, the API key in the
   `ASC_API_KEY_ID` secret is active and has the **App Manager** role.
3. On the Mac mini, no stale cached profile is left. Find the cached copies
   with the loop from Section 3 and delete each file whose name is
   `iOS Team Store Provisioning Profile: com.evanhoffman.HealthExporter` or
   `HealthExporter App Store`:

   ```sh
   rm ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<uuid>.mobileprovision
   ```

   The next run downloads a fresh profile.

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
`Unlock signing keychain` → `Archive` → `Export IPA`. The dry run skips
`Upload IPA for Internal TestFlight`. When those steps are green, dispatch
again without `-f upload=false` to upload. If the upload also goes green the
runner is fully recovered. End-to-end runtime is normally
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

- Workflow: [`.github/workflows/release-testflight.yml`](../.github/workflows/release-testflight.yml)
- Test script: [`ci/run_ios_tests.sh`](../ci/run_ios_tests.sh)
- Export options: [`ci/ExportOptions.plist`](../ci/ExportOptions.plist)
  (`signingStyle = automatic`, no named profile)
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
