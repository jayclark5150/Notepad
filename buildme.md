# Building Notepad

Requires macOS 12.0+, Apple Silicon (arm64), and Xcode Command Line Tools.

```bash
xcode-select --install   # if not already installed
```

## Commands

```bash
make          # Build Notepad.app
make run      # Build and launch
make install  # Build and copy to /Applications
make dmg      # Build and create Notepad.dmg
make clean    # Remove build artifacts
```

## Custom signing

By default the app is ad-hoc signed (`-`) and works only on the build machine.
To sign for distribution, set your Developer ID in the Makefile:

```bash
make SIGN_ID="Developer ID Application: Your Name (TEAMID)"
```

Notarization is required for Gatekeeper to allow the app on other machines.
