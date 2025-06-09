local Snacks = require('snacks')
local Path = require('plenary.path')
local uv = vim.uv
local M = {}

---Update the title of the picker, truncating if required
local function update_title(picker, title)
	local len = picker.input.win:size().width - 4
	picker.title = title:len() > len and "…" .. title:sub(-len + 1) or title
	picker:update_titles()
end

--- Set the picker current working directory (cwd) and reload the picker
--- This function is used to set the new working directory and refresh the picker.
---@param picker any
---@param new_cwd string
local function set_picker_cwd(picker, new_cwd)
	local resolved_cwd = uv.fs_realpath(new_cwd)
	if resolved_cwd and resolved_cwd ~= picker:cwd() then
		picker:set_cwd(resolved_cwd)
		update_title(picker, new_cwd)
		picker.input:set("", "")
	end
	picker:find()
end

-- Navigate up one directory
function M.navigate_parent(picker)
	local cwd = picker:cwd()
	local parent = vim.fs.dirname(cwd)
	set_picker_cwd(picker, parent)
end

-- Either remove a character from the input or navigate up one directory
function M.backspace(picker)
	if picker.input:get() == '' then
		M.navigate_parent(picker)
	else
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<bs>", true, false, true), "tn",
			false)
	end
end

---@return boolean|nil, string|nil
local function dir_iswriteable(dir)
	local stat = uv.fs_stat(dir)
	if not stat then
		Snacks.notify.error("Could not stat destination directory: " .. dir)
	elseif stat.type ~= "directory" then
		Snacks.notify.error("Destination is not a directory: " .. dir)
	elseif not uv.fs_access(dir, "w") then
		Snacks.notify.error("Destination is not writable: " .. dir)
	else
		return true
	end
end

---Move a file or directory to a new location
---@param paths string[]  -- List of absolute file paths to move
---@param dir string  -- Destination directory
local function move_paths(paths, dir)
	paths = vim.iter(paths):filter(function(path)
		return path ~= "" and uv.fs_stat(path)
	end):totable()
	if not dir_iswriteable(dir) then return end
	local count = 0
	vim.iter(paths):each(
		function(path)
			local old_path = uv.fs_realpath(path)
			local new_path = vim.fs.joinpath(dir, vim.fs.basename(path))
			-- TODO: account for directories, snacks can't rename directories
			Snacks.rename.rename_file({
				from = old_path,
				to = new_path,
				on_rename = function()
					count = count + 1
				end
			})
		end)
	return count
end

---Copy a file or directory to a new location
---@param path string  -- Absolute file path to copy
---@param dir string  -- Destination directory
---@return table
local function copy_path(path, dir)
	-- Normalize the path so that trailing slashes are removed
	if not uv.fs_access(path, "r") then
		return { [path] = { ok = false, err = "Not readable" } }
	end
	local stat, err = uv.fs_stat(path)
	if not stat then
		return { [path] = { ok = false, err = err } }
	end
	path = uv.fs_realpath(path) or path
	if stat.type == "file" then
		local destination = vim.fs.joinpath(dir, vim.fs.basename(path))
		local ok, err = uv.fs_copyfile(path, destination,
			{ excl = false, ficlone = true, ficlone_force = false })
		return { [path] = { ok = ok, err = err } }
	end
	if stat.type == "directory" then
		local new_dir = vim.fs.joinpath(dir, vim.fs.basename(path))
		local ok = vim.fn.mkdir(new_dir, "p")
		if ok == 0 then
			return { [path] = { ok = false, err = "Could not create directory in destination" } }
		end
		return vim.iter(vim.fs.dir(path, { follow = false })):map(
			function(name)
				local child_path = vim.fs.joinpath(path, name)
				return copy_path(child_path, new_dir)
			end
		):fold({}, function(acc, t)
			return vim.tbl_extend('force', acc, t)
		end)
	end
	return { [path] = { ok = false, err = "Not a file or directory" } }
end

---Copy a list of files or paths to a new location
---@param paths string[]  -- List of file paths to copy
---@param dir string  -- Destination directory
---@return (table|nil), (nil|string)
local function copy_paths(paths, dir)
	local ok, err = dir_iswriteable(dir)
	if not ok then return nil, err end
	return vim.iter(paths):map(
			function(path)
				return copy_path(path, dir)
			end)
		:fold({}, function(acc, t)
			return vim.tbl_extend('force', acc, t)
		end)
end

local function edit_path(p)
	local cb = function()
		vim.cmd.edit(p)
	end
	if vim.in_fast_event() then
		cb = vim.schedule_wrap(cb)
	end
	cb()
end

local function edit_paths(p)
	if type(p) == "string" then
		M.edit_path(p)
	elseif type(p) == "table" then
		for _, path in ipairs(p) do
			edit_path(path)
		end
	end
	return true
end

function M.edit(picker)
	local selected = picker:selected({ fallback = true })
	if #selected > 0 then
		local readable_files = vim.iter(selected)
			:map(function(item) return item.file end)
			:filter(function(path)
				return vim.fn.filereadable(path) == 1
			end)
			:totable()
		picker:close()
		edit_paths(readable_files)
		return
	end
end

function M.confirm(picker, item)
	local snacks = require('snacks')
	local callback = picker.opts.on_confirm or function(path, _picker)
		_picker:close()
		edit_path(path)
	end
	-- Case 1: No items are tab-selected and no valid item is in the list
	if not item or item.score == 0 then
		local new_path = vim.fs.joinpath(picker:cwd(), picker.input:get())
		-- if the path is a directory we create it and navigate into it
		local os_pathsep = package.config:sub(1, 1)
		if new_path:sub(-1):find(os_pathsep) then
			if vim.fn.mkdir(new_path, "p") == 0 then
				snacks.notify.error("Could not create directory " .. new_path)
				return
			end
			snacks.notify.info("Created directory: " .. new_path)
			set_picker_cwd(picker, new_path)
		else
			callback(new_path, picker)
		end
		return
	end

	-- Case 2: A valid item is in in the list
	local file = item.file
	local stat = uv.fs_stat(file)
	if stat and stat.type == 'directory' then
		set_picker_cwd(picker, file)
	elseif vim.fn.filereadable(file) == 1 then
		callback(file, picker)
	end
end

function M.set_cwd(picker)
	vim.cmd("tcd " .. vim.fn.fnameescape(picker:cwd()))
end

function M.yank(picker)
	local snacks = require('snacks')
	local files = {} ---@type string[]
	if vim.fn.mode():find("^[vV]") then
		picker.list:select() -- add the visual selection to the list of selected items
	end
	for _, item in ipairs(picker:selected({ fallback = true })) do
		table.insert(files, item.file)
	end
	local value = table.concat(files, "\n")
	vim.fn.setreg(vim.v.register or "+", value, "l")
	local message = #files == 1 and files[1] or #files .. " items"
	snacks.notify.info("Yanked " .. message)
end

function M.copy(picker)
	local snacks = require('snacks')
	local files = {} ---@type string[]
	for _, item in ipairs(picker:selected({ fallback = false })) do
		table.insert(files, item.file)
	end
	local dir = picker:cwd()
	vim.schedule(function()
		local result, err = copy_paths(files, dir)
		if not result then
			snacks.notify.info(err)
			return
		end
		local errors = {}
		local pasted = vim.iter(result):fold(0,
			function(acc, path, res)
				if res.ok then
					acc = acc + 1
				else
					vim.tbl_insert(errors, path .. ": " .. res.err)
				end
				return acc
			end)
		snacks.notify.info("Copied " .. #files .. " items (total " .. pasted .. " files)")
		if #errors > 0 then
			snacks.notify.error("Error while copying items:\n" .. table.concat(result, "\n"))
		end
		picker.list:set_selected()
		picker:find()
	end)
end

function M.move(picker)
	local snacks = require('snacks')
	local files = {} ---@type string[]
	for _, item in ipairs(picker:selected({ fallback = false })) do
		table.insert(files, item.file)
	end
	local dir = picker:cwd()
	vim.schedule(function()
		local moved = move_paths(files, dir)
		if not moved then
			snacks.notify.error("Error while moving items: " .. vim.inspect(errs))
			return
		end
		snacks.notify.info("Moved " .. moved .. " items")
		picker.list:set_selected()
		picker:find()
	end)
end

function M.delete(picker)
	local snacks = require('snacks')
	if vim.fn.mode():find("^[vV]") then
		picker.list:select() -- add the visual selection to the list of selected items
	end
	local sel = picker:selected({ fallback = true })
	if #sel == 0 then return end
	local message = #sel == 1 and vim.fs.joinpath(sel.file) or #sel .. " files"
	local focus_input = vim.api.nvim_get_current_win() == picker.input.win.win
	local insert_mode = vim.fn.mode() == "i"
	vim.ui.select(
		{ 'Yes', 'No' },
		{ prompt = "Delete " .. message .. "?" },
		function(confirm)
			if confirm == "No" then return end
			local num_deleted = 0
			vim.iter(sel):each(
				function(item)
					local file = item.file
					local ok, err = pcall(vim.fs.rm, file, { recursive = true })
					if ok then
						snacks.bufdelete({ file = file, force = true, wipe = true })
						num_deleted = num_deleted + 1
						picker.list:unselect(item)
					else
						snacks.notify.error("Delete failed: " .. err)
					end
				end)
			snacks.notify.info("Deleted " .. num_deleted .. " items")
			picker:find() -- Refresh the picker
			if focus_input then
				picker:focus("input")
			end
			if insert_mode then
				vim.cmd("startinsert")
			end
		end)
end

function M.rename(picker, selected)
	local snacks = require('snacks')
	if not selected then return end
	local old_path = uv.fs_realpath(selected.file)
	snacks.rename.rename_file({ from = old_path, on_rename = function() picker:find() end })
end

function M.refresh(picker)
	picker:find()
end

function M.create_new(picker)
	local snacks = require('snacks')
	local new_path = vim.fs.joinpath(picker:cwd(), picker.input:get())

	if vim.fn.filereadable(new_path) == 1 then
		snacks.notify.info("Item already exists")
		return
	end

	-- if the path is a directory we create it and navigate into it
	local dir = ""
	if new_path:sub(-1) == "/" then
		if vim.fn.isdirectory(new_path) == 0 then
			if vim.fn.mkdir(new_path, "p") == 0 then
				snacks.notify.error("Could not create " .. new_path)
				return
			end
			snacks.notify("Created directory: " .. new_path, { level = "info" })
		end
		dir = new_path
		return
	else
		dir = vim.fs.dirname(new_path)
		if vim.fn.mkdir(dir, "p") == 0 then
			snacks.notify.error("Could not create directory " .. new_path)
			return
		end
	end
	set_picker_cwd(picker, dir)
end

local ret = {
	actions = vim.iter(M)
		:fold({}, function(acc, k, v)
			acc[k] = { action = v }
			return acc
		end),
	update_title = update_title,
}


return ret
