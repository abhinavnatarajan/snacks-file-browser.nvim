local default_config = {
	show_empty = true,
	hidden = true,
	ignored = false,
	follow = false,
	supports_live = true,
	layout = {
		preview = true,
		preset = "default",
	},
	win = {
		input = {
			keys = {
				["<M-n>"] = { "create_new", mode = { "n", "i" } },
				["<M-e>"] = { "edit", mode = { "n", "i" } },

				["<BS>"] = { "backspace", mode = { "n", "i" } },
				["<M-BS>"] = { "navigate_parent", mode = { "n", "i" } },
				["<C-d>"] = { "set_cwd", mode = { "i", "n" } },

				["<M-y>"] = { "yank", mode = { "n", "i" } },
				["<M-p>"] = { "copy", mode = { "n", "i" } },
				["<M-m>"] = { "move", mode = { "n", "i" } },
				["<M-d>"] = { "delete", mode = { "n", "i" } },
				["<M-r>"] = { "rename", mode = { "n", "i" } },

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
				["<F5>"] = { "refresh", mode = { "n" } },
			}
		}
	},
}

local current_config = vim.deepcopy(default_config)

local M = {}

function M.set(config)
	current_config = vim.tbl_deep_extend('force', current_config, config)
end

function M.get()
	return current_config
end

function M.reset()
	current_config = vim.deepcopy(default_config)
end

return M
