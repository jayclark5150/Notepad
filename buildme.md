# Build & Release Notes

Build and distribution steps for Notepad (macOS, arm64).

## Prerequisites

- macOS 12.0+ on Apple Silicon (arm64)
- Xcode Command Line Tools: `xcode-select --install`
- For a distributable build: an Apple Developer account with a **Developer ID Application** certificate installed in your login keychain
- For export testing: `brew install pandoc`

## Build the icon

`Notepad.icns` is generated from `icon_src.png` and is not committed:

```bash
./make_icon.sh
```

## Local build

```bash
make          # Build Notepad.app (ad-hoc signed)
make run      # Build and launch
make install  # Build and copy to /Applications
make dmg      # Build Notepad.dmg (Notepad.app + Applications shortcut)
make clean    # Remove build artifacts
```

### How signing works

`make` signs the app in a temporary folder (`$TMPDIR/notepad-build`), checks
it with `codesign --verify --deep --strict`, then copies it back to the
project folder. `make install` and `make dmg` use the clean signed copy from
the temporary folder.

This is because iCloud Desktop & Documents sync re-adds Finder attributes to
files in synced folders, and `codesign` refuses them with "resource fork,
Finder information, or similar detritus not allowed". If you still see that
error, build from a folder outside iCloud (for example `~/Developer`).

### Switching between a Homebrew install and a local build

```bash
brew uninstall --cask --force notepad   # remove the Homebrew copy
make install                            # install your build
```

Homebrew does not track a `make install` copy. Before going back to the cask,
delete it (`rm -rf /Applications/Notepad.app`), or `brew install` stops with
"already an App at /Applications/Notepad.app".

### Checking a build

The status bar shows the version (for example `v2.3.0`). Manual checks for the
Markdown preview are P1 to P12 in `regression-checklist.md`.

By default `SIGN_ID = -` (ad-hoc). An ad-hoc build runs only on the build
machine; Gatekeeper blocks it on any machine that receives it through a
quarantine-triggering channel (download, AirDrop, email).

## Distributable (signed + notarized) build

### 1. Sign with your Developer ID

Pass your identity to any build target via `SIGN_ID`:

```bash
make dmg SIGN_ID="Developer ID Application: Your Name (TEAMID)"
```

List available identities with:

```bash
security find-identity -v -p codesigning
```

This produces a signed `Notepad.app` inside `Notepad.dmg`.

### 2. Notarize the DMG

Store credentials once (uses an app-specific password from appleid.apple.com):

```bash
xcrun notarytool store-credentials "notepad-notary" \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "app-specific-password"
```

Submit and wait:

```bash
xcrun notarytool submit Notepad.dmg \
    --keychain-profile "notepad-notary" \
    --wait
```

### 3. Staple the ticket

```bash
xcrun stapler staple Notepad.dmg
xcrun stapler validate Notepad.dmg
```

The stapled DMG can now be distributed and opens without Gatekeeper warnings.

## Verifying a build

```bash
codesign --verify --deep --strict --verbose=2 Notepad.app
spctl --assess --type execute --verbose Notepad.app   # after notarization
```

## Release checklist

Pushing a `v*` tag runs `.github/workflows/release.yml`
(spec: `docs/release-workflow.md`). It checks the version, then either
publishes or syncs the Homebrew tap. Every check is listed in
`regression-checklist.md`; if any fails, nothing is published.

1. Bump the version in `Info.plist` (`CFBundleVersion` and
   `CFBundleShortVersionString`) and the badge in `README.md`.
2. Add a dated `## [<version>]` entry to `CHANGELOG.md`.
3. Commit and push to `main`.
4. Release it one of two ways:

   **A. Signed and notarized (for other Macs).** Build, notarize and staple
   locally (above), then create the release with the DMG. This also creates
   and pushes the tag:

   ```bash
   gh release create "v<version>" Notepad.dmg --title "<version>" --notes "…"
   ```

   The workflow sees the existing release, leaves it alone, and updates the
   tap to that DMG's sha256 (TAP-SYNC mode).

   **B. CI build (ad-hoc signed).** Push the tag only:

   ```bash
   git tag "v<version>" && git push origin "v<version>"
   ```

   The workflow builds `Notepad.dmg`, creates the release and updates the tap
   (PUBLISH mode). Ad-hoc builds are blocked by Gatekeeper on other Macs.

   Do not push the tag before running `gh release create` in path A, or CI
   publishes its own ad-hoc build first.

5. Check the run summary on the Actions tab: it names the mode and every
   check's result. Then verify end to end:

   ```bash
   brew update && brew upgrade --cask notepad   # or: brew install --cask jayclark5150/tap/notepad
   ```

To preview a release without publishing, run the workflow from the Actions tab
(**Run workflow**) with the tag and `dry_run` checked. It builds the DMG,
runs every check and keeps the DMG as a run artifact.

The tap needs the `TAP_TOKEN` repository secret (push access to
`jayclark5150/homebrew-tap`). The cask `url` must keep pointing at
`.../download/v#{version}/Notepad.dmg`; the workflow refuses to run otherwise.
