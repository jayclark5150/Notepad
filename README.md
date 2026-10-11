v# Notepad

A minimal plain-text editor for macOS (Apple Silicon).

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue) ![Architecture](https://img.shields.io/badge/arch-arm64-green) ![Version](https://img.shields.io/badge/version-1.0.6-orange)

## Features

- Line number gutter with toggle visibility
- Find & Replace (case-insensitive, wrap-around search)
- Font selection: Monospaced, Sans-Serif, Serif
- Adjustable font size (8–72 pt) and line spacing
- Markdown syntax highlighting in the editor
- Live Markdown preview pane (Cmd+Shift+P)
- Resizable split between editor and preview (drag the divider, double-click to reset), remembered between launches
- Adjustable preview text size (Cmd+Option+= / Cmd+Option+- / Cmd+Option+0 to reset), remembered between launches
- Code blocks rendered as rounded rectangles with a one-click Copy button
- Save-aware close and quit (window and app will not close if a save fails or is cancelled)
- UTF-8 with Latin-1 fallback for file reading
- Undo/Redo support

## Security

- App Sandbox with user-selected file access
- Hardened Runtime enabled
- Code signed at build time (set `SIGN_ID` in Makefile for a Developer ID distributable build)
- Large file warning (100 MB+)
- POSIX permission preservation on save

## Build

Requires macOS 12.0+, Apple Silicon (arm64), and Xcode Command Line Tools (`xcode-select --install`).

On a fresh clone, generate the app icon first. The Makefile needs `Notepad.icns`, which is not stored in the repo:

```bash
./make_icon.sh   # builds Notepad.icns from icon_src.png
```

Then:

```bash
make          # Build Notepad.app
make run      # Build and launch
make install  # Build and copy to /Applications
make dmg      # Build and create Notepad.dmg (drag-to-Applications installer)
make clean    # Remove build artifacts
```

By default the app is ad-hoc signed, so the app and DMG run only on the Mac that built them. To sign with a Developer ID instead, set `SIGN_ID`:

```bash
make dmg SIGN_ID="Developer ID Application: Your Name (TEAMID)"
```

A Developer ID build must also be notarized before Gatekeeper allows it on other Macs. See `buildme.md`.

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Toggle Markdown preview | Cmd+Shift+P |
| Toggle line numbers | Cmd+Shift+L |
| Editor text bigger / smaller | Cmd++ / Cmd+- |
| Preview text bigger / smaller | Cmd+Option+= / Cmd+Option+- |
| Preview text actual size | Cmd+Option+0 |
| Find & Replace | Cmd+F |
| Reset editor/preview split | Double-click the divider |

## License

All rights reserved.
