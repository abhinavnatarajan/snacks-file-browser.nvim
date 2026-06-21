# AGENTS.md

## Commands

- `make lint` runs `luac -p` over `lua/` and `tests/`; it is only a Lua syntax check.
- `make test` runs `nvim --headless -u NONE -l tests/run.lua`.
- There are no tracked package manifests, lockfiles, formatter configs, or CI workflows.

## Test Notes

- `tests/run.lua` is a custom headless Neovim harness, not busted/plenary.
- The harness mocks `require("snacks")`, `vim.system`, `vim.ui.select`, and selected filesystem calls; tests do not require installing `snacks.nvim`, `wl-clipboard`, or macOS `osascript`.
- There is no built-in single-test flag; temporarily narrow `tests/run.lua` only if needed and restore it before finishing.

## Architecture

- Public entrypoint is `lua/snacks-file-browser/init.lua`; `setup()` registers `:SnacksFileBrowser`, `:SnacksFileBrowserSave`, and `:SnacksFileBrowserSaveAs`.
- `open()` builds a `snacks.picker` backed by `fd` through `snacks.picker.source.proc`; runtime use requires `fd` and `snacks.nvim`.
- Defaults and keymaps live in `lua/snacks-file-browser/config.lua`; public type annotations live in `lua/snacks-file-browser/types.lua`.
- Picker actions live in `lua/snacks-file-browser/actions.lua`; filesystem, clipboard, buffer, and LSP rename helpers live in `lua/snacks-file-browser/utils.lua`.

## Clipboard Gotchas

- Keep platform-specific clipboard code inside `utils.lua`; `actions.lua` should call `Utils.get_clipboard_paths()`.
- Linux paste uses `wl-paste -t text/uri-list -n` and parses file URIs; macOS paste uses `osascript -l JavaScript` and expects a JSON array of POSIX paths.
- `yank_to_clipboard` still uses `wl-copy` and is Linux Wayland-only.
- If changing user-visible action behavior or keymaps, update both `README.md` and relevant tests.
