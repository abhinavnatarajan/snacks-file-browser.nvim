local Config = require('snacks-file-browser.config')
local Actions = require('snacks-file-browser.actions')
local os_pathsep = package.config:sub(1, 1)

local M = {}

---Needs to be called before using the file browser
function M.setup(config)
	Config.set(config or {})
end

--- Open the file browser picker with specified actions and keys
-- -@param opts? table  -- Optional configuration table
function M.open(opts)
	opts = vim.tbl_deep_extend('force', Config.get(), opts or {})

	-- Configure the picker to use the actions and keys from options or defaults
	local cwd = opts.cwd or vim.uv.cwd()
	return require('snacks').picker({
		cwd = cwd,
		show_empty = opts.show_empty,
		hidden = opts.hidden,
		ignored = opts.ignored,
		follow = opts.follow,
		supports_live = true,
		layout = opts.layout,
		on_confirm = opts.on_confirm,
		finder = function(_opts, ctx)
			local args = {
				"--follow",
				"--max-depth=1",
				"--color=never",
				"--strip-cwd-prefix"
			}
			if _opts.hidden then
				vim.list_extend(args, { "--hidden" })
			end
			if _opts.ignored then
				vim.list_extend(args, { "--no-ignore" })
			end
			if _opts.follow then
				vim.list_extend(args, { "--follow" })
			end
			return require('snacks.picker.source.proc').proc({
				_opts,
				{
					cmd = "fd",
					args = args,
					transform = function(item, _ctx)
						-- fdfind appends a "/" to the end of a file path if it is a directory
						if item.text:sub(-1) == os_pathsep then
							item.dir = true
						end
						item.file = vim.fs.normalize(vim.fs.abspath(vim.fs.joinpath(_ctx.picker:cwd(), item.text)))
					end,
				}
			}, ctx)
		end,
		format = 'file',
		on_show = function(picker)
			Actions.update_title(picker, picker:cwd())
		end,
		actions = Actions.actions,
		win = opts.win
	})
end

setmetatable(M, {
	__call = function(table, opts)
		table.open(opts)
	end,
})

return M
