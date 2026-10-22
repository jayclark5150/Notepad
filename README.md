# Notepad (macOS)

A document editor for macOS — inspired by the clean aesthetic of iA Writer. Open and edit plain text, Markdown, and Word documents in a distraction-free, centered writing environment.

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue) ![Architecture](https://img.shields.io/badge/arch-arm64-green) ![Version](https://img.shields.io/badge/version-1.3.0-orange)

## Features

### Document formats
- **Plain Text** (.txt) — full read/write
- **Markdown** (.md) — full read/write with live syntax highlighting
- **Word Document** (.docx) — opens with bold, italic, and heading formatting preserved; saves back to .docx
- **Legacy Word** (.doc) — opens as read-only text extraction; use Save As to save as .docx or .txt

### Editor
- **iA Writer-inspired theme** — adapts automatically to macOS dark / light mode with custom colors
- **Centered writing column** — 720 px max-width with generous margins, just like iA Writer
- **Markdown syntax highlighting** — headers, code blocks, bold, italic, blockquotes with iA Writer accent colors
- **Edit / Preview toggle** — switch between raw Markdown and rendered preview in the same pane (Cmd+\\)
- Line number gutter (toggle with Cmd+Shift+L, off by default)
- Find & Replace (case-insensitive, wrap-around)
- Font selection: Monospaced, Sans-Serif, Serif
- Adjustable font size 8–72 pt (Cmd++ / Cmd+-)
- Adjustable line spacing
- Undo/Redo
- Unsaved-changes protection on close/quit/new/open
- UTF-8 with Latin-1 fallback for plain-text files
- Native file open/save dialogs
- Open files from Finder, Dock, or "Open With"
- Status bar: format badge, word count, character count, cursor line/column

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Toggle Edit / Preview | Cmd+\\ |
| Toggle line numbers | Cmd+Shift+L |
| Find & Replace | Cmd+F |
| Font bigger / smaller | Cmd++ / Cmd+- |
| Preview bigger / smaller | Cmd+Option+= / Cmd+Option+- |
| Preview actual size | Cmd+Option+0 |

## How DOCX editing works

When you open a `.docx` file the app converts it to Markdown for editing:

| Word formatting | Markdown equivalent |
|---|---|
| Heading 1–3 | `# ` … `### ` |
| **Bold** | `**bold**` |
| *Italic* | `*italic*` |
| ***Bold italic*** | `***bold italic***` |

When you save, the Markdown is converted back to a valid `.docx` file with font sizes and traits applied. Complex formatting (tables, images, comments) is not preserved.

## Build

Requires macOS 12.0+, Apple Silicon (arm64), and Xcode Command Line Tools (`xcode-select --install`).

Generate the app icon first (not stored in the repo):

```bash
./make_icon.sh   # builds Notepad.icns from icon_src.png
```

Then:

```bash
make          # Build Notepad.app
make run      # Build and launch
make install  # Build and copy to /Applications
make dmg      # Build Notepad.dmg (drag-to-Applications installer)
make clean    # Remove build artifacts
```

By default the app is ad-hoc signed (runs only on the build machine). For a distributable build:

```bash
make dmg SIGN_ID="Developer ID Application: Your Name (TEAMID)"
```

See `buildme.md` for notarization steps.

## Security

- App Sandbox with user-selected file access
- Hardened Runtime enabled
- Code signed at build time
- Large file warning (100 MB+)
- POSIX permission preservation on save

## License

All rights reserved.
