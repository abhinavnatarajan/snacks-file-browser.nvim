local Snacks = require('snacks')
local Utils = require('snacks-file-browser.utils')
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
	local resolved_cwd = vim.fs.normalize(new_cwd)
	if resolved_cwd and resolved_cwd ~= picker:cwd() then
		picker:set_cwd(resolved_cwd)
		update_title(picker, new_cwd)
		picker.input:set("", "")
	end
	picker:find()
end

---Navigate up one directory
function M.navigate_parent(picker)
	local cwd = picker:cwd()
	local parent = vim.fs.dirname(cwd)
	set_picker_cwd(picker, parent)
end

---Either remove a character from the input or navigate up one directory
function M.backspace(picker)
	if picker.input:get() == '' then
		M.navigate_parent(picker)
	else
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<bs>", true, false, true), "tn",
			false)
	end
end

---Rerun the finder
function M.refresh(picker)
	picker:find()
end

local function edit_path(p)
	local cb = function()
		if vim.fn.filereadable(p) then
			vim.cmd.edit(p)
		end
	end
	if vim.in_fast_event() then
		cb = vim.schedule_wrap(cb)
	end
	cb()
end

local function edit_paths(paths)
	local readable_files = vim.iter(paths)
		:filter(function(path)
			return vim.fn.filereadable(path) == 1
		end)
		:totable()
	vim.iter(readable_files):map(function(path) edit_path(path) end)
	return true
end

local function edit_paths_cb(picker, paths)
	picker:close()
	edit_paths(paths)
end

---Edit the selected file(s)
function M.edit(picker)
	local selected = picker:selected({ fallback = true })
	if #selected > 0 then
		local paths = vim.iter(selected):map(function(t) return t.file end):totable()
		edit_paths_cb(picker, paths)
		return
	else
		Snacks.notify.error("No files selected to edit")
	end
end

---Set the cwd of neovim from the picker
function M.set_cwd(picker)
	vim.cmd("tcd " .. vim.fn.fnameescape(picker:cwd()))
end

function M.confirm(picker, item)
	local cb = picker.opts.on_confirm or edit_paths_cb
	local selected = picker:selected({ fallback = false })

	-- If items are selected
	if #selected > 0 then
		local item_paths = vim.iter(selected):map(function(t) return t.file end):totable()
		cb(picker, item_paths)
		return
	end

	-- No items selected, so we create an item
	-- Case 1: No items in the list or the items do not match the input
	if not item or item.score == 0 then
		local new_path = vim.fs.joinpath(picker:cwd(), picker.input:get())
		-- if the path is a directory we create it and navigate into it
		local os_pathsep = package.config:sub(1, 1)
		if new_path:sub(-1):find(os_pathsep) then
			Utils.mkdir(new_path, nil, function(err)
				if err then
					Snacks.notify.error("Could not create directory " .. new_path)
					return
				end
				Snacks.notify.info("Created directory: " .. new_path)
				set_picker_cwd(picker, new_path)
			end)
		else
			cb(picker, { new_path })
		end
		return
	end

	-- Case 2: A valid item is in in the list
	local path = item.file
	uv.fs_stat(path, vim.schedule_wrap(function(err, stat)
		if err then
			Snacks.notify.error("Could not stat file: " .. err)
			return
		end
		if stat.type == 'directory' then
			set_picker_cwd(picker, path)
		elseif stat.type == "file" then
			cb(picker, { path })
		end
	end))
end

---Rename the currently selected file or directory
function M.rename(picker, selected)
	if not selected then return end
	local notify_lsp_clients = picker.opts.rename.notify_lsp_clients
	local old_file_name = selected.text
	local old_path = vim.fs.normalize(selected.file)

	local function rename_callback(new_name)
		local new_path = vim.fs.abspath(vim.fs.normalize(vim.fs.joinpath(picker:cwd(), new_name)))
		Utils.rename_path(old_path, new_path,
			notify_lsp_clients,
			vim.schedule_wrap(function(err)
				if err then
					Snacks.notify.error("Rename failed: " .. err)
					return
				end
				Snacks.notify.info("Renamed " .. old_file_name .. " to " .. new_name)
				picker:find()
			end)
		)
	end
	vim.ui.input({ prompt = "Enter new name: " }, rename_callback)
end

---Create a new file or directory based on the input in the picker
function M.create_new(picker)
	local new_path = vim.fs.joinpath(picker:cwd(), picker.input:get())

	if vim.fn.filereadable(new_path) == 1 then
		Snacks.notify.info("Item already exists")
		return
	end

	-- if the path is a directory we create it and navigate into it
	local dir = ""
	if new_path:sub(-1) == "/" then
		if vim.fn.isdirectory(new_path) == 0 then
			Utils.mkdir(new_path, nil, function(err)
				if err then
					Snacks.notify.error("Could not create " .. new_path .. "\n" .. err)
					return
				end
				set_picker_cwd(picker, new_path)
				Snacks.notify.info("Created directory: " .. new_path)
			end)
		end
	else
		-- Create the file asynchronously
		dir = vim.fs.dirname(new_path)
		Utils.create_file(new_path, function(err)
			if err then
				Snacks.notify(err)
				return
			end
			set_picker_cwd(picker, dir)
		end)
	end
end

function M.yank(picker)
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
	Snacks.notify.info("Yanked " .. message)
end

function M.copy(picker)
	local files = {} ---@type string[]
	for _, item in ipairs(picker:selected({ fallback = false })) do
		table.insert(files, item.file)
	end
	local dir = picker:cwd()
	Utils.copy_paths(files, dir, function(errors)
		if errors then
			Snacks.notify.error("Error while copying items:\n" .. table.concat(errors, "\n"))
		end
		local copied_count = #files - (errors and #errors or 0)
		if copied_count > 0 then
			Snacks.notify.info("Copied " .. copied_count .. " items")
		end
		picker.list:set_selected()
		picker:find()
	end)
end

function M.move(picker)
	local files = {} ---@type string[]
	for _, item in ipairs(picker:selected({ fallback = false })) do
		table.insert(files, item.file)
	end
	local dir = picker:cwd()
	Utils.move_paths(files, dir, {
		notify_lsp_clients = picker.opts.rename.notify_lsp_clients or false,
		callback = function(err)
			if err then
				Snacks.notify.error("Error while moving items: \n" .. table.concat(err, "\n"))
				return
			end
			-- might have some items moved even if there were errors
			Snacks.notify.info("Moved " .. #files - (err and #err or 0) .. " items")
			picker.list:set_selected()
			picker:find()
		end
	})
end

function M.delete(picker)
	if vim.fn.mode():find("^[vV]") then
		picker.list:select() -- add the visual selection to the list of selected items
	end
	local sel = picker:selected({ fallback = true })
	if #sel == 0 then return end
	local message = #sel == 1 and vim.fs.joinpath(sel.file) or #sel .. " items"
	local win = vim.api.nvim_get_current_win()
	local insert_mode = vim.fn.mode() == "i"
	local row, col = unpack(vim.api.nvim_win_get_cursor(picker.input.win.win))
	vim.ui.select(
		{ 'Yes', 'No' },
		{ prompt = "Delete " .. message .. "?" },
		function(confirm)
			if not confirm then return end
			local num_deleted = 0
			vim.iter(sel):each(
				function(item)
					local file = item.file
					local ok, err = pcall(vim.fs.rm, file, { recursive = true })
					if ok then
						Snacks.bufdelete({ file = file, force = true, wipe = true })
						num_deleted = num_deleted + 1
						picker.list:unselect(item)
					else
						Snacks.notify.error("Delete failed: " .. err)
					end
				end)
			Snacks.notify.info("Deleted " .. num_deleted .. " items")
			picker:find() -- Refresh the picker
			vim.api.nvim_win_set_cursor(win, { row, col })
			if insert_mode then
				vim.cmd("startinsert")
			end
		end)
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
