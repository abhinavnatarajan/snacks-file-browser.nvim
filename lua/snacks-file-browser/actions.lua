local Snacks = require('snacks')
local Utils = require('snacks-file-browser.utils')
local uv = vim.uv
local M = {
	actions = {}
}

--- Set the picker current working directory (cwd) and reload the picker.
--- This function is used to set the new working directory and refresh the picker.
---@param picker SnacksFileBrowser
---@param new_cwd string
local function set_picker_cwd(picker, new_cwd)
	local resolved_cwd = vim.fs.normalize(new_cwd)
	if resolved_cwd and resolved_cwd ~= picker:cwd() then
		picker:set_cwd(resolved_cwd)
		Utils.update_title(picker, new_cwd)
		picker.input:set("", "")
	end
	picker:action("refresh")
end

---@param picker SnacksFileBrowser
---@param item snacks.picker.Item
---@param opts table | nil
---@return snacks.picker.Item[] | string[] | nil
local function resolve_selection(picker, item, opts)
	opts = vim.tbl_extend('force', { needs_match = false, paths_only = true }, opts or {})
	local selected = picker:selected({ fallback = false })
	if #selected == 0 then
		if not item or (item.score == 0 and opts.needs_match) then
			Snacks.notify.error("No items selected.")
			return
		end
		selected = { item }
	end
	if opts.paths_only then
		---@type string[]
		local paths = vim.iter(selected)
			:map(function(it) return it.file end)
			:totable()
		return paths
	end
	return selected
end


M.actions.edit_selected = {
	name = "edit_selected",
	desc = "Edit selected",
	---@param picker SnacksFileBrowser
	---@param item snacks.picker.Item
	action = function(picker, item)
		local selected_paths = resolve_selection(picker, item)
		if not selected_paths then return end
		Utils.edit_paths(picker, selected_paths)
	end
}

M.actions.cd_parent = {
	name = "cd_parent",
	desc = "Navigate to parent",
	---@param picker SnacksFileBrowser
	action = function(picker)
		local cwd = picker:cwd()
		local parent = vim.fs.dirname(cwd)
		set_picker_cwd(picker, parent)
	end
}

M.actions.smart_cd_parent = {
	name = "smart_cd_parent",
	desc = "Backspace or navigate to parent",
	---Either remove a character from the input or navigate up one directory
	---@param picker SnacksFileBrowser
	action = function(picker)
		if picker.input:get() == '' then
			picker:action("cd_parent")
		else
			vim.api.nvim_feedkeys(vim.keycode("<bs>"), "tn",
				false)
		end
	end
}

M.actions.refresh = {
	name = "refresh",
	desc = "Rerun the finder",
	---@param picker SnacksFileBrowser
	action = function(picker)
		picker:refresh()
	end
}

M.actions.multi_confirm = {
	name = "multi_confirm",
	desc = "Confirm selected files",
	---@param picker SnacksFileBrowser
	action = function(picker, item)
		local callback = picker.opts.on_confirm
		local selected_items = resolve_selection(picker, item)
		if not selected_items then return end
		callback(picker, selected_items)
	end
}

M.actions.sync_cwd = {
	name = "sync_cwd",
	desc = "Sync the cwd b/w neovim and the picker",
	---@param picker SnacksFileBrowser
	action = function(picker)
		vim.cmd("tcd " .. vim.fn.fnameescape(picker:cwd()))
	end
}

M.actions.open_system = {
	name = "open_system",
	desc = "Open selected items in system",
	---@param picker SnacksFileBrowser
	action = function(picker, item)
		local selected_paths = resolve_selection(picker, item)
		if not selected_paths then return end
		local errors = vim.iter(selected_paths):map(function(path)
			local systemobj, err = vim.ui.open(path)
			if not systemobj then
				return err
			else
				return nil
			end
		end):filter(function(it)
			return it ~= nil
		end):totable()
		if #errors > 0 then
			local errmsgs = vim.iter(errors):join("\n")
			Snacks.notify.error("Errors while opening items: " .. errmsgs)
			return
		end
		Snacks.notify.info("Opened " .. tostring(#selected_paths - #errors) .. " items")
	end
}

M.actions.confirm = {
	name = "confirm",
	desc = "Confirm selection",
	---@param picker SnacksFileBrowser
	---@param item snacks.picker.Item
	action = function(picker, item)
		local callback = picker.opts.on_confirm

		-- No items selected, so we create an item.
		-- Case 1: No items in the list or the items do not match the input.
		if not item or item.score == 0 then
			local input = picker.input:get()
			if input == "" then return end
			local new_path = vim.fs.joinpath(picker:cwd(), input)
			-- If the path is a directory we create it and navigate into it.
			local os_pathsep = package.config:sub(1, 1)
			if new_path:sub(-1):find(os_pathsep) then
				Utils.mkdir_async(new_path, nil, function(err)
					if err then
						Snacks.notify.error("Could not create directory " .. new_path)
						return
					end
					Snacks.notify.info("Created directory: " .. new_path)
					set_picker_cwd(picker, new_path)
				end)
			else
				callback(picker, { new_path })
			end
			return
		end

		-- Case 2: A valid item is in in the list
		local path = item.file ---@type string
		uv.fs_stat(path, vim.schedule_wrap(function(err, stat)
			if err then
				Snacks.notify.error("Could not stat file: " .. err)
				return
			end
			if stat.type == 'directory' then
				set_picker_cwd(picker, path)
			elseif stat.type == "file" then
				callback(picker, { path })
			end
		end))
	end
}
---Pass the highlighted or matched item to a callback function.

M.actions.rename = {
	name = "rename",
	desc = "Rename highlighted item",
	---@param picker SnacksFileBrowser
	---@param item snacks.picker.Item
	action = function(picker, item)
		if not item then return end
		local notify_lsp_clients = picker.opts.notify_lsp_clients_on_rename
		local old_file_name = item.text
		local old_path = vim.fs.normalize(item.file)

		local function rename_callback(new_name)
			if not new_name or new_name == "" then
				return
			end
			local new_path = vim.fs.abspath(vim.fs.normalize(vim.fs.joinpath(picker:cwd(), new_name)))
			local _, err, _ = Utils.rename_path(old_path, new_path, notify_lsp_clients)
			vim.schedule(function()
				if err then
					Snacks.notify.error("Rename failed: " .. err)
					return
				end
				Snacks.notify.info("Renamed " .. old_file_name .. " to " .. new_name)
				picker:action("refresh")
			end)
		end
		vim.ui.input({ prompt = "Enter new name: ", default = old_file_name }, rename_callback)
	end
}

M.actions.create_new = {
	name = "create_new",
	desc = "Create new file/directory from input",
	---@param picker SnacksFileBrowser
	action = function(picker)
		local function create_new(new_path)
			if not picker or picker.closed then return end

			-- If the path is a directory we create it and navigate into it.
			local dir = ""
			if new_path:sub(-1) == package.config:sub(1, 1) then
				if vim.fn.isdirectory(new_path) == 1 then
					Snacks.notify.info("Directory already exists")
					return
				end
				Utils.mkdir(new_path, nil, function(err)
					if err then
						Snacks.notify.error("Could not create " .. new_path .. "\n" .. err)
						return
					end
					set_picker_cwd(picker, new_path)
					Snacks.notify.info("Created directory: " .. new_path)
				end)
			else
				if vim.fn.filereadable(new_path) == 1 then
					Snacks.notify.info("Item already exists")
					return
				end
				-- Create the file.
				dir = vim.fs.dirname(new_path)
				local create_file_result, error = Utils.create_file(new_path)
				if not create_file_result then
					Snacks.notify(("Could not create file due to %s"):format(error))
					return
				end
				set_picker_cwd(picker, dir)
			end
		end
		local cwd = picker:cwd()
		local picker_input = picker.input:get()
		if picker_input == "" then
			vim.ui.input(
				{ prompt = "Enter name for new file or directory: " },
				function(ui_input)
					if not ui_input then
						return
					end
					create_new(vim.fs.joinpath(cwd, ui_input))
				end
			)
		else
			create_new(vim.fs.joinpath(cwd, picker_input))
		end
	end
}

M.actions.yank_paths = {
	name = "yank_paths",
	desc = "Yank paths of selected items",
	---@param picker SnacksFileBrowser
	---@param item snacks.picker.Item
	action = function(picker, item)
		local selected_paths = resolve_selection(picker, item)
		if not selected_paths then return end
		local value = table.concat(selected_paths, "\n")
		vim.fn.setreg(vim.v.register or "+", value, "l")
		local msg = tostring(#selected_paths) .. " path" .. (#selected_paths > 1 and "s" or "")
		Snacks.notify.info("Copied " .. msg)
	end
}

M.actions.yank_to_clipboard = {
	name = "yank_to_clipboard",
	desc = "Yank selected items to system clipboard",
	---@param picker SnacksFileBrowser
	---@param item snacks.picker.Item
	action = function(picker, item)
		local selected_paths = resolve_selection(picker, item)
		if not selected_paths then return end
		-- TODO: needs windows and macos equivalents
		local uri_list = vim.iter(selected_paths):map(vim.uri_from_fname):join('\n')
		local cmd = { 'wl-copy', '-t', 'text/uri-list', uri_list }
		vim.system(cmd, { stderr = false }):wait()
		Snacks.notify.info("Yanked " .. tostring(#selected_paths) .. " items to clipboard")
	end
}

M.actions.paste_from_clipboard = {
	name = "paste_from_clipboard",
	desc = "Paste files from system clipboard",
	action = function(picker)
		-- Get list of items to paste separated by '\r\n'
		local job = vim.system({ 'wl-paste', '-t', 'text/uri-list', '-n' }, { text = true }):wait()
		local stderr, stdout = job.stderr, job.stdout
		if not stdout or (stdout == "" and #stderr > 0) then
			Snacks.notify.error("No files in clipboard")
			return
		end
		local uris = vim.split(stdout, '\n', { trimempty = true })
		local paths = vim.iter(uris):map(vim.uri_to_fname):totable()
		Utils.copy_paths(paths, picker:cwd(), function(success, errors)
			if not success then
				Snacks.notify.error("Error while copying items:\n" .. table.concat(errors, "\n"))
			end
			local copied_count = #paths - (errors and #errors or 0)
			if copied_count > 0 then
				Snacks.notify.info("Copied " .. copied_count .. " items")
			end
			picker.list:set_selected()
			picker:action("refresh")
		end)
	end
}

M.actions.copy = {
	name = "copy",
	desc = "Copy selected items",
	---@param picker SnacksFileBrowser
	action = function(picker)
		---@type string[]
		local files = vim.iter(picker:selected({ fallback = false }))
			:map(function(item) return item.file end)
			:totable()
		local dir = picker:cwd()
		Utils.copy_paths(files, dir, function(success, errors)
			if not success then
				Snacks.notify.error("Error while copying items:\n" .. table.concat(errors, "\n"))
			end
			local copied_count = #files - (errors and #errors or 0)
			if copied_count > 0 then
				Snacks.notify.info("Copied " .. copied_count .. " items")
			end
			picker.list:set_selected()
			picker:action("refresh")
		end)
	end
}

M.actions.move = {
	name = "move",
	desc = "Move selected items here",
	---@param picker SnacksFileBrowser
	action = function(picker)
		local files = vim.iter(picker:selected({ fallback = false }))
			:map(function(item) return item.file end)
			:totable()
		local dir = picker:cwd()
		Utils.move_paths(files, dir, {
			notify_lsp_clients = picker.opts.notify_lsp_clients_on_rename or false,
			callback = function(success, err)
				if not success then
					Snacks.notify.error("Error while moving items: \n" .. table.concat(err, "\n"))
					return
				end
				-- Might have some items moved even if there were errors
				Snacks.notify.info("Moved " .. #files - (err and #err or 0) .. " items")
				picker.list:set_selected()
				picker:action("refresh")
			end
		})
	end
}

M.actions.delete = {
	name = "delete",
	desc = "Delete selected items",
	---@param picker SnacksFileBrowser
	action = function(picker, item)
		local selected_items = resolve_selection(picker, item, { paths_only = false })
		if not selected_items then return end
		---@cast selected_items snacks.picker.Item[]
		local message = #selected_items == 1 and selected_items[1].file or #selected_items .. " items"
		local insert_mode = vim.fn.mode() == "i"
		local _, col = unpack(vim.api.nvim_win_get_cursor(picker.input.win.win))
		local is_end_of_line = col >= #picker.input:get()
		vim.ui.select(
			{ 'Yes', 'No' },
			{ prompt = "Delete " .. message .. "?" },
			function(confirm)
				if not confirm then return end
				local num_deleted = 0
				vim.iter(selected_items):each(
					function(it)
						local path = it.file
						local ok, err = pcall(vim.fs.rm, path, { recursive = true })
						if ok then
							Snacks.bufdelete({ file = path, force = true, wipe = true })
							num_deleted = num_deleted + 1
							picker.list:unselect(item)
						else
							Snacks.notify.error("Delete failed: " .. err)
						end
					end)
				Snacks.notify.info("Deleted " .. num_deleted .. " items")
				picker:action("refresh") -- Refresh the picker
				if insert_mode then
					if is_end_of_line then
						vim.cmd("startinsert!")
					else
						vim.cmd("startinsert")
					end
				end
			end
		)
	end
}

return M
