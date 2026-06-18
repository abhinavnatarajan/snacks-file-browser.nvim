---@meta _

---@class SnacksFileBrowser.Config : snacks.picker.Config
---@field show_hidden boolean -- show hidden files and directories
---@field show_ignored boolean -- show ignored files and directories
---@field follow_symlinks boolean -- follow symbolic links
---@field supports_live boolean -- live update the browser as you type
---@field notify_lsp_clients_on_rename boolean -- notify attached LSP clients when a file is renamed
---@field on_confirm fun(picker: SnacksFileBrowser, items: SnacksFileBrowser.Item[]): boolean|nil -- action to invoke for the confirm and multi_confirm actions

---@class SnacksFileBrowser : snacks.Picker
---@field opts SnacksFileBrowser.Config

---@class SnacksFileBrowser.Item : snacks.picker.Item
---@field file string
---@field dir? boolean
