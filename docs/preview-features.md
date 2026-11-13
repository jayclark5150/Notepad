# Preview features spec (2.3.0)

Risk tier: **Medium**. The task-list click changes the user's document.
Checks: [`regression-checklist.md`](../regression-checklist.md), section "Markdown preview".

## Purpose

Make the rendered preview (Cmd+\\) handle the extended Markdown people paste
from other tools, let task lists be ticked in place, and make code easy to copy.

## Scope

In scope: `main.mm` preview only (`loadPreviewScrolledTo:`, `markdownToHTML:`,
`applyInlineMarkdown:`, the `toggleTask` message handler).
Out of scope: the WYSIWYM editor (it still shows `==`, `~`, `^`, `:joy:` as
typed), Pandoc export, .docx and .doc files (no preview).

## Behaviour

| Feature | Input | Preview output |
|---|---|---|
| Emoji shortcode | `:joy:` | 😂 (about 500 GitHub names; unknown names left as typed) |
| Highlight | `==text==` (no space just inside the `==`) | `<mark>` |
| Subscript | `H~2~O` (no spaces inside) | `<sub>` |
| Superscript | `X^2^` (no spaces inside) | `<sup>` |
| Task list | `- [ ]`, `* [x]`, `+ [X]` at line start | real checkbox |
| Code block | fenced block | copy icon, checkmark for 1.5 s after copying |

Inline code spans and link or image URLs are never rewritten by these rules.

## Task-list click contract

1. Each checkbox carries `data-line`, the 0-based source line index.
2. A click posts `{line, checked}` to the `toggleTask` handler.
3. Native code re-reads that line from the current text. It changes the one
   box character only if the line is still a task line; otherwise it
   re-renders the preview and changes nothing.
4. The change goes through `shouldChangeTextInRange:` and `didChangeText`, so
   it is undoable (from the editor), marks the document edited, and is saved
   only when the user saves.
5. The preview re-renders at the same scroll position.

## Assumptions

- Text is stored with `\n` line endings (loading normalizes CRLF and CR).
- Only the page the app generates can post messages; inputs are still
  type-checked (`NSNumber`) and bounds-checked.

## Acceptance criteria

1. The four sample lines (`:joy:`, `==very important words==`, `H~2~O`, `X^2^`)
   render as emoji, highlight, subscript and superscript.
2. `a == b == c`, `x ~ y ~ z`, `10:30:45` and `:notreal:` render unchanged.
3. Formatting characters inside backticks and URLs render unchanged.
4. Clicking a task box changes exactly that line's `[ ]` or `[x]`, marks the
   window edited, and leaves the scroll position.
5. The copy icon copies the block's text and shows a checkmark.
6. `javascript:` and similar URLs are still replaced with `#`.

## Residual risks

- Cmd+Z while the preview is showing goes to the web view, not the editor;
  switch to the editor (Cmd+\\) to undo a tick.
- Not compiled or run on macOS by Claude; checked with a GNUstep syntax pass,
  a Python replica of the inline rules, and the page script in Node.
