# Changelog

## [2.3.1] - 2026-11-13
- **Build**: each build embeds the SHA-256 of `main.mm`; `make` refuses to sign, and the release check refuses to publish, an app binary that was not compiled from the current source (a stale binary with a new `Info.plist` was uploaded as 2.3.0)

## [2.3.0] - 2026-11-13
- **Preview: clickable task lists**: tick or clear `- [ ]` / `- [x]` boxes in the preview; the Markdown is updated, the document is marked edited, and the change can be undone from the editor
- **Preview: copy icon** on code blocks replaces the "Copy" text button and shows a checkmark when copied
- **Preview: standalone code spans** (a paragraph that is only `` `code` ``, even across several lines) render as a code block with the copy icon, keeping line breaks
- **Preview: extended Markdown**: emoji shortcodes (`:joy:`), `==highlight==`, subscript `H~2~O`, superscript `X^2^`
- Task lists also accept `* [ ]` and `+ [ ]`
- Preview keeps its scroll position when it re-renders
- **Fix**: underscores, tildes or carets inside link and image URLs are no longer turned into formatting

## [2.2.2] - 2026-11-11
- **Fix (data loss)**: dragging a file onto the window now honors the unsaved-changes prompt instead of silently replacing your document
- **Fix**: Pandoc export now reflects your current edits — unsaved changes are saved first rather than exporting the last-saved version on disk
- **Security**: hardened the Markdown preview against HTML/script injection — quotes are now escaped and link/image URLs with `javascript:`, `vbscript:`, `data:`, or `file:` schemes are rejected
- **Perf**: live Markdown formatting is debounced, so fast typing in large documents no longer reformats the whole document on every keystroke
- **Encoding**: plain-text files now use automatic encoding detection (BOM/UTF-16) before falling back to UTF-8 and Latin-1
- Internal cleanup: removed dead conversion code and an unused export parameter

## [2.2.1] - 2026-11-08
- Fix code text in editor showing as gray — code content now uses body text color (pure black/white); monospace font distinguishes it from prose
- Raise syntax marker color from `tertiaryLabelColor` to `secondaryLabelColor` for better visibility against pure white/black backgrounds

## [2.2.0] - 2026-11-08
- **Pandoc export** — File › Export submenu with HTML, PDF, Word (.docx), ePub, and LaTeX; requires `brew install pandoc`
- **Fix**: Markdown preview was showing `#E8E6E3` instead of note content (misaligned format arguments)
- **Gutters**: editor and preview gutters capped at 48 px per side; text fills wide windows instead of leaving large empty margins
- **Colors**: editor and preview now use pure black-on-white (light) and white-on-black (dark)

## [2.1.1] - 2026-10-25
- Fix code text color in preview — inline code and fenced blocks now use the body text color instead of amber/brown, ensuring readability in both light and dark mode

## [2.1.0] - 2026-10-25
- **Image paste in Markdown** — paste a screenshot or image (Cmd+V) into a `.md` file; the image is saved as `assets/image-YYYYMMDD-HHmmss.png` next to the document and a `![](assets/…)` reference is inserted at the cursor; images render in the Markdown preview
- Remove app sandbox (was blocking asset folder creation next to the document)

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
