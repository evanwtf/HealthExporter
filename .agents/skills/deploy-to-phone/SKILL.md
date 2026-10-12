---
name: deploy-to-phone
description: Build the HealthExporter iOS app (Debug) from the current checkout and install it on the owner's connected iPhone over USB. Picks the Xcode whose iOS SDK matches the device, signs with the development identity, and installs with devicectl. Use when the user says "deploy to my phone", "build and install on my iPhone", "run this on my device", or similar.
argument-hint: [branch-or-ref] (optional; defaults to the current branch)
allowed-tools: Bash, Read, Grep
---

# Build and install HealthExporter on the iPhone (USB)

This skill builds a **Debug** build of the app from the working tree and installs
it on the owner's connected iPhone. It is a manual test path, not a release path.
TestFlight builds come from `release-testflight.yml` in CI.

HealthKit and Clinical Health Records need a real device. The simulator covers
them only in part, so this skill is the main way to test the export flow by hand.

## Match Xcode to the device iOS

A Debug build from an Xcode **older** than the device's iOS can hang at launch or
crash with `EXC_BAD_ACCESS` at `0x0`. The owner's phone can run a beta iOS. Do not
assume that the `xcode-select` default is correct: it is usually the stable Xcode.

Rule: use the Xcode whose iOS SDK is **equal to or newer than** the device's iOS.

## Steps

### 1. Find the checkout

- Default: build the current branch (`git rev-parse --abbrev-ref HEAD`).
- If the user gives a branch or a ref:
  1. Run `git status --porcelain`.
  2. If the tree is clean, run `git checkout <ref>`.
  3. If the tree is dirty, stop and ask. Do not stash or discard the user's work.

### 2. Find the device

```bash
xcrun devicectl list devices    # coredevice UUID; the iPhone shows "available (paired)"
xcrun xctrace list devices      # "<name> (<iOS version>) (<hardware UDID>)"
```

Record three values for the physical iPhone:

- the **coredevice UUID** (the first UUID column from `devicectl`), for the install;
- the **hardware UDID** (from `xctrace`), for `-destination id=`;
- the **iOS version** (from `xctrace`), for the Xcode choice.

Stop and ask the user when:

- no physical iPhone is paired and available: ask them to connect and unlock it;
- more than one physical iPhone is available: ask which one to use.

### 3. Pick the Xcode

```bash
ls -d /Applications/Xcode*.app
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -showsdks | grep iphoneos
```

Choose the Xcode whose `iphoneos` SDK is equal to or newer than the device iOS.
Set it with `DEVELOPER_DIR` for this build only. Do **not** run `xcode-select -s`:
the stable Xcode stays the default.

### 4. Prepare the phone

Tell the user to unlock the phone and keep it unlocked. On the first connection,
the toolchain must turn on the developer services.

### 5. Build (Debug, device destination, automatic signing)

```bash
DEVELOPER_DIR=<chosen Xcode>/Contents/Developer \
  xcodebuild build \
  -project HealthExporter.xcodeproj -scheme HealthExporter -configuration Debug \
  -destination "id=<HARDWARE-UDID>" \
  -derivedDataPath "$SCRATCH/he-device-build" \
  -allowProvisioningUpdates
```

- Put `-derivedDataPath` in the session scratchpad, not in the repo.
- Automatic signing uses the development identity of the team in the project.
- Filter the output for `error:`, `BUILD SUCCEEDED`, `BUILD FAILED` and `CodeSign`.

### 6. Install over USB

```bash
xcrun devicectl device install app --device <COREDEVICE-UUID> \
  "$SCRATCH/he-device-build/Build/Products/Debug-iphoneos/HealthExporter.app"
```

The install is good when the output shows `App installed:` and
`bundleID: com.evanhoffman.HealthExporter`.

### 7. Report

Tell the user:

- the build is installed, with the branch and the commit;
- to start the app from the home screen (a Debug build runs without Xcode);
- the Debug build **replaces** the TestFlight build on the phone until they
  install from TestFlight again;
- HealthKit read access belongs to the bundle ID, so the access they gave before
  stays.

## Failure modes

- **The app hangs at launch, or crashes with `EXC_BAD_ACCESS` at `0x0`:** the Xcode
  is older than the device iOS. Build again with a newer Xcode through
  `DEVELOPER_DIR`.
- **A signing or provisioning error:** keep `-allowProvisioningUpdates`. The
  chosen Xcode must have the owner's Apple ID and the development identity.
- **`devicectl` does not find the device:** the phone is locked or does not trust
  the Mac. Unlock it, and pair it again.
- **The export shows no lab results:** Clinical Health Records needs a health
  records account on the phone. This is a data condition, not a build failure.
