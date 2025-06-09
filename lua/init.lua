local Config = require('snacks-file-browser.config')
local Actions = require('snacks-file-browser.actions')

local M = {}

---Needs to be called before using the file browser
function M.setup(config)
	Config.set(config or {})
end

--- Open the file browser picker with specified actions and keys
-- -@param opts? table  -- Optional configuration table
function M.file_browser(opts)
	opts = vim.tbl_deep_extend('force', Config.get(), opts or {})

	-- Configure the picker to use the actions and keys from options or defaults
	local cwd = opts.cwd or M.uv.cwd()
	local picker = require('snacks').picker({
		cwd = cwd,
		show_empty = opts.show_empty,
		hidden = opts.hidden,
		ignored = opts.ignored,
		follow = opts.follow,
		supports_live = true,
		layout = opts.layout,
		finder = function(_opts, ctx)
			local args = {
				"--follow",
				"--max-depth=1",
				"--color=never",
			}
			if _opts.hidden then
				vim.list_extend(args, { "--hidden" })
			end
			if _opts.ignored then
				vim.list_extend(args, { "--no-ignore" })
			end
			return require('snacks.picker.source.proc').proc({
				_opts,
				{
					cmd = "fd",
					args = args,
					transform = function(item, ctx)
						-- fdfind appends a "/" to the end of a file path if it is a directory
						if item.text:sub(-1) == M.pathsep then
							item.dir = true
						end
						item.file = vim.fs.normalize(vim.fs.abspath(vim.fs.joinpath(ctx.picker:cwd(), item.text)))
					end,
				}
			}, ctx)
		end,
		format = 'file',
		on_show = function(picker)
			M.update_title(picker, picker:cwd())
		end,
		actions = Actions.actions,

		win = opts.win
	})
end

M.setup()

setmetatable(M, {
	__call = function(table, opts)
		table.file_browser(opts)
	end,
})
