# Notepad (macOS)

A document editor for macOS. Open and edit plain text, Markdown, and Word documents in a distraction-free, centered writing environment.

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue) ![Architecture](https://img.shields.io/badge/arch-arm64-green) ![Version](https://img.shields.io/badge/version-1.6.0-orange)

## Features

### Document formats
- **Plain Text** (.txt) — full read/write
- **Markdown** (.md) — full read/write with live syntax highlighting
- **Word Document** (.docx) — native rich-text editing; bold, italic, underline, strikethrough, alignment, and heading styles preserved on save
- **Legacy Word** (.doc) — opens as read-only text extraction; use Save As to save as .docx or .txt

### Editor
- **Adaptive theme** — adapts automatically to macOS dark / light mode with custom colors
- **Centered writing column** — adjustable column width (300–1200 px, default 720) with auto-centering margins
- **Markdown syntax highlighting** — headers, code blocks, bold, italic, blockquotes with accent colors
- **Edit / Preview toggle** — switch between raw Markdown and rendered preview in the same pane (Cmd+\\)
- **Formatting toolbar** — Bold, Italic, Underline, Strikethrough, alignment buttons, and Heading Style popup (DOCX mode only)
- **Typewriter mode** — cursor stays vertically centered as you type (View > Typewriter Mode or Cmd+Shift+T)
- **Full-screen support** — native macOS full-screen (green traffic-light button or View > Enter Full Screen)
- **Drag & drop** — drag any supported file onto the window to open it
- **Open Recent** — File > Open Recent submenu with full history
- Line number gutter (toggle with Cmd+Shift+L, off by default)
- Find & Replace with Find Next (⌘G), Find Previous (⌘⇧G), Use Selection for Find (⌘E), Jump to Selection (⌘J)
- Revert to Saved (File menu)
- Paste and Match Style (⌘⇧V)
- Text Transformations — Make Upper Case, Make Lower Case, Capitalize (Edit > Transformations)
- Spelling and Grammar submenu with per-document check, grammar toggle, and auto-correct
- Start Dictation and Emoji & Symbols (Edit menu)
- Font selection: Monospaced, Sans-Serif, Serif (via Preferences or Format > Show Fonts)
- Adjustable font size 8–72 pt (Cmd++ / Cmd+-)
- Adjustable line spacing
- Spelling & grammar check toggle (Edit menu, persisted across launches)
- Undo/Redo
- Unsaved-changes protection on close/quit/new/open
- UTF-8 with Latin-1 fallback for plain-text files
- Native file open/save dialogs
- Open files from Finder, Dock, or "Open With"
- Window size and position remembered across launches
- Status bar: format badge, word count, character count, cursor line/column

### Preferences (Cmd+,)
- Font family (Monospaced / Sans-Serif / Serif)
- Font size (8–72 pt)
- Typewriter mode toggle
- Spelling & grammar toggle
- Column width (300–1200 px slider)
- All settings persisted via NSUserDefaults

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| New | Cmd+N |
| Open | Cmd+O |
| Close | Cmd+W |
| Save | Cmd+S |
| Save As | Cmd+Shift+S |
| Print | Cmd+P |
| Minimize | Cmd+M |
| Enter Full Screen | Ctrl+Cmd+F |
| Hide Notepad | Cmd+H |
| Hide Others | Cmd+Option+H |
| Toggle Edit / Preview | Cmd+\\ |
| Preferences | Cmd+, |
| Paste and Match Style | Cmd+Shift+V |
| Find… | Cmd+F |
| Find Next | Cmd+G |
| Find Previous | Cmd+Shift+G |
| Use Selection for Find | Cmd+E |
| Jump to Selection | Cmd+J |
| Show Spelling and Grammar | Cmd+: |
| Check Document Now | Cmd+; |
| Emoji & Symbols | Ctrl+Cmd+Space |
| Show Fonts panel | Cmd+T |
| Show/Hide Toolbar | Cmd+Option+T |
| Bold | Cmd+B |
| Italic | Cmd+I |
| Underline | Cmd+U |
| Toggle line numbers | Cmd+Shift+L |
| Typewriter mode | Cmd+Shift+T |
| Font bigger / smaller | Cmd++ / Cmd+- |
| Preview bigger / smaller | Cmd+Option+= / Cmd+Option+- |
| Preview actual size | Cmd+Option+0 |

## How DOCX editing works

When you open a `.docx` file the app loads it as native rich text using `NSAttributedString` with `NSOfficeOpenXMLTextDocumentType`. You can edit bold, italic, underline, strikethrough, text alignment, and heading font sizes directly. When you save, the rich text is written back to a valid `.docx` file with all formatting preserved.

Complex formatting (tables, images, comments) is preserved on round-trip (the app doesn't alter what it doesn't edit). Dark mode automatically adjusts near-black DOCX text colors so they are readable.

## Install

Open Terminal and run:

```bash
brew install --cask jayclark5150/tap/notepad
```

Because the app is ad-hoc signed, Gatekeeper will block it on first launch. After install, run this once in Terminal:

```bash
xattr -cr /Applications/Notepad.app
```

Then open Notepad normally from `/Applications` or Spotlight.

## Build from source

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

MIT — see [LICENSE](LICENSE).
