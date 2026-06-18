local Snacks = require('snacks')
local Utils = require('snacks-file-browser.utils')
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
	picker:find()
end

---@param picker SnacksFileBrowser
---@param item snacks.picker.Item | nil
---@param opts { fallback: "none"|"highlighted"|"matched", output: "items"|"paths", notify: boolean }
---@return SnacksFileBrowser.Item[] | string[] | nil
local function resolve_selection(picker, item, opts)
	if type(opts) ~= "table" then
		error("resolve_selection requires explicit options", 2)
	end
	if opts.fallback ~= "none" and opts.fallback ~= "highlighted" and opts.fallback ~= "matched" then
		error("resolve_selection requires fallback to be 'none', 'highlighted', or 'matched'", 2)
	end
	if opts.output ~= "items" and opts.output ~= "paths" then
		error("resolve_selection requires output to be 'items' or 'paths'", 2)
	end
	if type(opts.notify) ~= "boolean" then
		error("resolve_selection requires notify to be a boolean", 2)
	end

	local selected = picker:selected({ fallback = false })
	if #selected == 0 then
		if opts.fallback == "none" then
			if opts.notify then Snacks.notify.error("No items selected.") end
			return
		end
		if not item then
			if opts.notify then Snacks.notify.error("No items selected.") end
			return
		end
		if opts.fallback == "matched" and item.score == 0 then
			if opts.notify then Snacks.notify.error("No matching item.") end
			return
		end
		selected = { item }
	end
	if opts.output == "paths" then
		---@type string[]
		local paths = vim.iter(selected)
			:map(function(it) return it.file end)
			:totable()
		return paths
	end
	return selected
end

local function notify_system_failure(command, job)
	if (job.code or 0) ~= 0 then
		Snacks.notify.error(command .. " failed with exit code " .. tostring(job.code))
		return true
	end
	if (job.signal or 0) ~= 0 then
		Snacks.notify.error(command .. " stopped by signal " .. tostring(job.signal))
		return true
	end
	return false
end


M.actions.edit_selected = {
	name = "edit_selected",
	desc = "Edit selected",
	---@param picker SnacksFileBrowser
	---@param item SnacksFileBrowser.Item
	action = function(picker, item)
		local selected_paths = resolve_selection(picker, item, {
			fallback = "highlighted",
			output = "paths",
			notify = true,
		})
		if not selected_paths then return end
		picker:norm(function()
			picker:close()
		end)
		Utils.edit_paths(selected_paths)
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
	desc = "Confirm selected items",
	---@param picker SnacksFileBrowser
	action = function(picker, item)
		local callback = picker.opts.on_confirm
		local selected_items = resolve_selection(picker, item, {
			fallback = "highlighted",
			output = "items",
			notify = true,
		})
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
		local selected_paths = resolve_selection(picker, item, {
			fallback = "highlighted",
			output = "paths",
			notify = true,
		})
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

M.actions.accept = {
	name = "accept",
	desc = "Accept input or highlighted item",
	---@param picker SnacksFileBrowser
	---@param item SnacksFileBrowser.Item
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
				callback(picker, { { idx = -1, score = 0, file = new_path, text = input } })
			end
			return
		end

		-- Case 2: A valid item is in in the list
		if item.dir then
			set_picker_cwd(picker, item.file)
		else
			callback(picker, { item })
		end
	end
}

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
				Utils.mkdir_async(new_path, nil, function(err)
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
		local selected_paths = resolve_selection(picker, item, {
			fallback = "highlighted",
			output = "paths",
			notify = true,
		})
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
		local selected_paths = resolve_selection(picker, item, {
			fallback = "highlighted",
			output = "paths",
			notify = true,
		})
		if not selected_paths then return end
		-- TODO: needs windows and macos equivalents
		local uri_list = vim.iter(selected_paths):map(vim.uri_from_fname):join('\n')
		local cmd = { 'wl-copy', '-t', 'text/uri-list', uri_list }
		local job = vim.system(cmd, { stderr = false }):wait()
		if notify_system_failure('wl-copy', job) then return end
		Snacks.notify.info("Yanked " .. tostring(#selected_paths) .. " items to clipboard")
	end
}

M.actions.paste_from_clipboard = {
	name = "paste_from_clipboard",
	desc = "Paste files from system clipboard",
	action = function(picker)
		-- Get list of items to paste separated by '\r\n'
		local job = vim.system({ 'wl-paste', '-t', 'text/uri-list', '-n' }, { text = true }):wait()
		if notify_system_failure('wl-paste', job) then return end
		local stdout = job.stdout
		if not stdout or stdout == "" then
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
	action = function(picker, item)
		local files = resolve_selection(picker, item, {
			fallback = "none",
			output = "paths",
			notify = true,
		})
		if not files then return end
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
	action = function(picker, item)
		local files = resolve_selection(picker, item, {
			fallback = "none",
			output = "paths",
			notify = true,
		})
		if not files then return end
		local dir = picker:cwd()
		Utils.move_paths(files, dir, {
			notify_lsp_clients = picker.opts.notify_lsp_clients_on_rename or false
		}, function(success, errors)
			if not success then
				Snacks.notify.error("Error while moving items:\n" .. table.concat(errors, "\n"))
			end
			local moved_count = #files - (errors and #errors or 0)
			if moved_count > 0 then
				Snacks.notify.info("Moved " .. moved_count .. " items")
			end
			picker.list:set_selected()
			picker:action("refresh")
		end)
	end
}

M.actions.delete = {
	name = "delete",
	desc = "Delete selected items",
	---@param picker SnacksFileBrowser
	action = function(picker, item)
		local selected_items = resolve_selection(picker, item, {
			fallback = "highlighted",
			output = "items",
			notify = true,
		})
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
