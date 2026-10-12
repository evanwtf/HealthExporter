## Summary

-

## Release

Apply one label before you merge:

- [ ] `semver:patch`: a fix or a small change. No label means a patch release.
- [ ] `semver:minor`: a layout change.
- [ ] `semver:major`: a major change.
- [ ] `skip-release`: docs, CI or tooling only. The merge cuts no release and no TestFlight upload.

Never use `skip-release` with a `semver:*` label: the release job fails.
A release pull request adds its lines under `## Unreleased` in `docs/changelog.md`: plain sentences for testers, with no links, backticks or bold. They become the GitHub release notes and the TestFlight notes.
