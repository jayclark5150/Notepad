# Release workflow spec

Spec for `.github/workflows/release.yml` and `scripts/release-gate.sh`.
Risk tier: **Medium** (software deployment change; runs unattended).
Checks and findings: [`regression-checklist.md`](../regression-checklist.md).

## Purpose

Publish each `v*` tag as a GitHub release whose `Notepad.dmg` asset is exactly
what the Homebrew cask (`jayclark5150/homebrew-tap`, `Casks/notepad.rb`)
downloads, so `brew install --cask jayclark5150/tap/notepad` always gets a
matching file and checksum.

## Scope

In scope: building the DMG, creating the release, verifying the published
asset, updating the cask `version` and `sha256`.
Out of scope: Developer ID signing and notarization (CI has no certificate;
see Residual risks), changing the cask's `url` or other stanzas.

## Inputs

| Input | Source |
|---|---|
| Tag `vX.Y.Z` | tag push, or `workflow_dispatch` input `tag` |
| `dry_run` | `workflow_dispatch` input, default `true` |
| `Info.plist`, `README.md`, `CHANGELOG.md`, `Makefile`, `main.mm` | the tagged commit |
| Existing release + `Notepad.dmg` asset | GitHub (manual, notarized releases) |
| `Casks/notepad.rb` | `jayclark5150/homebrew-tap` |
| `TAP_TOKEN` | repo secret with push access to the tap |

## Outputs

- GitHub release `vX.Y.Z` with `Notepad.dmg` (PUBLISH mode only)
- Cask commit setting `version` and `sha256` (skipped if already correct)
- Run artifact `Notepad-dmg` (every mode that has a DMG)
- Run summary naming the mode and every check's result

## Modes

| Mode | When | Release | Tap |
|---|---|---|---|
| PUBLISH | no release exists for the tag | created with CI-built DMG | updated |
| TAP-SYNC | release exists with `Notepad.dmg` | untouched | updated to that asset |
| PREVIEW (dry run) | `workflow_dispatch` with `dry_run` | none | none |
| PREVIEW (halted) | any gate check fails | none | none; run fails |

## Assumptions

- The cask `url` is `.../releases/download/v#{version}/Notepad.dmg` and it
  installs `app "Notepad.app"`.
- `make dmg` produces `Notepad.dmg` with `Notepad.app` and an `Applications`
  link at its root.
- A manual release that already exists is the intended one (for example a
  notarized build) and must not be replaced.

## Constraints

- No real action (release, tap push) runs unless every gate check passed.
- Re-running the same tag is safe: an existing release switches to TAP-SYNC
  and an already-correct cask makes no commit.
- One run per tag at a time (`concurrency`).
- Workflow inputs reach shell only through environment variables.

## Dependencies

`macos-14` runner (hdiutil, codesign, plutil, shasum, brew), `gh`,
`actions/checkout@v4`, `actions/upload-artifact@v4`, `TAP_TOKEN`.

## Acceptance criteria

1. The released asset is named `Notepad.dmg`; no `Notepad.zip` is produced.
2. The cask's `sha256` equals the sha256 of the asset downloaded back from the
   release (R18), and its `version` equals the tag (R16, R17).
3. A tag whose `Info.plist`, README badge or CHANGELOG disagree with it
   publishes nothing (R1 to R5).
4. A DMG that does not mount, lacks `Notepad.app` or the `Applications` link,
   has the wrong version, or fails `codesign --verify` publishes nothing
   (R7 to R12).
5. A cask that no longer points at `Notepad.dmg` publishes nothing (R13 to R15).
6. A manually created release is never replaced (R20, TAP-SYNC).
7. The run summary states the mode, and a failed gate fails the run.

## Residual risks

- CI builds are ad-hoc signed (warning W1). Gatekeeper blocks them on Macs
  other than the build machine. The 2.2.2 asset on the tap is also ad-hoc.
  Shipping to other people needs Developer ID signing and notarization.
- `brew style` offenses are a warning, not a gate.
- If the release is published but the tap push fails, re-running the
  workflow finishes the job in TAP-SYNC mode.
