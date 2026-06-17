local Actions = require("snacks-file-browser.actions")
local Utils = require("snacks-file-browser.utils")

---@type SnacksFileBrowser.Config
local default_config = {
	show_empty = true,
	show_hidden = true,
	show_ignored = true,
	follow_symlinks = false,
	supports_live = true,
	notify_lsp_clients_on_rename = true,
	actions = Actions.actions,
	on_confirm = Utils.edit_paths,
	format = 'file',
	---@param picker SnacksFileBrowser
	on_show = function(picker)
		Utils.update_title(picker, picker:cwd())
	end,
	layout = { preset = "default" },
	win = {
		input = {
			keys = {
				["<M-n>"] = { "create_new", mode = { "n", "i" } },
				["<M-CR>"] = { "multi_confirm", mode = { "n", "i" } },
				["<M-e>"] = { "edit_selected", mode = { "n", "i" } },
				["<CR>"] = { "confirm", mode = { "n", "i" } },
				["<BS>"] = { "smart_cd_parent", mode = { "n", "i" } },
				["<M-BS>"] = { "cd_parent", mode = { "n", "i" } },
				["<C-]>"] = { "sync_cwd", mode = { "n", "i" } },
				["<M-c>"] = { "yank_paths", mode = { "n", "i" } },
				["<C-c>"] = { "yank_to_clipboard", mode = { "n", "i" } },
				["<C-v>"] = { "paste_from_clipboard", mode = { "n", "i" } },
				["<M-p>"] = { "copy", mode = { "n", "i" } },
				["<M-m>"] = { "move", mode = { "n", "i" } },
				["<M-d>"] = { "delete", mode = { "n", "i" } },
				["<M-r>"] = { "rename", mode = { "n", "i" } },
				["<M-o>"] = { "open_system", mode = { "n", "i" } },
				["<F5>"] = { "refresh", mode = { "n", "i" } },
			},
		},
		list = {
			keys = {
				["<M-n>"] = { "create_new", mode = { "n", "i" } },
				["<M-e>"] = { "edit_selected", mode = { "n", "x" } },
				["<CR>"] = { "confirm", mode = { "n", "x" } },
				["<M-CR>"] = { "multi_confirm", mode = { "n", "x" } },
				["<BS>"] = { "cd_parent", mode = { "n" } },
				["<C-]>"] = { "sync_cwd", mode = { "n" } },
				["<M-c>"] = { "yank_paths", mode = { "n", "i" } },
				["<C-c>"] = { "yank_to_clipboard", mode = { "n", "x" } },
				["<C-v>"] = { "paste_from_clipboard", mode = { "n", "x" } },
				["p"] = { "copy", mode = { "n" } },
				["m"] = { "move", mode = { "n" } },
				["d"] = { "delete", mode = { "n", "x" } },
				["r"] = { "rename", mode = { "n" } },
				["o"] = { "open_system", mode = { "n", "x" } },
				["<F5>"] = { "refresh", mode = { "n" } },
			}
		}
	},
}

---@type SnacksFileBrowser.Config
local current_config = vim.deepcopy(default_config)

local M = {}

function M.set(config)
	current_config = vim.tbl_deep_extend('force', current_config, config)
end

---@return SnacksFileBrowser.Config
function M.get()
	return current_config
end

function M.reset()
	current_config = vim.deepcopy(default_config)
end

return M
