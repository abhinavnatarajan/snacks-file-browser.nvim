# Code Review Planning Notes

This document captures code review observations for later triage. It focuses on clarity of intent, code reuse, modularity, architecture, maintainability, bugs, corner cases, and performance.

## Critical Issues

### `create_new` Crashes When Creating Directories

- Location: `lua/snacks-file-browser/actions.lua:234`
- `create_new` calls `Utils.mkdir(...)`, but `utils.lua` exports `mkdir_async`, not `mkdir`.
- Any `create_new` path ending in a path separator will raise `attempt to call field 'mkdir' (a nil value)`.
- This affects `<M-n>` and direct `create_new` action use for directories.

### Recursive Directory Copy Has A Callback Signature Bug

- Location: `lua/snacks-file-browser/utils.lua:284-286`
- `copy_path(child_path, new_dir, type, function(err) ...)` treats the first callback argument as an error.
- `copy_path` actually invokes callbacks as `(success, errors)`.
- A successful child copy passes `true` into `err`, causing `vim.list_extend(errors, true)` to crash.
- A failed child copy passes `nil` as the first argument, so the actual errors are ignored.
- This makes copying non-empty directories unreliable.

## High Priority Issues

### Move Error Handling Has Inconsistent Callback Contracts

- Locations: `lua/snacks-file-browser/utils.lua:356`, `lua/snacks-file-browser/utils.lua:359`, `lua/snacks-file-browser/utils.lua:372-374`, `lua/snacks-file-browser/actions.lua:368-374`
- `move_paths` sometimes calls `callback({ error = ... })`, while callers expect `(success, err)`.
- Since a table is truthy, action code can treat an error as success and notify that files were moved.
- The non-writable destination branch does not return, so move processing continues after reporting the error.
- The rename error format string `("Could not move %s to %\n%s")` contains an invalid `%` sequence and can crash while constructing the error.
- `actions.lua` expects errors to be strings and calls `table.concat(err, "\n")`, but `move_paths` currently stores tables in `errors`.

### Copy Error Handling Has Inconsistent Callback Contracts

- Locations: `lua/snacks-file-browser/utils.lua:307-313`, `lua/snacks-file-browser/actions.lua:343-346`
- `copy_paths` calls `callback(nil, error, message)` or `callback(nil, "EACCES", ...)` on destination errors.
- Action code expects the second callback argument to be a list of error strings.
- Passing a string to `table.concat(errors, "\n")` can crash.
- The non-writable destination branch does not return, so copy processing continues after reporting the error.

### Selection Fallback Can Operate On Unmatched Items

- Location: `lua/snacks-file-browser/actions.lua:26-34`
- `resolve_selection` has a `needs_match` option, but no current action passes `needs_match = true`.
- Actions such as `edit_selected`, `multi_confirm`, `open_system`, `yank_paths`, `yank_to_clipboard`, and `delete` can fall back to `item` even if `item.score == 0`.
- `confirm` treats `score == 0` as no match, but shared fallback behavior does not.
- This is especially risky for destructive actions. Typing non-matching input and invoking delete could delete the previously highlighted item instead of doing nothing.

## Medium Priority Issues

### Directory Copy Does Not Handle Unreadable Directory Iterators

- Location: `lua/snacks-file-browser/utils.lua:273-277`
- `vim.fs.dir(path, { follow = false })` can fail and return `nil, err`.
- The code immediately iterates `for name, type in children do`, which can attempt to call a nil iterator.
- This should report a copy error instead.

## Architecture And Maintainability Themes

### Standardize Filesystem Callback Contracts

- Current utilities mix callback shapes such as `(success, errors)`, `(nil, error, message)`, and a single error table.
- This causes several real bugs in copy and move flows.
- Prefer one convention across all filesystem helpers, for example `callback(ok, errors)` where `errors` is always `string[]|nil`.

### Centralize Selection Semantics

- `resolve_selection` centralizes some fallback behavior, but `copy` and `move` bypass it.
- `needs_match` exists but is unused.
- Destructive and external actions should have explicit semantics for selected items, highlighted fallback, and unmatched picker items.

### Clarify The Action/Utility Boundary

- `actions.lua` currently mixes UI intent, confirmation prompts, clipboard shell commands, and direct filesystem operations.
- `utils.lua` contains lower-level copy, move, create, and rename operations, but the boundary is uneven.
- Consider having actions collect UI intent and confirmation, while utilities handle filesystem operations with consistent result types.

### Simplify Directory Creation APIs

- `mkdir_async` is complex, `create_file` uses synchronous `vim.fn.mkdir(dir, "p")`, and `create_new` calls a non-existent `Utils.mkdir`.
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
