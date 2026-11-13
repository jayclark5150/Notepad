# Regression checklist

Versioned record of checks that must keep passing, and of the findings behind
them. Read before changing anything listed here; append new checks and
findings before finishing.

## Release pipeline (`.github/workflows/release.yml`)

Automated by `scripts/release-gate.sh` (IDs match its output) unless noted.
Any FAIL puts the run in PREVIEW (halted) mode: nothing is published or pushed.

| ID | Check | Added | Guards against |
|---|---|---|---|
| R1 | Tag is `vX.Y.Z` | 2026-11-13 | Bad tag names reaching the cask |
| R2 | `Info.plist` CFBundleShortVersionString = tag | 2026-11-13 | App reports a different version than the release |
| R3 | `Info.plist` CFBundleVersion = tag | 2026-11-13 | Same |
| R4 | README version badge = tag | 2026-11-13 | Release checklist step 1 skipped |
| R5 | CHANGELOG has `## [X.Y.Z]` | 2026-11-13 | Release checklist step 2 skipped |
| R7 | `Notepad.dmg` exists and is non-empty | 2026-11-13 | F1: release shipped `Notepad.zip` |
| R8 | DMG mounts | 2026-11-13 | Corrupt image |
| R9 | DMG root has `Notepad.app` | 2026-11-13 | "App source is not there" from the cask |
| R10 | DMG root has the `Applications` link | 2026-11-13 | Broken drag-to-install |
| R11 | App inside DMG has the tag's version | 2026-11-13 | Stale build uploaded |
| R12 | `codesign --verify --deep --strict` passes | 2026-11-13 | Broken signature |
| R13 | Cask url ends in `v#{version}/Notepad.dmg` | 2026-11-13 | F1: asset name and cask out of step |
| R14 | Cask has `app "Notepad.app"` | 2026-11-13 | Cask installs the wrong bundle |
| R15 | Cask has exactly one `version` and one `sha256` line | 2026-11-13 | sed rewriting the wrong line |
| R16 | Cask `version` = tag after edit | 2026-11-13 | Silent sed no-op |
| R17 | Cask `sha256` = asset hash after edit | 2026-11-13 | F1: cask hash of a different file |
| R18 | Asset downloaded back from the release hashes to the cask sha256 | 2026-11-13 | Users get a checksum failure |
| R19 | `TAP_TOKEN` set (real runs) | 2026-11-13 | Release published, tap never updated |
| R20 | Existing release has `Notepad.dmg`; a manual release is never replaced | 2026-11-13 | F2: CI overwriting or colliding with a notarized manual release |
| W1 | Warn when the app is ad-hoc signed | 2026-11-13 | F3 (warning only) |

Local run of the portable checks (R1 to R5, R13 to R18); R8 to R12 need macOS:

```bash
bash scripts/release-gate.sh pre v2.2.2
bash scripts/release-gate.sh cask path/to/homebrew-tap/Casks/notepad.rb
```

Manual check after each release:

- [ ] `brew update && brew upgrade --cask notepad` installs the new version on a Mac

## Findings log

| ID | Date | Finding | Status |
|---|---|---|---|
| F1 | 2026-11-13 | Workflow uploaded `Notepad.zip` and wrote the zip's sha256 into a cask that downloads `Notepad.dmg`. A CI release would have broken `brew install`. | Fixed: workflow builds and verifies `Notepad.dmg` (R7, R13, R17, R18) |
| F2 | 2026-11-13 | Releases 2.0.0 to 2.2.2 were made by hand; every tag run failed ("release already exists") or was cancelled, so the tap was updated by hand. | Fixed: existing releases run in TAP-SYNC mode (R20) |
| F3 | 2026-11-13 | The 2.2.2 `Notepad.dmg` on the tap is ad-hoc signed (no Developer ID certificate, not notarized). Gatekeeper blocks it on other Macs. | Open: needs a Developer ID certificate |
| F4 | 2026-11-13 | `brew upgrade` 2.1.1 to 2.2.2 failed with "App source '/Applications/Notepad.app' is not there" because the installed app had been removed outside brew. Local state, not a pipeline bug. | Workaround: `brew uninstall --cask --force notepad`, then reinstall |
| F5 | 2026-11-13 | Audit: `GH_TOKEN` and `TAP_TOKEN` were set for the whole job, so the build step could read them. | Fixed: each token is set only on the steps that use it |
