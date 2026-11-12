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
make clean    # Remove build artifacts
```

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

1. Bump the version in `Info.plist` (`CFBundleVersion` and
   `CFBundleShortVersionString`) and the badge in `README.md`.
2. Add a dated entry to `CHANGELOG.md`.
3. `make dmg SIGN_ID="…"`, then notarize and staple (above).
4. Commit, tag the release, and push.
5. Publish a GitHub release whose tag is `v<version>` with `Notepad.dmg`
   attached (the Homebrew cask downloads this exact asset name):

   ```bash
   gh release create "v<version>" Notepad.dmg --title "<version>" --notes "…"
   ```

6. **Update the Homebrew tap** so `brew install --cask jayclark5150/tap/notepad`
   serves the new version. In the
   [`jayclark5150/homebrew-tap`](https://github.com/jayclark5150/homebrew-tap)
   repo, edit `Casks/notepad.rb`:
   - set `version` to the new version;
   - set `sha256` to the DMG hash: `shasum -a 256 Notepad.dmg`;
   - keep the `url` pointing at `.../download/v#{version}/Notepad.dmg`;
   - run `brew style Casks/notepad.rb` (should report no offenses), then
     commit and push.

   The cask `version`/`sha256` must match the uploaded DMG exactly, or the
   install fails the checksum. Verify end to end with:

   ```bash
   brew update && brew upgrade --cask notepad   # or: brew install --cask jayclark5150/tap/notepad
   ```
