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

### `save_as` Builds Ex Commands Unsafely

- Locations: `lua/snacks-file-browser/init.lua:22`, `lua/snacks-file-browser/init.lua:30`
- Paths are concatenated directly into Ex commands without `fnameescape` or structured command APIs.
- Paths with spaces, `|`, quotes, or other Ex-special characters can fail or execute unintended commands.
- `silent saveas ++p` is also missing a space before the path, producing commands like `silent saveas ++p/tmp/foo`.

### Selection Fallback Can Operate On Unmatched Items

- Location: `lua/snacks-file-browser/actions.lua:26-34`
- `resolve_selection` has a `needs_match` option, but no current action passes `needs_match = true`.
- Actions such as `edit_selected`, `multi_confirm`, `open_system`, `yank_paths`, `yank_to_clipboard`, and `delete` can fall back to `item` even if `item.score == 0`.
- `confirm` treats `score == 0` as no match, but shared fallback behavior does not.
- This is especially risky for destructive actions. Typing non-matching input and invoking delete could delete the previously highlighted item instead of doing nothing.

### Command Arguments Are Documented But Not Parsed

- Locations: `README.md:43-52`, `lua/snacks-file-browser/init.lua:115-120`
- The README documents `:SnacksFileBrowser cwd=..` as a way to override config.
- The user command callback passes Neovim's command callback object directly into `M.open(opts)`.
- That object has fields like `args`, `fargs`, and `line1`; it is not parsed into `{ cwd = ".." }`.
- As written, command arguments such as `cwd=..` do not set the picker cwd.

## Medium Priority Issues

### `follow_symlinks = false` Is Ignored

- Location: `lua/snacks-file-browser/init.lua:37-51`
- `--follow` is always included in the default `fd` arguments.
- The `follow_symlinks` option only controls whether a duplicate `--follow` is appended.
- The option currently does not disable symlink following.

### `edit_paths` Does Not Reliably Skip Directories

- Location: `lua/snacks-file-browser/utils.lua:10-14`
- Directories are skipped only when the path string ends with the platform separator.
- Picker items store `item.file` as normalized absolute paths, which commonly do not retain trailing separators.
- Selecting a directory and running `edit_selected` can still call `vim.cmd.edit` on the directory.
- Use item metadata or `uv.fs_stat` rather than string suffixes.

### Directory Copy Does Not Handle Unreadable Directory Iterators

- Location: `lua/snacks-file-browser/utils.lua:273-277`
- `vim.fs.dir(path, { follow = false })` can fail and return `nil, err`.
- The code immediately iterates `for name, type in children do`, which can attempt to call a nil iterator.
- This should report a copy error instead.

### Wayland Clipboard Actions Do Not Check Exit Status

- Locations: `lua/snacks-file-browser/actions.lua:300-302`, `lua/snacks-file-browser/actions.lua:311-314`
- `yank_to_clipboard` always reports success after `vim.system(...):wait()`.
- It does not inspect `job.code`, `job.signal`, or stderr.
- Missing `wl-copy`, compositor issues, unsupported MIME types, or command failures can be reported as success.
- `paste_from_clipboard` partially checks output, but not exit status directly.

### File Creation Uses Executable Permissions

- Location: `lua/snacks-file-browser/utils.lua:176`
- New files are opened with mode `0755`.
- Regular files generally should default to `0644`, subject to umask.
- Current behavior can create executable files unexpectedly.

## Low Priority Issues

### Delete Unselects The Action Argument Instead Of Each Deleted Item

- Location: `lua/snacks-file-browser/actions.lua:400-407`
- The loop iterates `selected_items` as `it`, but calls `picker.list:unselect(item)`.
- For multi-selection this unselects the same action argument repeatedly rather than each deleted item.
- Refresh probably masks this today, but the intent is unclear.

### `show_empty` Appears To Be Dead Configuration

- Locations: `lua/snacks-file-browser/config.lua:6`, `lua/snacks-file-browser/types.lua:7`, `lua/snacks-file-browser/init.lua:36-60`
- `show_empty` is defined and documented, but the finder does not read it.
- If it is intended for snacks internals, consider clarifying the name or documentation.
- If it is a browser option, it currently has no effect.

### `Config.set` Accumulates State Across Setup Calls

- Location: `lua/snacks-file-browser/config.lua:68-70`
- `Config.set` deep-extends into `current_config` instead of starting from defaults.
- Calling `setup` multiple times with partial configs leaves previous customizations in place.
- This may be acceptable for plugin-manager setup, but it is surprising for tests and dynamic reconfiguration.

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
