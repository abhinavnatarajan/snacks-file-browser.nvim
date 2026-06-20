local M = {}
local Snacks = require('snacks')
local uv = vim.uv

---@param paths string[]
function M.edit_paths(paths)
	for _, fname in ipairs(paths) do
		vim.schedule(function()
			vim.cmd.edit(vim.fn.fnameescape(fname))
		end)
	end
end

local function system_errors(command, job)
	if (job.code or 0) ~= 0 then
		return { command .. " failed with exit code " .. tostring(job.code) }
	end
	if (job.signal or 0) ~= 0 then
		return { command .. " stopped by signal " .. tostring(job.signal) }
	end
end

local function file_uri_to_fname(uri)
	if not uri:match("^[Ff][Ii][Ll][Ee]:") then
		return nil, "Unsupported clipboard URI scheme: " .. uri
	end

	local rest = uri:sub(6)
	if not rest:match("^//") then
		local ok, path = pcall(vim.uri_to_fname, uri)
		if ok and path then
			return path
		end
		return nil, "Invalid clipboard URI: " .. uri
	end

	local authority, path = rest:match("^//([^/]*)(.*)$")
	authority = (authority or ""):lower()
	path = path or ""
	if authority == "" then
		if path:match("^//") then
			return nil, "Unsupported non-local clipboard URI: " .. uri
		end
		local ok, fname = pcall(vim.uri_to_fname, uri)
		if ok and fname then
			return fname
		end
		return nil, "Invalid clipboard URI: " .. uri
	end
	if authority == "localhost" then
		local ok, fname = pcall(vim.uri_to_fname, "file://" .. path)
		if ok and fname then
			return fname
		end
		return nil, "Invalid clipboard URI: " .. uri
	end
	return nil, "Unsupported non-local clipboard URI: " .. uri
end

---@param paths string[]
---@return boolean|nil, string[]|nil
function M.open_paths_system(paths)
	local errors = vim.iter(paths):map(function(path)
		local systemobj, err = vim.ui.open(path)
		if not systemobj then
			return err or ("Could not open " .. path)
		end
	end):filter(function(err)
		return err ~= nil
	end):totable()

	return #errors == 0 and true or nil, #errors > 0 and errors or nil
end

---@param paths string[]
---@return boolean|nil, string[]|nil
function M.yank_paths_to_clipboard(paths)
	if vim.fn.executable('wl-copy') ~= 1 then
		return nil, { "wl-copy is not installed" }
	end
	local uri_list = vim.iter(paths):map(vim.uri_from_fname):join('\r\n') .. '\r\n'
	local job = vim.system({ 'wl-copy', '-t', 'text/uri-list', uri_list }, { stderr = false }):wait()
	local errors = system_errors('wl-copy', job)
	if errors then
		return nil, errors
	end
	return true
end

---@return string[]|nil, string[]|nil
function M.get_clipboard_paths()
	local job = vim.system({ 'wl-paste', '-t', 'text/uri-list', '-n' }, { text = true }):wait()
	local errors = system_errors('wl-paste', job)
	if errors then
		return nil, errors
	end
	local stdout = job.stdout
	if not stdout or stdout == "" then
		return nil, { "No files in clipboard" }
	end
	local paths = {}
	errors = {}
	for _, uri in ipairs(vim.split(stdout, '\n', { trimempty = true })) do
		uri = uri:gsub('\r$', '')
		if uri:sub(1, 1) ~= '#' then
			local path, uri_error = file_uri_to_fname(uri)
			if path then
				table.insert(paths, path)
			else
				table.insert(errors, uri_error)
			end
		end
	end
	if #errors > 0 then
		return nil, errors
	end
	if #paths == 0 then
		return nil, { "No files in clipboard" }
	end
	return paths
end

---Update the title of the picker, truncating if required.
function M.update_title(picker, title)
	local len = picker.input.win:size().width - 4
	picker.title = title:len() > len and "…" .. title:sub(-len + 1) or title
	picker:update_titles()
end

---@param path string
---@return boolean|nil, string[]|nil
function M.mkdir_p(path)
	if vim.fn.isdirectory(path) == 1 then
		return true, nil
	end

	local stat = uv.fs_stat(path)
	if stat and stat.type ~= "directory" then
		return nil, { "Path exists and is not a directory: " .. path }
	end

	local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, path, "p")
	if not mkdir_ok then
		return nil, { tostring(mkdir_result) }
	end
	if mkdir_result ~= 1 or vim.fn.isdirectory(path) ~= 1 then
		return nil, { "Could not create directory: " .. path }
	end
	return true, nil
end

---@param path string
---@return boolean|nil, string[]|nil, boolean did_create
function M.create_directory(path)
	if vim.fn.isdirectory(path) == 1 then
		return true, nil, false
	end

	local ok, errors = M.mkdir_p(path)
	if not ok then
		return nil, errors, false
	end
	return true, nil, true
end

---@param path string  -- Absolute path to the directory to check
---@return boolean|nil, string|nil
local function is_writeable_dir(path)
	local stat, err_msg = uv.fs_stat(path)
	if not stat then
		return nil, err_msg
	elseif stat.type ~= "directory" then
		return false
	end
	local writeable
	writeable, err_msg = uv.fs_access(path, "w")
	if err_msg then
		return nil, err_msg
	elseif not writeable then
		return false
	end
	return true
end

---Create a file at the given path, creating intermediate directories as needed.
---@param file string  -- Absolute path to the file to create
---@return boolean|nil, string[]|nil, boolean did_create
function M.create_file(file)
	if vim.fn.filereadable(file) == 1 then
		return true, nil, false
	end

	-- Create the parent directory if necessary
	local dir = vim.fs.dirname(file)
	local mkdir_ok, mkdir_errors = M.mkdir_p(dir)
	if not mkdir_ok then
		return nil, mkdir_errors, false
	end
	local fd, error = uv.fs_open(file, "w", tonumber('644', 8))
	if not fd then
		return nil, { error }, false
	end
	_, error = uv.fs_close(fd)
	if error then
		return nil, { error }, false
	end
	return true, nil, true
end

---Rename a file or directory.
---Will update buffer names if the file (or any files contained in the directory)
---are open in buffers in Neovim.
---Will also emit appropriate lsp notifications to clients that support it
---@param from string  -- Absolute path of the file or directory to rename
---@param to string  -- Absolute path of the new name for the file or directory
---@param notify_lsp_clients boolean  -- Whether to notify LSP clients about the rename
---@return boolean|nil, string[]|nil
function M.rename_path(from, to, notify_lsp_clients)
	local lsp_changes = {
		files = { {
			oldUri = vim.uri_from_fname(from),
			newUri = vim.uri_from_fname(to),
		} }
	}
	local buf_renames = vim.iter(vim.api.nvim_list_bufs())
		:fold({}, function(acc, bufnr)
			local name = vim.api.nvim_buf_get_name(bufnr)
			if name == from then
				acc[bufnr] = to
				return acc
			else
				local relpath = vim.fs.relpath(from, name)
				if relpath then
					acc[bufnr] = vim.fs.joinpath(to, relpath)
				end
			end
			return acc
		end)

	-- Send LSP pre-rename notifications
	local clients = notify_lsp_clients and vim.lsp.get_clients() or {}
	for _, client in ipairs(clients) do
		if client:supports_method("workspace/willRenameFiles") then
			local resp = client:request_sync("workspace/willRenameFiles", lsp_changes, 1000, 0)
			if resp and resp.result ~= nil then
				vim.lsp.util.apply_workspace_edit(resp.result, client.offset_encoding)
			end
		end
	end

	local success, error, message = uv.fs_rename(from, to)
	if error or not success then
		return nil, { message or error or "unknown error" }
	end

	vim.schedule(function()
		for key, val in pairs(buf_renames) do
			vim.api.nvim_buf_set_name(key, val)
		end
		-- Send LSP notifications
		for _, client in ipairs(clients) do
			if client:supports_method("workspace/didRenameFiles") then
				client:notify("workspace/didRenameFiles", lsp_changes)
			end
		end
	end)
	return true, nil
end

---@param paths string[]
---@return boolean|nil, string[]|nil, number
function M.delete_paths(paths)
	local errors = {}
	local deleted_count = 0
	for _, path in ipairs(paths) do
		local ok, err = pcall(vim.fs.rm, path, { recursive = true })
		if ok then
			Snacks.bufdelete({ file = path, force = true, wipe = true })
			deleted_count = deleted_count + 1
		else
			table.insert(errors, "Could not delete " .. path .. ": " .. tostring(err))
		end
	end

	return #errors == 0 and true or nil, #errors > 0 and errors or nil, deleted_count
end

---@async
---Copy a file or directory to a new location.
---@param path string  -- Absolute file path to copy.
---@param dir string  -- Absolute path of destination directory.
---@param path_type "file" | "directory"  -- Type of path.
---@param callback fun(ok: boolean|nil, errors?: string[])  -- Callback function to call when the copy is complete.
local function copy_path(path, dir, path_type, callback)
	if path_type == "file" then
		local destination = vim.fs.joinpath(dir, vim.fs.basename(path))
		uv.fs_copyfile(path, destination, { excl = false, ficlone = true, ficlone_force = false },
			function(err)
				if err then
					callback(nil, { err })
					return
				end
				callback(true) --success
			end)
	elseif path_type == "directory" then
		local new_dir = vim.fs.joinpath(dir, vim.fs.basename(path))
		local mkdir_ok, mkdir_errors = M.mkdir_p(new_dir)
		if not mkdir_ok then
			callback(nil, mkdir_errors)
			return
		end
		return coroutine.wrap(function()
			local errors = {}
			local children = vim.fs.dir(path, { follow = false })
			local co = coroutine.running()
			local total = 0
			local done = 0
			for name, type in children do
				total = total + 1
				if type ~= "file" and type ~= "directory" then
					table.insert(errors, "Unsupported file type: " .. type .. " for " .. name)
					done = done + 1
				else
					local child_path = vim.fs.joinpath(path, name)
					copy_path(child_path, new_dir, type, function(success, child_errors)
						if not success and child_errors then
							vim.list_extend(errors, child_errors)
						end
						done = done + 1
						vim.schedule(function() coroutine.resume(co) end)
					end)
				end
			end
			while done < total do
				coroutine.yield() -- Wait for all copies to complete
			end
			callback(#errors == 0 and true or nil, #errors > 0 and errors or nil)
		end)()
	end
end

---@async
---Copy a list of files or paths to a new location.
---@param paths string[]  -- List of file paths to copy.
---@param dir string  -- Destination directory.
---@param callback fun(ok: boolean|nil, errors?: string[])  -- Callback function to call when the copy is complete.
function M.copy_paths(paths, dir, callback)
	local writeable, error = is_writeable_dir(dir)
	if error then
		callback(nil, { error })
		return
	elseif not writeable then
		callback(nil, { "Directory is not writeable: " .. dir })
		return
	end
	coroutine.wrap(function()
		local errors = {}
		local done = 0
		local co = coroutine.running()
		for _, path in ipairs(paths) do
			local stat, stat_error = uv.fs_stat(path)
			if not stat then
				table.insert(errors, stat_error)
				done = done + 1
			elseif stat.type ~= "file" and stat.type ~= "directory" then
				table.insert(errors, "Unsupported file type: " .. stat.type .. " for " .. path)
				done = done + 1
			else
				copy_path(path, dir, stat.type, function(success, err_copy)
					if not success and err_copy then
						vim.list_extend(errors, err_copy)
					end
					done = done + 1
					vim.schedule(function() coroutine.resume(co) end)
				end)
			end
		end
		while done < #paths do
			coroutine.yield() -- Wait for all copies to complete
		end
		return vim.schedule(function()
			callback(#errors == 0 and true or nil, #errors > 0 and errors or nil)
		end)
	end)()
end

---Move a file or directory to a new location
---@param paths string[]  -- List of absolute file paths to move
---@param dir string  -- Destination directory
---@param opts? { notify_lsp_clients?: boolean }
---@param callback? fun(ok: boolean|nil, errors?: string[])
function M.move_paths(paths, dir, opts, callback)
	opts = opts or {}
	callback = callback or function(_, _) end
	local notify_lsp_clients = opts.notify_lsp_clients or false

	local writeable, error = is_writeable_dir(dir)
	if error then
		callback(nil, { error })
		return
	elseif not writeable then
		callback(nil, { "Directory is not writeable: " .. dir })
		return
	end
	coroutine.wrap(function()
		local co = coroutine.running()
		local done = 0
		local errors = {}
		for _, path in ipairs(paths) do
			local old_path = vim.fs.normalize(path)
			local new_path = vim.fs.joinpath(dir, vim.fs.basename(path))
			vim.schedule(function()
				local success, rename_errors = M.rename_path(old_path, new_path, notify_lsp_clients)
				if not success then
					table.insert(errors,
						("Could not move %s to %s: %s"):format(old_path, new_path, table.concat(rename_errors or {}, "\n")))
				end
				done = done + 1
				return vim.schedule(function() coroutine.resume(co) end)
			end)
		end
		while done < #paths do
			coroutine.yield() -- Wait for all renames to complete
		end
		return vim.schedule(function()
			callback(#errors == 0 and true or nil, #errors > 0 and errors or nil)
		end)
	end)()
end

return M
