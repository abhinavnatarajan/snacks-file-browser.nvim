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
	on_confirm = Actions.edit_files,
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
				["<M-e>"] = { "multi_confirm", mode = { "n", "i" } },

				["<BS>"] = { "backspace", mode = { "n", "i" } },
				["<M-BS>"] = { "navigate_parent", mode = { "n", "i" } },
				["<C-]>"] = { "set_cwd", mode = { "i", "n" } },

				["<M-y>"] = { "yank", mode = { "i" } },
				["<M-p>"] = { "copy", mode = { "i" } },
				["<M-m>"] = { "move", mode = { "i" } },
				["<M-d>"] = { "delete", mode = { "i" } },
				["<M-r>"] = { "rename", mode = { "i" } },
				["<M-o>"] = { "open_system", mode = { "i" } },
				["y"] = { "yank", mode = { "n", } },
				["p"] = { "copy", mode = { "n" } },
				["m"] = { "move", mode = { "n" } },
				["r"] = { "rename", mode = { "n" } },
				["d"] = { "delete", mode = { "n", } },
				["o"] = { "open_system", mode = { "n", } },

				["<F5>"] = { "refresh", mode = { "n", "i" } },
			},
		},
		list = {
			keys = {
				["<BS>"] = { "navigate_parent", mode = { "n", "x" } },
				["y"] = { "yank", mode = { "n", "x" } },
				["p"] = { "copy", mode = { "n" } },
				["m"] = { "move", mode = { "n" } },
				["r"] = { "rename", mode = { "n" } },
				["d"] = { "delete", mode = { "n", "x" } },
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
