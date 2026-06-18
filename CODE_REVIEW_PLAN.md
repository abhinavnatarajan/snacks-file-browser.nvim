# Code Review Planning Notes

This document captures code review observations for later triage. It focuses on clarity of intent, code reuse, modularity, architecture, maintainability, bugs, corner cases, and performance.

## High Priority Issues

### Selection Fallback Can Operate On Unmatched Items

- Location: `lua/snacks-file-browser/actions.lua:26-34`
- `resolve_selection` has a `needs_match` option, but no current action passes `needs_match = true`.
- Actions such as `edit_selected`, `multi_confirm`, `open_system`, `yank_paths`, `yank_to_clipboard`, and `delete` can fall back to `item` even if `item.score == 0`.
- `confirm` treats `score == 0` as no match, but shared fallback behavior does not.
- This is especially risky for destructive actions. Typing non-matching input and invoking delete could delete the previously highlighted item instead of doing nothing.

## Architecture And Maintainability Themes

### Standardize Filesystem Callback Contracts

- Copy and move operations now use `callback(ok, errors)` where `errors` is always `string[]|nil`.
- Later standardize create, delete, and rename error handling around one result convention as well.
- Prefer one convention across filesystem helpers, for example `callback(ok, errors)` where `errors` is always `string[]|nil`.

### Centralize Selection Semantics

- `resolve_selection` centralizes some fallback behavior, but `copy` and `move` bypass it.
- `needs_match` exists but is unused.
- Destructive and external actions should have explicit semantics for selected items, highlighted fallback, and unmatched picker items.

### Clarify The Action/Utility Boundary

- `actions.lua` currently mixes UI intent, confirmation prompts, clipboard shell commands, and direct filesystem operations.
- `utils.lua` contains lower-level copy, move, create, and rename operations, but the boundary is uneven.
- Consider having actions collect UI intent and confirmation, while utilities handle filesystem operations with consistent result types.

### Simplify Directory Creation APIs

- `mkdir_async` is complex, while `create_file` uses synchronous `vim.fn.mkdir(dir, "p")`.
- A single exported `mkdir_p` helper, sync or async, would make the intended API clearer.

### Add Focused Tests

- High-value behavioral tests would cover:
- `create_new` directory creation.
- Copying non-empty directories.
- Move/copy failures for non-writable destinations.
- Command argument parsing for `:SnacksFileBrowser cwd=..`.
- `save_buffer_as` with paths containing spaces or Ex-special characters.
- Selection fallback behavior for destructive actions.

## Verification From Review

- The review was initially performed read-only against commit `1f6bbed feat!: update actions`.
- `luac -p` passed for all Lua files.
- No behavioral filesystem tests were run during the review because those would create, move, copy, or delete files.
