# Regression checklist

Versioned record of checks that must keep passing, and of the findings behind
them. Read before changing anything listed here; append new checks and
findings before finishing.

## Release pipeline (`.github/workflows/release.yml`)

Automated by `scripts/release-gate.sh` (IDs match its output) unless noted.
Any FAIL puts the run in PREVIEW (halted) mode: nothing is published or pushed.

| ID | Check | Added | Guards against |
|---|---|---|---|
| R1 | Tag is `vX.Y.Z` | 2026-11-13 | Bad tag names reaching the cask |
| R2 | `Info.plist` CFBundleShortVersionString = tag | 2026-11-13 | App reports a different version than the release |
| R3 | `Info.plist` CFBundleVersion = tag | 2026-11-13 | Same |
| R4 | README version badge = tag | 2026-11-13 | Release checklist step 1 skipped |
| R5 | CHANGELOG has `## [X.Y.Z]` | 2026-11-13 | Release checklist step 2 skipped |
| R6 | Git checkout with no changes to tracked files, and HEAD is the tag's commit | 2026-11-13 | F9: an old main.mm built under a new version number |
| R7 | `Notepad.dmg` exists and is non-empty | 2026-11-13 | F1: release shipped `Notepad.zip` |
| R8 | DMG mounts | 2026-11-13 | Corrupt image |
| R9 | DMG root has `Notepad.app` | 2026-11-13 | "App source is not there" from the cask |
| R10 | DMG root has the `Applications` link | 2026-11-13 | Broken drag-to-install |
| R11 | App inside DMG has the tag's version | 2026-11-13 | Stale build uploaded |
| R12 | `codesign --verify --deep --strict` passes | 2026-11-13 | Broken signature |
| R13 | Cask url ends in `v#{version}/Notepad.dmg` | 2026-11-13 | F1: asset name and cask out of step |
| R14 | Cask has `app "Notepad.app"` | 2026-11-13 | Cask installs the wrong bundle |
| R15 | Cask has exactly one `version` and one `sha256` line | 2026-11-13 | sed rewriting the wrong line |
| R16 | Cask `version` = tag after edit | 2026-11-13 | Silent sed no-op |
| R17 | Cask `sha256` = asset hash after edit | 2026-11-13 | F1: cask hash of a different file |
| R18 | Asset downloaded back from the release hashes to the cask sha256 | 2026-11-13 | Users get a checksum failure |
| R19 | `TAP_TOKEN` set (real runs) | 2026-11-13 | Release published, tap never updated |
| R20 | Existing release has `Notepad.dmg`; a manual release is never replaced | 2026-11-13 | F2: CI overwriting or colliding with a notarized manual release |
| R21 | App binary contains `NOTEPAD-SOURCE-SHA256:<sha256 of main.mm>` (also enforced by `make` before signing) | 2026-11-13 | F9: stale binary shipped under a new version |
| W1 | Warn when the app is ad-hoc signed | 2026-11-13 | F3 (warning only) |

Local run of the portable checks (R1 to R5, R13 to R18); R8 to R12 need macOS:

```bash
bash scripts/release-gate.sh pre v2.2.2
bash scripts/release-gate.sh cask path/to/homebrew-tap/Casks/notepad.rb
```

Manual check after each release:

- [ ] `brew update && brew upgrade --cask notepad` installs the new version on a Mac

## Markdown preview (`main.mm`)

Manual checks on a Mac (`make run`, open a `.md` file, Cmd+\ for the preview).
Spec: `docs/preview-features.md`.

| ID | Check | Added | Guards against |
|---|---|---|---|
| P1 | `:joy:` shows 😂; `:notreal:` and `10:30:45` stay as typed | 2026-11-13 | Shortcodes eating normal colons |
| P2 | `==very important words==` is highlighted; `a == b == c` is not | 2026-11-13 | Comparisons turned into highlights |
| P3 | `H~2~O` and `X^2^` render as sub/superscript; `~~flat~~` is still strikethrough | 2026-11-13 | Subscript clashing with strikethrough |
| P4 | `` `:joy: ==x== H~2~O` `` in backticks renders literally | 2026-11-13 | Formatting inside code |
| P5 | `[s](http://a.com/my_file_name.md)` and `[h](http://a.com/~user/)` keep their exact URLs | 2026-11-13 | F6: URLs rewritten by inline rules |
| P6 | `[x](javascript:alert(1))` links to `#` | 2026-11-13 | Script injection via links (2.2.2 fix) |
| P7 | Clicking a task box flips only that line's `[ ]`/`[x]`, the title shows edited, scroll stays put | 2026-11-13 | Wrong line changed; preview jumping to top |
| P8 | After a tick, Cmd+\ to the editor and Cmd+Z restores the box | 2026-11-13 | Tick not undoable |
| P9 | A `- [ ]` line inside a fenced code block shows as code, not a checkbox | 2026-11-13 | Toggling text inside code |
| P10 | Code-block copy icon copies the block and shows a checkmark | 2026-11-13 | Copy broken by icon change |
| P11 | Light and dark mode: highlight, checkboxes and copy icon are readable | 2026-11-13 | Theme regressions |
| P12 | A paragraph that is only `` `cmd` `` (one line, or several lines inside one pair of backticks) shows as a code block with the copy icon, and copying keeps the line breaks; `Run `make` now` stays inline | 2026-11-13 | Copy icon missing on standalone code; prose code turned into blocks |
| P13 | Open a `.docx`: the toolbar Style popup is about 130 pt wide and switches heading styles; `make` prints no deprecation warnings | 2026-11-13 | Toolbar sizing broken by the Auto Layout change |
| P14 | In a `.docx`: B, I, U, S toolbar buttons are enabled; each toggles its style on the selection, on and off; Cmd+Z undoes it; the title shows edited | 2026-11-13 | F10: buttons permanently disabled |
| P15 | In a `.docx` with nothing selected: Cmd+B then typing gives bold text | 2026-11-13 | Typing attributes not updated |
| P16 | In a `.md`: select a word, Cmd+B gives `**word**`, Cmd+B again removes it; Cmd+I on a bold word gives `***word***`; Format > Underline is greyed out; in a `.txt` all four are greyed out | 2026-11-13 | Marker toggling breaking bold/italic combinations |

## Findings log

| ID | Date | Finding | Status |
|---|---|---|---|
| F1 | 2026-11-13 | Workflow uploaded `Notepad.zip` and wrote the zip's sha256 into a cask that downloads `Notepad.dmg`. A CI release would have broken `brew install`. | Fixed: workflow builds and verifies `Notepad.dmg` (R7, R13, R17, R18) |
| F2 | 2026-11-13 | Releases 2.0.0 to 2.2.2 were made by hand; every tag run failed ("release already exists") or was cancelled, so the tap was updated by hand. | Fixed: existing releases run in TAP-SYNC mode (R20) |
| F3 | 2026-11-13 | The 2.2.2 `Notepad.dmg` on the tap is ad-hoc signed (no Developer ID certificate, not notarized). Gatekeeper blocks it on other Macs. | Open: needs a Developer ID certificate |
| F4 | 2026-11-13 | `brew upgrade` 2.1.1 to 2.2.2 failed with "App source '/Applications/Notepad.app' is not there" because the installed app had been removed outside brew. Local state, not a pipeline bug. | Workaround: `brew uninstall --cask --force notepad`, then reinstall |
| F5 | 2026-11-13 | Audit: `GH_TOKEN` and `TAP_TOKEN` were set for the whole job, so the build step could read them. | Fixed: each token is set only on the steps that use it |
| F6 | 2026-11-13 | Preview applied italic/bold rules inside link URLs, so `my_file_name.md` became `my<em>file</em>name.md` and broke the link. | Fixed in 2.3.0: URLs are parked before inline rules (P5) |
| F7 | 2026-11-13 | Cmd+Z in the preview does not undo a task tick (the web view has focus). | Open: undo from the editor (P8) |
| F8 | 2026-11-13 | `make` failed at codesign with "resource fork, Finder information, or similar detritus not allowed" when building in an iCloud-synced folder (~/Documents): sync re-adds Finder attributes after `xattr -cr`. | Fixed: the Makefile signs and verifies a copy in `$TMPDIR/notepad-build`; `dmg` and `install` copy from that clean signed copy |
| F9 | 2026-11-13 | The first v2.3.0 upload had a 2.3.0 `Info.plist` but a 2.2.2 binary (old "Copied!" text, none of the new code). R11 only checked the plist version. | Fixed in 2.3.1: source fingerprint in the binary (`make`, R21) and clean checkout at the tag (R6). The second upload had the same 2.2.2 binary, which fits a working copy whose main.mm was reverted outside git (likely iCloud sync of ~/Documents); fingerprint alone cannot catch that, R6 can. Build releases from a fresh clone outside iCloud |
| F10 | 2026-11-13 | Bold/Italic/Underline/Strikethrough toolbar buttons and menu items were always disabled: `toggleBoldface:` etc. are UIKit names with no handler in AppKit, so the responder chain found no target (present since 1.4.0). | Fixed in 2.3.2: handlers in AppDelegate (P14 to P16) |
