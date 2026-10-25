# Changelog

## [2.0.1] - 2026-10-25
- Fix link handler ignoring `claimedInline`, causing links inside bold/code to become invisible
- Fix strikethrough not claiming its range, allowing links inside `~~…~~` to be double-processed
- Fix invisible markers carrying bold/italic font metrics, causing cursor navigation artifacts
- Fix `cursorLoc` defaulting to 0 on invalid selection, showing wrong marker state on initial load
- Fix `NSUnderlineStyleAttributeName` not cleared on reset, leaking underline from DOCX to plain-text
- Fix code fence markers becoming fully invisible (now always shown in dim color)
- Fix double formatting pass per keystroke (suppress selection-change reformat after text-change reformat)
- Fix potential re-entry cascade after heading font resize via async dispatch for selection-triggered formatting
- Perf: compile 6 inline regex patterns once via `dispatch_once` instead of on every call

## [2.0.0] - 2026-10-25
- **WYSIWYM live Markdown rendering** — syntax markers hide as you write and reappear when the cursor returns; no mode switch needed
- Headings render at scaled font size in place; `## ` prefix hides when cursor is off-line
- Bold, italic, bold+italic apply immediately as font traits; markers invisible until cursor enters span
- Inline code spans use monospace font in accent color; backticks hidden off-span
- Strikethrough renders with strikethrough attribute; `~~` markers hidden off-span
- Links show only the link text in accent color; full `[text](url)` syntax revealed on cursor entry
- Blockquotes hide `> ` prefix when cursor is off-line
- Code fences hide opening/closing markers off-line; content uses monospace
- Horizontal rules hidden when cursor is off-line
- Rendered HTML preview (Cmd+\\) retained for print-ready output

## [1.4.0] - 2026-10-22
- NSToolbar with Bold/Italic/Underline/Strikethrough, alignment buttons, and Heading Style popup
- Typewriter mode: cursor scrolls to vertical center on each keystroke (Cmd+Shift+T)
- Drag & drop files onto window to open
- Full-screen support (NSWindowCollectionBehaviorFullScreenPrimary)
- File > Open Recent submenu
- File > Print… (Cmd+P)
- Format menu: Strikethrough, Align Left/Center/Right, Show Fonts panel (Cmd+T)
- Edit menu: Check Spelling While Typing toggle (persisted)
- Preferences window (Cmd+,): font family, font size, typewriter, spell check
- Dark mode DOCX color fix

## [1.3.0] - 2026-10-01
- Dark/light theme with dynamic NSColor
- Open and edit .docx files via NSAttributedString + DOCX round-trip
- Open .doc (legacy Word) as read-only plain text
- Single-pane Edit/Preview toggle (Cmd+\); removes split-pane preview
- Centered 720px writing column with 24pt vertical padding
- Syntax highlighting with accent colors
- Status bar shows file format badge [TXT/MD/DOCX/DOC]

## [1.0.6] - 2026-09-01
- Bug fixes and stability improvements

## [1.0.4] - 2026-08-15
- Bug fixes

## [1.0.3] - 2026-08-01
- Initial public release
