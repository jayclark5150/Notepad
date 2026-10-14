# Building Notepad

**Version:** 1.0.7  
**Requires:** macOS 12.0+, Apple Silicon (arm64), Xcode Command Line Tools

```bash
xcode-select --install   # if not already installed
```

## Commands

| Command | Description |
|---|---|
| `make` | Build `Notepad.app` |
| `make run` | Build and launch |
| `make install` | Build and copy to `/Applications` |
| `make dmg` | Build and create `Notepad.dmg` |
| `make clean` | Remove build artifacts |

## Icon

The app icon is prebuilt as `Notepad.icns`. To regenerate it from `icon_src.png`:

```bash
./make_icon.sh
```

## Signing

By default the app is ad-hoc signed (`-`) and runs only on the build machine. To sign for distribution, set your Developer ID in the Makefile:

```makefile
SIGN_ID = Developer ID Application: Your Name (TEAMID)
```

Or pass it on the command line:

```bash
make SIGN_ID="Developer ID Application: Your Name (TEAMID)"
```

Notarization is required for Gatekeeper to allow the app on other machines.
