# App Store release runbook

This runbook takes a HealthExporter build from TestFlight to the App Store.
The owner starts every App Store Connect write. Each write runs from a
workflow on the Linux runner; nothing runs from a laptop.

The workflows:

| Workflow | Does |
|----------|------|
| `release-testflight.yml` | Tests, archives and uploads a build to TestFlight. Each release merge starts it. |
| `appstore-screenshots.yml` | Replaces the 6.9-inch iPhone screenshots of an App Store version. |
| `release-appstore.yml` | Checks an App Store version, attaches the build, sets the metadata and submits it for App Review. |
| `promote-testflight-external.yml` | Adds a build to the external TestFlight group and submits it for Beta App Review. |

## Prerequisites

### The App Store Connect API key

The workflows use one App Store Connect team API key. The repository secrets
are `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` and `ASC_API_KEY_P8` (the `.p8` file
text).

The key must have the **App Manager** role. A key with the Developer role can
upload builds, but App Store Connect refuses its review submissions and its
TestFlight promotions with `403 FORBIDDEN_ERROR`.

### The App Review contact

App Review needs a contact for each submission. `release-appstore.yml` reads
it from four secrets:

| Secret | Value |
|--------|-------|
| `ASC_REVIEW_CONTACT_FIRST_NAME` | First name |
| `ASC_REVIEW_CONTACT_LAST_NAME` | Last name |
| `ASC_REVIEW_CONTACT_EMAIL` | Email address |
| `ASC_REVIEW_CONTACT_PHONE` | Phone number: `+`, the country code, then the number, for example `+1 555 0100 123` |

The owner sets them, as repository or organization secrets. `gh secret set`
asks for the value, so the value does not go into the shell history:

```bash
gh secret set ASC_REVIEW_CONTACT_FIRST_NAME --repo evanwtf/HealthExporter
gh secret set ASC_REVIEW_CONTACT_LAST_NAME --repo evanwtf/HealthExporter
gh secret set ASC_REVIEW_CONTACT_EMAIL --repo evanwtf/HealthExporter
gh secret set ASC_REVIEW_CONTACT_PHONE --repo evanwtf/HealthExporter
```

A set secret wins over the contact in App Store Connect. When a secret is not
set, the script keeps the value that App Store Connect has. When neither has a
value, the script refuses and names the missing secret. The script sends only
the values from the secrets; it does not send a kept value again. The script
never logs a contact value. It logs only "set from secret", "kept" or
"missing".

## Cut a public release

1. Merge the release pull request. The release job tags `vX.Y.Z` and starts
   `release-testflight.yml` on the tag. Check that the upload passed:

   ```bash
   gh run list --workflow release-testflight.yml --repo evanwtf/HealthExporter --limit 3
   ```

2. If the UI changed, replace the App Store screenshots. Run the dry run,
   read the log, then upload:

   ```bash
   gh workflow run appstore-screenshots.yml --repo evanwtf/HealthExporter -f version=2.5.5
   gh workflow run appstore-screenshots.yml --repo evanwtf/HealthExporter -f version=2.5.5 -f dry_run=false
   ```

   The screenshot upload needs an editable App Store version. If the version
   does not exist yet, run step 4 (prepare) first. It creates the version.

3. Run `release-appstore.yml` in mode dry-run (the default). It writes nothing:

   ```bash
   gh workflow run release-appstore.yml --repo evanwtf/HealthExporter -f version=2.5.5
   ```

   Read the log. The plan names the build, the version, What's New and the
   review submission. When a check fails, the run fails and lists every
   problem. Fix them all, then run the dry run again.

   - The default build is the newest VALID, unexpired build of the version.
     Pass `-f build=57` to use another one.
   - What's New comes from the version's section of `docs/changelog.md`,
     without the lines that start with "- Please". Those lines ask testers
     to check something, so only TestFlight shows them.
   - For a version that the run creates, the script always uses the
     changelog text: App Store Connect can copy What's New from the version
     before it. For a version that exists, the script keeps the text in App
     Store Connect, and uses the changelog only when the text is empty. Pass
     `-f replace_whats_new=true` to use the changelog text in all cases.
   - When the version does not exist, the dry run cannot check its
     metadata. The prepare run creates it, then checks it before any other
     write.
   - App Store Connect allows one editable version. When a lower version is
     in Prepare for Submission, the script renames it to the new version. It
     keeps that version's metadata and screenshots.

4. Run mode prepare. It writes the version, the release type, the build,
   What's New and the App Review contact. It does not submit:

   ```bash
   gh workflow run release-appstore.yml --repo evanwtf/HealthExporter -f version=2.5.5 -f mode=prepare
   ```

5. Open the version in App Store Connect and read the page: the build, What's
   New, the screenshots and the App Review information.

6. Run mode submit. It runs the checks again, writes the same values, adds the
   version to a review submission and submits it:

   ```bash
   gh workflow run release-appstore.yml --repo evanwtf/HealthExporter -f version=2.5.5 -f mode=submit
   ```

   The default release type releases the version when App Review approves it.
   To release it by hand, add `-f release_type=manual`.

Watch a run:

```bash
gh run watch --repo evanwtf/HealthExporter "$(gh run list --workflow release-appstore.yml --repo evanwtf/HealthExporter --limit 1 --json databaseId --jq '.[0].databaseId')"
```

## Promote a build to external TestFlight

This step is optional. It gives the build to the external testers before, or
in place of, an App Store release:

```bash
gh workflow run promote-testflight-external.yml --repo evanwtf/HealthExporter -f build=57
```

Add `-f submit_review=false` to add the build to the group without a Beta App
Review submission. Add `-f group=<name>` to use one group only.

## Verify a release went in

1. The `release-appstore.yml` run passed, and its last log line is
   "Submitted version X.Y.Z (build N) for App Review".

   ```bash
   gh run list --workflow release-appstore.yml --repo evanwtf/HealthExporter --limit 3
   ```

2. Run the dry run again. It must now refuse, with "already in review
   (WAITING_FOR_REVIEW)" and the version state. That refusal shows that App
   Store Connect has the submission:

   ```bash
   gh workflow run release-appstore.yml --repo evanwtf/HealthExporter -f version=2.5.5
   ```

3. In App Store Connect, the version shows "Waiting for Review". Apple also
   sends an email to the account holder.

4. After approval, a version with release type after-approval goes to "Ready
   for Distribution" without a further step. A version with release type
   manual waits in "Pending Developer Release" until the owner releases it in
   App Store Connect.

## When a submit run fails

Run mode submit again. If the failed run added the version to a draft review
submission, the version is in "Ready for Review". The script reuses that
version and that draft, and does not add the version twice.

## When App Review rejects the version

The dry run refuses with "has unresolved issues". Read App Review's message in
App Store Connect, and answer it there.

- If App Review needs a new build, merge the fix. Then run mode prepare with
  the new version number. The script renames the rejected version only when
  it is in Prepare for Submission, so first remove the rejected version from
  review in App Store Connect.
- If App Review needs only an answer or a metadata change, resubmit in App
  Store Connect.

## Rotate the ASC key

The key is a team key. Other apps of the team can use the same key, so update
every repository that uses it before you revoke the old key.

1. In App Store Connect, go to Users and Access, then Integrations, then App
   Store Connect API, then Team Keys. Generate a key with the App Manager
   role. Download the `.p8` file. App Store Connect lets you download it once.
2. Keep the `.p8` file in the team's password manager.
3. Set the three secrets. The key ID is on the Team Keys page. The issuer ID
   does not change.

   ```bash
   gh secret set ASC_API_KEY_ID --repo evanwtf/HealthExporter
   gh secret set ASC_API_KEY_P8 --repo evanwtf/HealthExporter < AuthKey_NEWKEYID.p8
   ```

4. Delete the local `.p8` file.
5. Test the new key with a dry run. It only reads:

   ```bash
   gh workflow run release-appstore.yml --repo evanwtf/HealthExporter -f version=2.5.5
   ```

   A `401` error means a wrong key ID, issuer ID or `.p8` text. A `403` error
   on a write means the key does not have the App Manager role.

6. Revoke the old key in App Store Connect.
