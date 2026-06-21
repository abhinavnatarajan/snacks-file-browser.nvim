# Snacks File Browser

A file browser for neovim that uses the fuzzy finder, picker, and files source from `snacks.nvim`.
This is similar to `nvim-telescope/Telescope-file-browser.nvim`.

## Requirements

- [fd](https://github.com/sharkdp/fd)
- [wl-clipboard](https://github.com/bugaevc/wl-clipboard) for Linux Wayland file clipboard actions. macOS clipboard actions use the system `osascript` command.

## Installation

Use your favourite plugin manager to install:

```lua
-- lazy.nvim
return {
    'abhinavnatarajan/snacks-file-browser.nvim',
    dependencies = { 'folke/snacks.nvim' },
    opts = {
    -- optional config
    }
}

```

## Usage

There are three main functions with both Lua and Vim commands:

```lua
require('snacks-file-browser').open(opts)
require('snacks-file-browser').save_buffer(opts)
require('snacks-file-browser').save_buffer_as(opts)
```

```vim
:SnacksFileBrowser " open the file browser
:SnacksFileBrowserSave " to save the current buffer, opening a dialog if the buffer is unnamed
:SnacksFileBrowserSaveAs " to save the current buffer with a new name
```

You can override any configuration value in the opts table or arguments to the command.
For example, to open the file browser in the parent directory of the current buffer, you can use:

```lua
require('snacks-file-browser').open ({
    cwd = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
})
```
```vim
:SnacksFileBrowser cwd=..
```

## Configuration

The file browser can be configured by passing a table to the `require('snacks-file-browser').setup` function.
The available options and their defaults can be seen in [`types.lua`](lua/snacks-file-browser/types.lua) and [`config.lua`](lua/snacks-file-browser/config.lua).
The `on_confirm` callback receives the picker and a list of picker items. Each item includes a `file` path and may include `dir = true` for directories.

## Default Keybindings

### Input Window

| Keybinding | Modes  | Action                                                                         |
| ---        | ---    | ---                                                                            |
| `<M-n>`    | `n, i` | Create a new file or directory.                                                |
| `<M-CR>`   | `n, i` | Confirm selected item(s).                                                      |
| `<M-e>`    | `n, i` | Edit selected or highlighted path(s).                                          |
| `<CR>`     | `n, i` | Accept the input or highlighted item.                                          |
| `<BS>`     | `n, i` | Navigate up one directory if the input is empty, otherwise delete a character. |
| `<M-BS>`   | `n, i` | Navigate up one directory.                                                     |
| `<C-]>`    | `n, i` | Set Neovim's tab-local cwd to the picker's directory.                          |
| `<M-c>`    | `n, i` | Yank selected path(s) to a register.                                           |
| `<C-c>`    | `n, i` | Yank selected item(s) to the system clipboard. Linux Wayland and macOS.        |
| `<C-v>`    | `n, i` | Paste item(s) from the system clipboard. Linux Wayland and macOS.              |
| `<M-p>`    | `n, i` | Copy selected item(s) to the current directory.                                |
| `<M-m>`    | `n, i` | Move selected item(s) to the current directory.                                |
| `<M-d>`    | `n, i` | Delete selected item(s).                                                       |
| `<M-r>`    | `n, i` | Rename the highlighted item.                                                   |
| `<M-o>`    | `n, i` | Open selected item(s) with the system's default application.                   |
| `<F5>`     | `n, i` | Refresh the file browser.                                                      |

### List Window

| Keybinding | Modes  | Action                                                               |
| ---        | ---    | ---                                                                  |
| `<M-n>`    | `n, i` | Create a new file or directory.                                      |
| `<M-e>`    | `n, x` | Edit selected or highlighted path(s).                                |
| `<CR>`     | `n, x` | Accept the input or highlighted item.                                |
| `<M-CR>`   | `n, x` | Confirm selected item(s).                                            |
| `<BS>`     | `n`    | Navigate up one directory.                                           |
| `<C-]>`    | `n`    | Set Neovim's tab-local cwd to the picker's directory.                |
| `<M-c>`    | `n, i` | Yank selected path(s) to a register.                                 |
| `<C-c>`    | `n, x` | Yank selected item(s) to the system clipboard. Linux Wayland and macOS. |
| `<C-v>`    | `n, x` | Paste item(s) from the system clipboard. Linux Wayland and macOS.    |
| `p`        | `n`    | Copy selected item(s) to the current directory.                      |
| `m`        | `n`    | Move selected item(s) to the current directory.                      |
| `d`        | `n, x` | Delete selected item(s).                                             |
| `r`        | `n`    | Rename the highlighted item.                                         |
| `o`        | `n, x` | Open selected item(s) with the system's default application.         |
| `<F5>`     | `n`    | Refresh the file browser.                                            |

## Available Actions

The actions below use selected items when selections exist. Unless stated otherwise, actions that operate on selected items fall back to the highlighted item when nothing is selected, even if the highlighted item does not match the current input. If there are no selected items and no highlighted item, they show an error and do nothing. The `accept` action is the exception: it ignores selected items and treats an unmatched highlighted item as a request to create from the current input.

| Action | Behaviour |
| --- | --- |
| `cd_parent` | Navigate up one directory and refresh the picker. |
| `smart_cd_parent` | If the input is empty, run `cd_parent`; otherwise, delete one character from the input. |
| `refresh` | Rerun the finder. |
| `edit_selected` | Edit selected path(s), or the highlighted path when nothing is selected, and close the picker. |
| `sync_cwd` | Set Neovim's tab-local cwd to the picker's current directory with `:tcd`. |
| `accept` | Accept only the highlighted or matched item; it intentionally ignores selected items so you can enter directories without clearing selections. If there is no matching item, it uses the current input: a trailing path separator creates that directory and enters it; otherwise a synthetic file item is passed to `on_confirm` as a one-item list. If the item is a directory, the picker enters it. If the item is a file, the item is passed to `on_confirm` as a one-item list. |
| `multi_confirm` | Pass selected item(s) to `on_confirm`; falls back to the highlighted item when nothing is selected. The default `on_confirm` closes the picker and edits file items, skipping directories. |
| `rename` | Rename the highlighted item. This action does not use selected items as a fallback source. |
| `create_new` | Create a new file or directory. If the picker input is empty, prompt for a path; otherwise use the picker input. A trailing path separator creates a directory and enters it; otherwise a file is created and the picker moves to its parent directory. |
| `yank_paths` | Yank selected path(s), or the highlighted path when nothing is selected, to the active register as linewise text. |
| `yank_to_clipboard` | Yank selected item(s), or the highlighted item when nothing is selected, to the system clipboard. Supports Linux Wayland via `wl-copy` and macOS via `osascript`/JXA. |
| `paste_from_clipboard` | Paste files from the system clipboard into the picker's current directory. Supports Linux Wayland via `wl-paste` and macOS via `osascript`/JXA. |
| `copy` | Copy explicitly selected item(s) to the picker's current directory. This action does not fall back to the highlighted item. |
| `move` | Move explicitly selected item(s) to the picker's current directory. This action does not fall back to the highlighted item. |
| `delete` | Delete selected item(s), or the highlighted item when nothing is selected, after confirmation. Open buffers for deleted files are wiped. |
| `open_system` | Open selected item(s), or the highlighted item when nothing is selected, with the system's default application. |
