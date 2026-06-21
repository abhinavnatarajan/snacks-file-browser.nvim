local Snacks = require('snacks')
local Config = require('snacks-file-browser.config')

local M = {}

local function parse_command_value(key, value)
	local config_value = Config.get()[key]
	if value == "true" then return true end
	if value == "false" then return false end
	if type(config_value) == "number" then return tonumber(value) end
	return value
end

local function parse_command_opts(command_opts)
	local opts = {}
	for _, arg in ipairs(command_opts.fargs or {}) do
		local key, value = arg:match("^([%w_]+)=(.*)$")
		if key then
			opts[key] = parse_command_value(key, value)
		else
			Snacks.notify.error("Invalid file browser option: " .. arg)
			return nil
		end
	end
	return opts
end

---@param bufnr number Buffer number to save.
---@param items SnacksFileBrowser.Item[] Item containing the absolute filename to save the buffer to.
local function save_as(bufnr, items)
	local path
	if type(items) == "table" then
		if #items > 1 then
			vim.notify("Multiple paths selected.", vim.log.levels.ERROR)
			return
		end
		path = items[1] and items[1].file
	else
		path = items
	end
	if not path then
		vim.notify("No path selected.", vim.log.levels.ERROR)
		return
	end
	local escaped_path = vim.fn.fnameescape(path)
	-- if the buffer name is empty then we can just save it
	-- using the `:w ++p {path}` command
	if vim.api.nvim_buf_get_name(bufnr) == "" then
		vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent w! ++p " .. escaped_path) end)
		return
	end
	-- if the buffer has a non-empty name `oldpath`,
	-- then `:w ++ {path}` will not change the buffer name to `path`
	-- If `cpoptions` contains `A`, the buffer will be marked as not modified
	-- but in reality it does not reflect the state of `oldpath`.
	-- This is misleading, so we instead use "saveas"
	vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent saveas ++p " .. escaped_path) end)
end

function M.open(opts)
	local cwd = opts and opts.cwd or vim.uv.cwd()
	local os_pathsep = package.config:sub(1, 1)
	local finder = function(_opts, ctx)
		_opts.args = {
			"--max-depth=1",
			"--color=never",
			"--strip-cwd-prefix"
		}
		if _opts.show_hidden then
			vim.list_extend(_opts.args, { "--hidden" })
		end
		if _opts.show_ignored then
			vim.list_extend(_opts.args, { "--no-ignore-vcs" })
		end
		if _opts.follow_symlinks then
			vim.list_extend(_opts.args, { "--follow" })
		end
		_opts.cmd = "fd"
		_opts.transform = function(item, _ctx)
			-- fdfind appends a "/" to the end of a file path if it is a directory
			if item.text:sub(-1) == os_pathsep then
				item.dir = true
			end
			item.file = vim.fs.normalize(vim.fs.abspath(vim.fs.joinpath(_ctx.picker:cwd(), item.text)))
		end
		return require('snacks.picker.source.proc').proc(_opts, ctx)
	end
	opts = vim.tbl_deep_extend('force', Config.get(), {
		cwd = cwd,
		finder = finder,
	}, opts or {})

	-- Configure the picker to use the actions and keys from options or defaults
	return require('snacks').picker(opts)
end

---@param opts SnacksFileBrowser.Config
function M.save_buffer_as(opts)
	local bufnr = vim.api.nvim_get_current_buf()
	opts = vim.tbl_deep_extend('force', opts or {}, {
		---@param picker SnacksFileBrowser
		---@param items SnacksFileBrowser.Item[]
		on_confirm = function(picker, items)
			picker:close()
			save_as(bufnr, items)
		end
	})
	M.open(opts)
end

---@param opts SnacksFileBrowser.Config
function M.save_buffer(opts)
	if vim.bo.buftype == "nofile" or vim.bo.buftype == "nowrite" then
		Snacks.notify("Cannot save this buffer", vim.log.levels.WARN)
		return
	end
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		local bufnr = vim.api.nvim_get_current_buf()
		opts = vim.tbl_deep_extend('force', opts or {}, {
			---@param picker SnacksFileBrowser
			---@param items SnacksFileBrowser.Item[]
			on_confirm = function(picker, items)
				picker:close()
				save_as(bufnr, items)
			end
		})
		M.open(opts)
	else
		-- buffer has a name but the parent directory
		-- may not exist since buffers can be renamed arbitrarily
		-- so we need ++p to create parent directories
		vim.cmd("silent w! ++p")
	end
end

---Needs to be called before using the file browser
---@param config SnacksFileBrowser.Config
function M.setup(config)
	Config.set(config or {})
	vim.api.nvim_create_user_command(
		'SnacksFileBrowser',
		function(command_opts)
			local opts = parse_command_opts(command_opts)
			if not opts then return end
			M.open(opts)
		end,
		{
			nargs = '*',
			desc = "Open file browser",
		}
	)
	vim.api.nvim_create_user_command(
		'SnacksFileBrowserSave',
		function(command_opts)
			local opts = parse_command_opts(command_opts)
			if not opts then return end
			M.save_buffer(opts)
		end,
		{
			nargs = '*',
			desc = "Save current buffer...",
		}
	)
	vim.api.nvim_create_user_command(
		'SnacksFileBrowserSaveAs',
		function(command_opts)
			local opts = parse_command_opts(command_opts)
			if not opts then return end
			M.save_buffer_as(opts)
		end,
		{
			nargs = '*',
			desc = "Save current buffer as...",
		}
	)
end

return M
