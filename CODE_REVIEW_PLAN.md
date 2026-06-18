# Code Review Planning Notes

This document captures code review observations for later triage. It focuses on clarity of intent, code reuse, modularity, architecture, maintainability, bugs, corner cases, and performance.

## High Priority Issues

- None currently tracked.

## TODO

- [x] Add a minimal headless Neovim test harness and initial focused tests.
- [x] Refresh stale architecture notes now that clipboard shell commands and `vim.ui.open` moved into `utils.lua`.
- [ ] Standardize `mkdir_async`, `create_file`, `rename_path`, and delete result contracts around `ok, errors`.
- [x] Move delete filesystem behavior and buffer cleanup into `utils.lua`, keeping confirmation and notifications in `actions.lua`.
- [ ] Simplify directory creation behind one clear `mkdir_p` or `mkdir_p_async` helper.
- [ ] Revisit composed clipboard paste utilities after async helper callback shapes are consistent.
- [ ] Defer host-qualified and UNC-like clipboard URI support until there is a reliable platform-specific resolver or library.

## Architecture And Maintainability Themes

### Standardize Filesystem Callback Contracts

- Copy and move operations now use `callback(ok, errors)` where `errors` is always `string[]|nil`.
- Delete now returns `ok, errors, deleted_count`, where `errors` is always `string[]|nil`.
- Create now returns `ok, errors, did_create`, where `errors` is always `string[]|nil` and `did_create` reports whether a new file or directory was actually created.
- Later standardize `mkdir_async` and rename error handling around one result convention as well.
- Prefer one convention across filesystem helpers, for example `callback(ok, errors)` where `errors` is always `string[]|nil`.
- Later standardize async helpers around one callback shape, for example `callback(ok, errors, result)`, before composing multi-step operations such as clipboard paste directly inside utilities.

### Centralize Selection Semantics

- `resolve_selection` requires every caller to explicitly declare fallback, output, and notification behavior.
- `accept` has special input/highlight handling and intentionally does not use shared selected-item fallback semantics.
- `copy` and `move` explicitly require selected items because falling back to the highlighted item would copy or move it into its current directory.

### Clarify The Action/Utility Boundary

- `actions.lua` now delegates system opening, clipboard shell commands, clipboard URI parsing, copy, move, create, and rename helpers to `utils.lua`.
- Delete filesystem behavior and buffer cleanup are now delegated to `utils.lua`.
- Keep actions focused on selection, confirmation, notifications, and picker refresh; keep filesystem operations in utilities with consistent result types.

### Clipboard URI Handling

- Clipboard paste currently accepts only local `file:` URIs with no authority or explicit `localhost` authority.
- Revisit whether a platform-specific utility or library can reliably resolve host-qualified file URIs or UNC-like forms to local paths.
- Avoid relying on `vim.uri_to_fname` alone for locality checks; it does not fully resolve these cases.

### Simplify Directory Creation APIs

- `mkdir_async` is complex, while `create_file` uses synchronous `vim.fn.mkdir(dir, "p")`.
- A single exported `mkdir_p` helper, sync or async, would make the intended API clearer.

### Add Focused Tests

- A minimal headless Neovim test harness now covers clipboard URI parsing, CRLF clipboard output, create error/existence handling, copy callback errors, non-empty directory copying, copy selection fallback, and delete utility/action behavior.
- High-value behavioral tests would cover:
- `create_new` directory creation.
- Move/copy failures for non-writable destinations.
- Command argument parsing for `:SnacksFileBrowser cwd=..`.
- `save_buffer_as` with paths containing spaces or Ex-special characters.
- Selection fallback behavior for destructive actions.

## Verification From Review

- The review was initially performed read-only against commit `1f6bbed feat!: update actions`.
- `luac -p` passed for all Lua files.
- No behavioral filesystem tests were run during the review because those would create, move, copy, or delete files.
