# Notepad

A minimal plain-text editor for macOS (Apple Silicon).

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue) ![Architecture](https://img.shields.io/badge/arch-arm64-green) ![Version](https://img.shields.io/badge/version-1.0.1-orange)

## Features

- Line number gutter with toggle visibility
- Find & Replace (case-insensitive, wrap-around search)
- Font selection: Monospaced, Sans-Serif, Serif
- Adjustable font size (8–72 pt) and line spacing
- Unsaved changes protection on close/quit/new/open
- UTF-8 with Latin-1 fallback for file reading
- Undo/Redo support

## Security

- App Sandbox with user-selected file access
- Hardened Runtime enabled
- Code signed at build time
- Large file warning (100 MB+)
- File permission preservation on save

## Build

Requires macOS 12.0+, Apple Silicon (arm64), and Xcode Command Line Tools.

```bash
make        # Build Notepad.app
make run    # Build and launch
make clean  # Remove build artifacts
```

To sign with a Developer ID instead of ad-hoc, set `SIGN_ID`:

```bash
make SIGN_ID="Developer ID Application: Your Name (TEAMID)"
```

## Icon

To regenerate the app icon from `icon_src.png`:

```bash
./make_icon.sh
```

## License

All rights reserved.
