# Snacks File Browser

A file browser for neovim that uses the fuzzy finder, picker, and files source from `snacks.nvim`.
This is similar to `nvim-telescope/Telescope-file-browser.nvim`.

## Requirements

- [fd](https://github.com/sharkdp/fd)

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
require('snacks-file-browser').open {
    cwd = vim.fs.dirname(vim.api.nvim_buf_get_name(0))
}
```
```vim
:SnacksFileBrowser cwd=..
```

## Configuration

The file browser can be configured by passing a table to the `require('snacks-file-browser').setup` function.
The available options and their defaults can be seen in [`types.lua`](lua/snacks-file-browser/types.lua) and [`config.lua`](lua/snacks-file-browser/config.lua).

## Default Keybindings

### Input Window

| Keybinding | Action                                                                         |
| ---        | ---                                                                            |
| `<CR>`     | Pass the selected item to a callback (by default `vim.cmd.edit`).              |
| `<M-n>`    | Create a new file or directory.                                                |
| `<M-e>`    | Edit the selected file(s) (will skip directories).                             |
| `<BS>`     | Navigate up one directory if the input is empty, otherwise delete a character. |
| `<M-BS>`   | Navigate up one directory.                                                     |
| `<C-]>`    | Set the current working directory of neovim to the picker's directory.         |
| `<M-y>`    | Yank the selected file(s) to the clipboard.                                    |
| `<M-p>`    | Copy the selected file(s) to the current directory.                            |
| `<M-m>`    | Move the selected file(s) to the current directory.                            |
| `<M-d>`    | Delete the selected file(s).                                                   |
| `<M-r>`    | Rename the selected file.                                                      |
| `<M-o>`        | Open the selected item(s) with the system's default application. |
| `<F5>`     | Refresh the file browser.                                                      |

### List Window

| Keybinding | Action                                                           |
| ---        | ---                                                              |
| `<BS>`     | Navigate up one directory.                                       |
| `y`        | Yank the selected file(s) to the clipboard.                      |
| `p`        | Copy the selected file(s) to the current directory.              |
| `m`        | Move the selected file(s) to the current directory.              |
| `r`        | Rename the selected file.                                        |
| `d`        | Delete the selected file(s).                                     |
| `o`        | Open the selected item(s) with the system's default application. |
| `<F5>`     | Refresh the file browser.                                        |

## Available Actions

* `navigate_parent`: Navigate up one directory.
* `backspace`: If the input is empty, navigate up one directory. Otherwise, delete a character.
* `refresh`: Rerun the finder.
* `edit`: Edit the selected item(s).
* `set_cwd`: Set the cwd of neovim from the picker.
* `confirm`: Pass the matched item in the picker list to a user-supplied callback (default `vim.cmd.edit`).
    * If there is no item matching the input and no highlighted item in the picker:
        * If the input ends with a path separator, create a new directory and navigate into it.
        * Otherwise, pass the input to the callback.
    * If a directory is highlighted in the picker, navigate into it.
    * If a file is matched/highlighted in the picker, pass it to the callback.
    Note that the `confirm` action does not deal with selected items.
    This is to allow one to descend into directories while retaining currently selected items.
* `multi_confirm`: Pass the picker and the paths of all selected items to a user-supplied callback.
By default, the callback closes the picker and calls `vim.cmd.edit` on all the selected items.
* `rename`: Rename the currently selected file or directory.
* `create_new`: Create a new file or directory based on the input in the picker.
* `yank`: Yank the selected item(s) to the clipboard.
* `copy`: Copy the selected item(s) to the current directory.
* `move`: Move the selected item(s) to the current directory.
* `delete`: Delete the selected item(s).
* `open_system`: Open the selected item(s) with the system's default application.
