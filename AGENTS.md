# Repository Guidelines

## Project Structure & Module Organization
`HealthExporter/HealthExporter/` contains the app source: SwiftUI views (`LaunchView.swift`, `DataSelectionView.swift`, `SettingsView.swift`), managers (`HealthKitManager.swift`, `SettingsManager.swift`), data model and registry (`HealthSampleTypes.swift`, `HealthMetricConfig.swift`, `LabMetricRegistry.swift`), pure logic (`ExportLogic.swift`, `LabSelection.swift`), and CSV output (`CSVGenerator.swift`, `CSVFile.swift`, `ExportSize.swift`). Tests live in `HealthExporterTests/`. Keep user-facing docs in `docs/`, with feature-specific notes under subfolders such as `docs/a1c/`. Store screenshots and marketing assets in `assets/`. Project configuration is in `HealthExporter.xcodeproj/`; there is no workspace and no Swift package. `CLAUDE.md`, `GEMINI.md` and `.github/copilot-instructions.md` are symlinks to this file — edit `AGENTS.md`. Agent skills live in `.agents/skills/`; `.claude/skills` is a symlink to that folder.

## Architecture Notes
Navigation flow: `HealthExporterApp` (`NavigationStack`) → `LaunchView` (welcome screen; `Choose Data` button, Settings gear in the toolbar) → `DataSelectionView`; `SettingsView` is presented as a sheet from the welcome screen. `HealthExporterTests/ScreenshotTests.swift` renders each screen in light and dark mode, at the simulator's full screen size, and attaches PNGs to the CI result bundle (`test-results` artifact). CI runs on the newest iPhone Pro Max simulator, so the images are 1320 × 2868 or the current 6.9-inch size: the iPhone size that App Store Connect requires. `ci/export_screenshots.sh` copies them, named by screen (for example `08-data-selection-mixed-light.png`), into the `screenshots` artifact: `gh run download <run-id> -n screenshots`. The Settings screenshots hide the simulator-only "Testing" section (`ScreenshotTests` passes `showsTestingTools: false` to `SettingsView`), so they show the shipped app.

Key components:

| File | Role |
|------|------|
| `HealthKitManager.swift` | The app's one `HKHealthStore` (`HealthKitManager.shared`), behind the `HealthDataStore` protocol. Async `HKSampleQueryDescriptor` queries for quantity samples and lab-result clinical records. `HealthKitQueryHelpers.readTypes` builds the read set from the selected metrics only |
| `ExportDataLoader.swift` | Fetches the selected metrics in a task group, one result per metric, so a failed metric does not discard the others (#112). Filters glucose below 20 mg/dL before the record limit (#113). Builds the partial-failure notice and the blocking error text. On iOS 27 it reads each type's limited-history start (`earliestAuthorizedSampleDates`) and builds the access-limit notice. Tests inject a fake `HealthDataStore` |
| `HealthMetricConfig.swift` | Built-in metric registry (`HealthMetrics`) for the always-available metrics (weight, steps, glucose) |
| `LabMetricRegistry.swift` | Single source of truth for lab metrics: `LabPanel` groupings, `LabMetric` records (id == primary LOINC; `alternateLoincCodes` also match records), and `LabMetricRegistry.all`. Adding a lab is a single append here |
| `HealthSampleTypes.swift` | `GlucoseSampleMgDl`, generic `LabResultSample`, `LOINCCode` constants, and `FHIRLabResultParser` |
| `ExportLogic.swift` | Pure logic: `isExportEnabled(...,hasSelectedLabs:)`, `resolveLabMetrics(selectedPanels:favoriteCodes:registry:)`, date-range/limit helpers, fetch-error ordering, filename generation |
| `SettingsManager.swift` | `@Observable`. Persists unit and format preferences plus `selectedLabPanels` and `favoriteLabCodes` in `UserDefaults`, in `didSet`; the keys (`SettingsManager.Key`) and value formats must not change. Takes the `UserDefaults` in its initializer (default `.standard`), so tests use a suite of their own. Runs the one-time legacy `exportA1C` → `favoriteLabCodes` migration. The app holds one instance in `@State`; views take it as `@Bindable` or a plain `let` |
| `LabSelection.swift` | The lab selection rules: a lab is selected through its panel or on its own (a favorite). A panel toggle changes the panels only, so it never clears labs selected one by one (#115) |
| `CSVGenerator.swift` | Converts samples to CSV with unit conversion, date formatting, and sort order. `appendLabResultRows` uses per-metric `LabMetric.valuePrecision`. `makeFile` is `@concurrent`: it builds the export once, off the main actor, and checks for cancellation before each metric and every `rowsPerCancellationCheck` rows |
| `CSVFile.swift` | The built export: the CSV text, its row count and its UTF-8 byte count. `Transferable` (`.commaSeparatedText`), so `fileExporter(item:)` writes it |
| `ExportSize.swift` | The exact row and byte count of a built export, the confirmation thresholds (500 rows or 1 MB) and the alert text |
| `DataSelectionView.swift` | "Choose Data": a two-column grid of category tiles (Weight, Steps, Blood Glucose, Vitals, then one tile per `LabPanel`), each a `Toggle` styled by `CategoryTileToggleStyle`. The Vitals and lab-panel tiles open `SelectionDetailView` for per-vital and per-lab toggles (individual labs are saved as favorites). The date range and Export CSV sit in a `.safeAreaBar` footer. `exportEnabled` is a computed property of the selection and the date range (#120). Also the export task, the progress overlay with its Cancel button, and the exporter state |
| `HealthCategory.swift` | The tile categories with their SF Symbol and category color (asset catalog `Category*` colors) |

Lab support (including A1C) uses Clinical Health Records via `HKClinicalTypeIdentifier.labResultRecord` and the LOINC code on each `LabMetric`; see `docs/a1c/` for the registry-driven implementation details.

## Build, Test, and Development Commands
Open the project in Xcode for day-to-day work:

```bash
open HealthExporter.xcodeproj
```

The checks to run before a push are in "Verification". The unit tests run in CI.

HealthKit and Clinical Records need a physical device, and the simulator covers them only in part. To install a Debug build on the owner's iPhone, use the `deploy-to-phone` skill (`.agents/skills/deploy-to-phone/SKILL.md`).

## Verification
Run these checks before you push:

```bash
ci/lint_swift.sh
xcodebuild build-for-testing -project HealthExporter.xcodeproj -scheme HealthExporter -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
uv run ruff format --check . && uv run ruff check . && uv run mypy && uv run pytest -rs
uv run scripts/changelog.py check
pre-commit run --all-files
```

- `ci/lint_swift.sh` runs SwiftFormat and SwiftLint (`--strict`) on `HealthExporter/` and `HealthExporterTests/`. It installs a missing tool with Homebrew. CI runs it before the tests, and a finding fails the job. To fix the format, run `swiftformat HealthExporter HealthExporterTests`.
- `build-for-testing` compiles the app and the tests. It does not start a simulator. The build must have 0 errors and 0 Swift warnings.
- The `uv run` line checks the Python scripts in `scripts/`. Run it when you change them.
- `scripts/changelog.py check` checks `docs/changelog.md`. Add `--require-unreleased` on a pull request that cuts a release.
- `pre-commit run --all-files` runs every hook in `.pre-commit-config.yaml`. Install pre-commit once per machine, and the hook once per clone: `uv tool install pre-commit && pre-commit install`. Do not use `uvx`: the hook then calls Python from the uvx cache, and it breaks when that cache is cleaned.
- `pre-commit install` refuses while `core.hooksPath` is set. Run `git config --local --unset-all core.hooksPath`, then run `pre-commit install` again.

The unit tests and the screenshots run in CI on the shared macOS runner. Do not run them on a laptop. The runner is shared with other repos, so batch your changes: a branch should need few CI runs.

If you change only docs or agent instructions, check the diff and say that you did not run the checks.

## Export Flow
The app is read-only with respect to HealthKit in production. `ExportDataLoader.requestAuthorization(for:)` calls `requestAuthorization(toShare: [], read: ...)` with the types of the selected metrics only. It includes the clinical-records read type only when labs are selected.

Export sequence:
1. User selects built-in metric toggles, panel/favorite labs, and a date range in `DataSelectionView`.
2. `ExportLogic.resolveLabMetrics(selectedPanels:favoriteCodes:)` produces the deduplicated list of `LabMetric`s to fetch.
3. `DataSelectionView` builds an `ExportRequest` and requests HealthKit read access for the selected metrics.
4. `ExportDataLoader.load` fetches the selected metrics in parallel; lab results come from a single clinical-records query. If some metrics fail, the export continues with the others. If every metric fails, or no data loaded, the export stops with an error. On iOS 27 a user can grant read access that starts at a date (`HKHealthStore.earliestAuthorizedSampleDate(for:)`). When that date is after the export's start, or the export has no start date, `ExportFetchResult.accessLimitNotice()` gives one line per metric.
5. `CSVGenerator.makeFile(from:...)` builds the CSV once, off the main actor (#111). It consumes the fetch result and releases each sample array as its rows are written. The result is a `CSVFile` with the exact row and byte count.
6. If the file has more than 500 rows or 1 MB, some metrics failed, or access to some metrics starts late, an alert gives the exact size, names each failed metric and gives each access start date. Cancel drops the file.
7. SwiftUI `.fileExporter(isPresented:item:contentTypes:defaultFilename:onCompletion:onCancellation:)` presents the Files picker with the `CSVFile`. The filename comes from `ExportLogic.exportFilename`.
8. `exportFile` is cleared after the export, a failure or a cancel in the picker.

Steps 3 to 5 run in one `Task` (`exportTask`) behind the "Preparing export..." overlay. Its Cancel button calls `cancelExport()`: it cancels the task and clears the pending file, and the screen returns to the selection with no alert. After each step, a cancelled task returns without changing the view state. `onDisappear` cancels the same way.

Keep this flow and its surrounding privacy copy aligned whenever export behavior changes.

## Coding Style & Naming Conventions
Follow existing Swift conventions: 4-space indentation, one top-level type per file, `UpperCamelCase` for types, `lowerCamelCase` for properties and methods. Prefer small SwiftUI views and move reusable logic into managers or helper types. Keep comments sparse and only where intent is not obvious. Match current file naming: view types end in `View`, managers end in `Manager`, tests end in `Tests`. When adding metrics, route availability through `HealthMetricConfig.swift`.

## Implementation Patterns
When adding a built-in HealthKit metric (e.g. a new quantity type):
1. Update `HealthMetricConfig.swift`.
2. Add the HealthKit type to `HealthKitQueryHelpers.readTypes`, and a case to `ExportMetric` and `ExportRequest` in `ExportDataLoader.swift`.
3. Add the toggle and selection handling in `DataSelectionView`.
4. Persist the setting in `SettingsManager`.
5. Extend `CSVGenerator`.
6. Add tests and docs in the same change.

When adding a new lab (Clinical Health Records / LOINC-coded observation):
1. Add the LOINC constant in `LOINCCode` if needed.
2. Append a `LabMetric` to `LabMetricRegistry.all` with the correct `LabPanel` group and `valuePrecision`. Put other LOINC codes for the same measurement in `alternateLoincCodes`; never change an existing `loincCode`, because favorites are keyed on it. A code must belong to one metric only.
3. No UI, fetch, or CSV code changes are required — the favorites/panel toggles, single clinical-records query, and registry-driven CSV rendering pick it up automatically.
4. Add tests (and a CSV byte-pinning test if exact output matters) and docs in the same change.

Memory management matters because HealthKit datasets can be large:
- Release fetched sample arrays immediately after CSV generation, for example `weightSamples = nil`. `CSVGenerator.makeFile` takes the fetch result `consuming` for this reason.
- Clear `exportFile` after the export, a failure, or a cancel.
- Prefer append-style CSV generation and avoid unnecessary intermediate allocations.
- Profile memory if a change could expand retained sample data.

CSV format details:
- Every export begins with `CSVGenerator.csvDisclaimer` (three `### `-prefixed lines) followed by the column header on the next line. A disclaimer line holds no comma or double quote: spreadsheets do not skip `### ` lines and would split one into columns (`disclaimer_eachLineIsOneCSVField`). Use `CSVGenerator.csvPreamble` (disclaimer + header + newline) as the starting buffer.
- Columns are `Date,Metric,LOINC,Value,Unit,Source,Meal Time`; every row has all seven fields
- The `LOINC` column carries the LOINC code found in the clinical record for lab rows and is empty for HealthKit-native metrics (weight, steps, glucose, vitals)
- The `Meal Time` column is `Before Meal` or `After Meal` for glucose rows tagged with `HKMetadataKeyBloodGlucoseMealTime`, and empty for untagged glucose rows and all other metrics
- Date formats come from `DateFormatOption`
- Sort order comes from `SortOrder`
- Weight precision is 2 decimals
- Lab precision is per-metric, sourced from `LabMetric.valuePrecision` (A1C renders to 2 decimals)
- Filename format is `HealthExporter_YYYY-MM-DD_HHMMSS.csv` (see `ExportLogic.exportFilename`)
- Default units are Fahrenheit and pounds

## Testing Guidelines
Unit tests use Swift Testing (`import Testing`): a suite is a `struct` (or a `final class` when it needs `deinit` as teardown), each test is a `@Test` function, and checks use `#expect` and `#require`. Use `@Test(arguments:)` when one check runs over a table of inputs. Only `ScreenshotTests.swift` uses `XCTest`, because it attaches PNGs with `XCTAttachment`. Add tests in `HealthExporterTests/` with filenames like `FeatureNameTests.swift`. `ci/run_ios_tests.sh` prints one total for both frameworks (`Test summary: N tests, ...`) from the result bundle. Cover CSV formatting, date filtering, unit conversion, and metric availability logic. The tests run in CI. Before a push, compile them with the `build-for-testing` command in "Verification".

## CI and releases
Runners are named by their labels only: Linux jobs run on `[self-hosted, Linux, X64]`, and macOS jobs on `[self-hosted, macOS, ARM64]`. The macOS runner is shared with other repos. Nothing runs from a laptop.

Workflows:
- `iOS Tests` (`ios-tests.yml`). The `Detect iOS changes` job lists the pull request's files with `gh api`. When every changed path is in `docs/`, `assets/`, `*.md`, `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md` or `.github/dependabot.yml`, or is a Python script or Python setting (`scripts/`, `pyproject.toml`, `uv.lock`, `.python-version`), `.gitleaksignore`, `.pre-commit-config.yaml`, `ci/appstore-screenshots.txt` or a Linux-only workflow (`appstore-screenshots`, `bump-build-number`, `changelog`, `gitleaks`, `promote-testflight-external`, `publish-release`, `scripts`), the workflow skips the tests. If that job fails, the tests run. The test job is named `iOS tests`, and the ruleset on `main` names it as a required check, with `iOS tests (fork guard)`. Do not rename either job. It runs `ci/lint_swift.sh`, then `ci/run_ios_tests.sh` on the newest iPhone Pro Max simulator, then `ci/export_screenshots.sh`, which uploads the `screenshots` artifact. The tests run after a lint failure too, so one run reports both. A new push to a pull request cancels the old run. A push to `main` does not run the tests: each release merge dispatches `release-testflight.yml`, which runs them on the release tag.
- A fork pull request never runs on the macOS runner, because the runner holds a signing keychain. When it changes iOS paths, the `iOS tests (fork guard)` job fails with "A maintainer must push this branch to the repo to run the tests."
- `ci/run_ios_tests.sh` probes `xcrun simctl` with a 30-second watchdog. When CoreSimulator does not respond, the job fails in about 5 minutes; see `docs/macos-runner-recovery.md`, section 8. Every job has `timeout-minutes`: 45 for the tests, 90 for TestFlight, 15 for the App Store screenshots, 10 for other Linux jobs.
- `Scripts` (`scripts.yml`, Linux) runs on changes to `scripts/`, `pyproject.toml`, `uv.lock` or `project.pbxproj`, and by dispatch. It runs `uv sync --frozen`, `ruff format --check`, `ruff check`, `mypy` (strict) and `pytest -rs`, and fails on a skipped test. It also runs `scripts/check_version.py`. Run the same checks locally: `uv run ruff format --check . && uv run ruff check . && uv run mypy && uv run pytest -rs`.
- `Gitleaks` (`gitleaks.yml`, Linux) scans the new commits of every pull request and push for secrets, with a pinned gitleaks release. Known false positives go in `.gitleaksignore`.
- `Changelog` (`changelog.yml`, Linux) checks `docs/changelog.md` on every pull request, with no paths filter. A pull request labeled `skip-release` gets `scripts/changelog.py check`. Every other pull request gets `check --require-unreleased`, which fails when `## Unreleased` is empty. A label change reruns the check, but not the iOS tests. The job has no concurrency group: GitHub judges a required check by its newest run, and a cancelled newer run once blocked a merge (#136). Do not rename the job.
- The ruleset on `main` requires the `iOS tests`, `iOS tests (fork guard)`, `Gitleaks` and `Changelog` checks. A pull request must be up to date with `main` before it merges.
- Dependabot (`.github/dependabot.yml`) updates the GitHub Actions monthly, with the `skip-release` label.

Releases:
- Every pull request merged to `main` cuts a release unless it has the `skip-release` label. `bump-build-number.yml` runs on `pull_request_target` from `main`, on the Linux runner. It never runs code from the pull request.
- The label on the merged pull request picks the version part. Apply exactly one before you merge (the pull request template lists them):
  - `semver:patch`: a fix or small change (2.5.4 → 2.5.5). No label also means a patch.
  - `semver:minor`: a layout change (2.5.4 → 2.6.0).
  - `semver:major`: a major change (→ 3.0.0).
  - `skip-release`: docs, CI or tooling only. No bump, no commit, no tag, no release and no TestFlight upload.
  - `skip-release` with any `semver:*` label fails the job.
- The release job:
  1. `scripts/changelog.py check --require-unreleased` fails when `## Unreleased` in `docs/changelog.md` is empty.
  2. `scripts/bump_version.py` replaces every `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` entry in `project.pbxproj`.
  3. `scripts/check_version.py --tag vX.Y.Z` fails when the entries disagree or the tag is not `v` + `MARKETING_VERSION`.
  4. `scripts/changelog.py release` renames `## Unreleased` to `## vX.Y.Z (build N), YYYY-MM-DD` (the UTC date) and adds a new, empty `## Unreleased` above it. `scripts/changelog.py notes` writes that section as the release notes.
  5. It commits `project.pbxproj` and `docs/changelog.md` as `Release vX.Y.Z (build N)`, with `Source merge: #N (title)` and `[skip ci]`.
  6. It pushes the commit and the tag with one `git push --atomic`.
  7. It creates the GitHub release from the notes, plus a "Full Changelog" compare link from the previous tag, and dispatches `release-testflight.yml` on the tag.
- Every refusal happens before the push, so a refused release pushes nothing.
- If `main` holds a release commit whose version has no tag, the "Detect stranded release" step tags that commit instead of bumping again. The notes come from `docs/changelog.md` in that commit, and the job writes them before it pushes the tag. The release step skips a release that already exists.
- Never edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` by hand, and never push a `v*` tag by hand. `publish-release.yml` is only a fallback for a tag pushed by hand. It takes the notes from `docs/changelog.md` at the tag, and it refuses to publish a version with no section.

Changelog (`docs/changelog.md`):
- The file is the one source of release notes: the GitHub release and the TestFlight "What to Test" notes both come from it.
- Layout: `# Changelog`, one short paragraph, `## Unreleased`, then one `## vX.Y.Z (build N), YYYY-MM-DD` section per version, newest first. A `---` line after the last section starts the footer, which is in no section.
- A pull request that cuts a release adds its lines under `## Unreleased`. Only the release job writes a version heading.
- Testers read the notes. Write one plain sentence or two after each `- `, for a user. No Markdown links, backticks, bold, `<` or `>`: `check` fails on them. App Store Connect refuses `<` and `>` in What's New as markup, so write "more than" or "less than".
- HTML comments (`<!-- ... -->`) are removed before the notes are used and before the empty check. Put notes for developers there.
- A section is at most 4000 characters after the comments are removed, the TestFlight limit.
- `scripts/changelog.py check` also fails on a missing or second `## Unreleased`, a malformed heading, a version that appears twice, and versions out of order.
- `RELEASE_DEPLOY_KEY` is optional. When the secret is set, the release job checks out and pushes with that deploy key, which can bypass the ruleset on `main`. When it is not set, the job pushes with `GITHUB_TOKEN`. Add the key before the ruleset requires status checks; `GITHUB_TOKEN` cannot bypass them.
- Land changes through one pull request per work session. Do not push directly to `main`.

TestFlight:
- `release-testflight.yml` tests, archives, exports and uploads to TestFlight on the macOS runner. After the tests it uploads the `screenshots` artifact, as `ios-tests.yml` does, so the release tag's run holds screenshots with the release's version number. Dry run (test, archive and export; no upload): `gh workflow run release-testflight.yml --repo evanwtf/HealthExporter -f upload=false`.
- After the upload, `scripts/changelog.py notes` writes the version's section of `docs/changelog.md`, and `scripts/update_testflight_notes.py` sets it as the "What to Test" notes. It targets the exact build number and version, and retries 10 times at 30-second intervals while App Store Connect lists the build. When the version has no section (a tag from before the changelog), the job logs a warning and the build has no notes.
- External testers: `gh workflow run promote-testflight-external.yml --repo evanwtf/HealthExporter -f build=<N>` adds a processed build to the external group (`External Hoffgroup`) and submits it for Beta App Review. Use `-f group=<name>` for one group, and `-f submit_review=false` to skip the review. The script is `scripts/promote_testflight_external.py`; `--inspect` changes nothing.
- The TestFlight job needs the repository secrets `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` and `ASC_API_KEY_P8` (an App Store Connect API key with the App Manager role; one team key serves all the team's apps), and the organization secret `MACOS_KEYCHAIN_PASSWORD` (the runner's login keychain), whose selected repositories must include `HealthExporter`. The archive signs automatically for development. The export signs manually with the runner's `Apple Distribution` identity and the `HealthExporter App Store` profile, which `ci/install_profile.swift` downloads by name on every run; an Admin creates or renews that profile in the developer portal (see `docs/macos-runner-recovery.md`). The cleanup step deletes the API key, restores the keychain's lock settings and locks it, even when the job fails.

App Store screenshots:
- `ci/appstore-screenshots.txt` is the one place where the App Store set is chosen: one screenshot name per line, in store order, without `.png`. `#` starts a comment.
- The images come from the `screenshots` artifact of a CI run. By default the workflow takes the newest successful `release-testflight.yml` run on the tag `v<version>`, and it fails when there is none. Pass `-f run_id=<id>` to use another run, for example an `iOS tests` run. The workflow logs the run and the files it used.
- The owner starts each upload. Dry run (the default): `gh workflow run appstore-screenshots.yml --repo evanwtf/HealthExporter -f version=2.5.5`. Upload: `gh workflow run appstore-screenshots.yml --repo evanwtf/HealthExporter -f version=2.5.5 -f dry_run=false`. It uploads only when `dry_run=false`.
- `appstore-screenshots.yml` runs on the Linux runner. `scripts/upload_appstore_screenshots.py` checks the set before any write. It refuses a name with no file, a size with no App Store slot (1320 × 2868 and 1290 × 2796 map to `APP_IPHONE_67`), an image with an alpha channel, images of more than one display type, more than 10 images, a version that is missing or not editable, and a locale with no localization.
- After the checks it deletes the screenshots in the version's 6.9-inch iPhone set, uploads the manifest's images in order, waits until Apple marks each one delivered, and sets the order. The version must be editable (Prepare for Submission). The script keeps `httpx` logging at WARNING: the upload URLs are pre-signed.

## Commit & Pull Request Guidelines
Use short, imperative commit subjects such as `Fix: clear csvContent on export failure to free memory` or `Update docs to match current codebase`. Only the release job writes `Release vX.Y.Z (build N)` commits. Keep commits focused. PRs should describe the user-visible change, list testing performed, link related issues, and include screenshots for SwiftUI/UI updates. Note any device-only validation when HealthKit behavior cannot be reproduced in CI.
When posting text blobs to GitHub, always write the content to a temporary file first and pass that file to the CLI. Use this for issue bodies, PR descriptions, comments, and similar multi-line text to avoid string-quoting problems.

## PR Labels
`bump-build-number.yml` reads the labels of the merged pull request. Give each pull request exactly one of these labels:

- `semver:patch`: a patch release (2.4.9 → 2.4.10). A pull request with no release label also gets a patch release.
- `semver:minor`: any layout change (2.4.9 → 2.5.0).
- `semver:major`: a major change (→ 3.0.0).
- `skip-release`: docs, CI or tooling only. The merge does not bump the version, tag a release or upload to TestFlight.

Never put `skip-release` and a `semver:*` label on the same pull request. The release job fails when it finds both.

A pull request without `skip-release` cuts a release, so it must add lines under `## Unreleased` in `docs/changelog.md`. The `Changelog` check fails when `## Unreleased` is empty, and the release job refuses too. A `skip-release` pull request needs no lines.

## Security & Configuration Tips
Do not commit real secrets; use `Secrets.plist.example` as the template. Keep HealthKit data on-device, avoid logging sensitive values, and preserve the privacy-first design.

The privacy policy has two copies: `PrivacyPolicy.swift` (shown in Settings) and `docs/privacy-policy.md` (the public web page). `PrivacyPolicyTests` fails when a line differs, so change both in one commit and update `lastUpdated` and the web date. When a change alters what the app reads, stores, logs or sends, update the policy in the same pull request. Never log a health value or date, even as `.private`.

Required capabilities and configuration:
- HealthKit is always required.
- Clinical Health Records is required for lab-result export (any LOINC-coded metric, including A1C).
- Usage descriptions are set via build settings: `NSHealthShareUsageDescription`, `NSHealthClinicalHealthRecordsShareUsageDescription`, and `NSHealthUpdateUsageDescription`.
- `ITSAppUsesNonExemptEncryption = NO` (`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption`) answers the export-compliance question for every upload. Without it, App Store Connect holds each build at "Missing Compliance" and internal testers do not get it. `InfoPlistTests` pins the value. Change it only if the app starts to use non-exempt encryption.
- Keep `NSHealthUpdateUsageDescription` in the app target even though the production export flow is read-only. `HealthKitManager.generateTestData()` calls `healthStore.save(...)` inside simulator-only code, and App Store validation still expects the write-purpose string to exist when that API is referenced.

HealthKit requires a physical device for full verification. The simulator has limited support; use the simulator-only test data generator for UI development when needed.

## Guardrails
Never:

- Hand-edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`. The release workflow owns them.
- Push a tag by hand. The release workflow tags each release.
- Push to `main`. Open a pull request, even for a one-line fix.
- Change the persisted `SettingsManager` keys (`SettingsManager.Key`) or their value formats. A changed key loses each user's saved settings.
- Change `ITSAppUsesNonExemptEncryption`, unless the app starts to use non-exempt encryption.
- Put host names, LAN addresses or secret names in this repo. The repo is public. Name the runners by their labels only.
