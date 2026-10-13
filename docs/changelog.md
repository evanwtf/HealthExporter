# Changelog

Release notes for each version of HealthExporter, newest first. The release job copies each section into the GitHub release and into the TestFlight "What to Test" notes. Write each line for a tester: one plain sentence or two after "- ", with no links, backticks or bold. A pull request that cuts a release adds its lines under Unreleased.

## Unreleased

<!-- One "- " line per change, in plain words for testers. -->

## v2.6.0 (build 58), 2026-10-13

- The app now keeps a history of your last 10 exports. Tap the clock button next to Settings on the welcome screen to see what each export held, its date range, its size, and any data that did not load.
- Tap Export Again on an entry to open Choose Data with the same selection and date range. Then tap Export CSV.
- The welcome screen shows the time of your last export. Tap it to open the history.
- To remove every entry, tap Clear History. To stop the history, turn off Keep Export History in Settings. This also clears it.
- The privacy policy now describes the export history. An entry holds no health data, and no file name or location.
- Please save an export in Files and check that it appears in the history. Then cancel the Files picker once, and check that no new entry appears.
- Please try Export Again on an entry with lab results, and check that Choose Data shows the same labs and dates.

## v2.5.5 (build 57), 2026-10-12

- The privacy policy in Settings is updated. It now says how the app reads lab results, what the exported file holds, where it can go, and that GitHub issues are public. It also gives the current steps to turn off Health access.

## v2.5.4 (build 56), 2026-10-12

- The disclaimer at the top of the CSV no longer splits into columns when you open the file in Google Sheets, Numbers or Excel.
- Please check that the file you export opens in a spreadsheet, and that the numbers match the Health app.

## v2.5.3 (build 55), 2026-10-12

- On iOS 27 you can give Health access that starts at a date. When that date is after the start of your export, an alert says when the data for each metric starts. "All Records" and "Last N Records" exports show the alert too.
- The close button in Settings is now a plain glass X, like the Settings button on the welcome screen.

## v2.5.2 (build 54), 2026-10-12

- Exports can be stopped. While "Preparing export..." shows, tap Cancel. The screen returns to your selection with no error.
- The app builds the file once, in the background, so the screen stays responsive during a large export.
- The size alert is now titled "Export Size", and it gives the exact number of rows and the exact file size.
- When you turn a lab panel off, a lab that you selected on its own stays selected.
- The Export CSV button always matches your selection and your dates.
- Please check that your settings from an earlier version are still there after the update.

## v2.5.1 (build 53), 2026-10-12

- New builds reach testers again. Versions 2.4.13 and 2.4.15 to 2.5.0 stopped at an export compliance question in App Store Connect, so testers did not get them. The app itself does not change.

## v2.5.0 (build 52), 2026-10-12

- Choose Data has a new layout. Each category (Weight, Steps, Blood Glucose, Vitals and each lab panel) is a tile. Tap a tile to turn it on or off. The Vitals and lab tiles open a list where you pick single items.
- Each tile shows a check mark when it is on, and a short count, such as "2 of 6 vitals" or "4 labs".
- The app uses the pink of its icon as its accent color, and a rounded font.
- The welcome screen shows the five kinds of data the app exports, a privacy line and a Choose Data button.

## v2.4.17 (build 51), 2026-10-12

- Nothing changes on screen. This build changes how the app is tested.

## v2.4.16 (build 50), 2026-10-12

- A partial export says so. If some metrics fail to load, the export goes on with the others, and an alert names each metric that failed.
- "Last N Records" for blood glucose now gives N readings. The app drops readings below 20 mg/dL before it counts, not after.
- The Health permission sheet asks only for the data you selected.
- Please check the permission sheet for an export of only vitals, of only labs and of only glucose.

## v2.4.15 (build 49), 2026-10-12

- On Choose Data, the list now runs under the date range and Export CSV footer, so you can see that more rows follow. The scroll bar flashes when the screen opens.

## v2.4.14 (build 48), 2026-10-12

- Nothing changes on screen. The app reads lab result dates in a new way, so please check that the lab dates in an export are right.

## v2.4.13 (build 47), 2026-10-12

- The CSV has a new last column, Meal Time. A glucose row shows Before Meal or After Meal when the reading has that tag.
- A lab result reported as a limit, such as more than 60 or less than 0.3, keeps that limit in the export.
- LDL, glucose, eGFR and A1C now also match the codes that most labs send. The lab "Fasting Glucose" is now "Glucose", because it matches any glucose result.
- "Last N Records" now applies to each lab on its own, so a selected lab no longer comes out empty.
- Lab results with a partial date, or with no unit, are no longer left out of the export.
- Steps are rounded to the nearest whole number, not cut off.
- Dates in the file always use the Gregorian calendar, even when your phone uses another calendar.
- When you cancel the Files picker, the app now clears the file from memory.
- A new look: a welcome screen in place of the splash screen, a segmented control for the date range and a full-width Export CSV button.

---

Earlier releases are on the GitHub releases page: https://github.com/evanwtf/HealthExporter/releases
