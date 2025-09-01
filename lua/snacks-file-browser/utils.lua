local M = {}
local uv = vim.uv

---@async
---Recursively creates an absolute directory and all its parent directories asynchronously.
---(Implemented iteratively, assumes path is absolute if not nil/empty)
---@param path string The absolute directory path to create.
---       If path is nil or empty, behavior is to attempt mkdir on that value, which will fail.
---@param mode number|nil Optional. The file mode (permissions) for the directories,
---       e.g., tonumber("755", 8). Defaults to tonumber("755", 8).
---@param callback function|nil Optional. A callback function `function(err)` that is
---       called upon completion. `err` is nil on success, or an error object
---       (table with `code`, `name`, `message`, `errno`) on failure.
function M.mkdir_async(path, mode, callback)
	local final_cb = vim.schedule_wrap(callback or function() end)
	local actual_mode = mode or tonumber("755", 8)

	-- Helper function to attempt creating a single directory,
	-- and verifies if it's a directory if it already existed.
	local try_make_single_dir = function(current_path, current_mode, cb_single)
		cb_single = cb_single or function() end

		uv.fs_mkdir(current_path, current_mode, function(mkdir_err)
			if not mkdir_err then
				cb_single(nil) -- Successfully created
			elseif mkdir_err:find('^EEXIST') then
				uv.fs_stat(current_path, function(stat_err, stat_data)
					if stat_err then
						cb_single(stat_err or mkdir_err)
					elseif stat_data and stat_data.type == 'directory' then
						cb_single(nil) -- Exists and is a directory: success
					else
						local err_not_dir = ('EEXIST: Path "%s" exists and is not a directory.'):format(current_path)
						cb_single(err_not_dir)
					end
				end)
			else
				cb_single(mkdir_err) -- Other mkdir error
			end
		end)
	end

	-- Generates path segments from root to the full path.
	-- Assumes p_raw is absolute if it's a non-empty, non-nil string.
	local get_path_segments_to_create = function(p_raw)
		-- If p_raw is nil or "", it's not a valid absolute path.
		-- Return {p_raw} to let fs_mkdir handle the error later.
		if not p_raw or p_raw == "" then
			return { p_raw }
		end

		local norm_path = vim.fs.normalize(p_raw)
		-- If normalization results in an empty string (e.g. path was invalid relative to root)
		if norm_path == "" then
			return { norm_path } -- Let fs_mkdir handle this error.
		end

		local segments = {}
		-- Collect parents; vim.fs.parents yields from immediate parent up to (but not including) root's parent.
		-- Example: /a/b/c -> parents are /a/b, /a, /
		for parent_segment in vim.fs.parents(norm_path) do
			table.insert(segments, 1, parent_segment) -- Prepend to get them in root-first order
		end

		-- If norm_path is a root itself (e.g., "/" or "C:\"), vim.fs.parents yields no segments.
		-- In this case, the segments list should just be the norm_path itself.
		if #segments == 0 then
			-- This implies norm_path is a root (e.g. "/", "C:\") OR it's a relative path like "foo".
			-- If it's a root (dirname(norm_path) == norm_path), then segments = {norm_path}.
			-- If it's relative (e.g. "foo"), segments = {"foo"}.
			-- The function will still attempt to create it; consumer ensures path is absolute for guarantee.
			table.insert(segments, norm_path)
		elseif segments[#segments] ~= norm_path then
			-- Add the normalized_path itself as the last segment if it's not already there.
			-- (It shouldn't be, as vim.fs.parents doesn't include the path itself).
			table.insert(segments, norm_path)
		end
		return segments
	end

	local segments_to_create
	-- pcall to catch potential errors from vim.fs.normalize or other path logic if path is malformed.
	local norm_ok, result = pcall(get_path_segments_to_create, path)

	if not norm_ok then
		-- Error during path processing (e.g., path was problematic for normalization)
		vim.defer_fn(function()
			final_cb('EINVAL: Error processing path: ' .. tostring(result)) -- result is the error message from pcall
		end, 0)
		return
	end
	segments_to_create = result

	-- With the current get_path_segments_to_create, segments_to_create will always have at least one element.
	-- If path was nil or "", that element will be nil or "", and try_make_single_dir will subsequently fail.

	local current_segment_idx = 1
	local function create_next_segment()
		if current_segment_idx > #segments_to_create then
			final_cb(nil) -- All segments created successfully
			return
		end

		local segment_path = segments_to_create[current_segment_idx]

		-- No need for explicit nil/empty check on segment_path here;
		-- try_make_single_dir will pass it to uv.fs_mkdir, which will error appropriately.

		try_make_single_dir(segment_path, actual_mode, function(err_single)
			if err_single then
				final_cb(err_single) -- Error creating this segment, stop.
				return
			end
			current_segment_idx = current_segment_idx + 1
			create_next_segment() -- Create the next segment
		end)
	end

	create_next_segment() -- Start the iterative creation process
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
---@return boolean|nil, string|nil, string|nil
function M.create_file(file)
	-- Create the parent directory if necessary
	local dir = vim.fs.dirname(file)
	local mkdir_result = vim.fn.mkdir(dir, "p")
	if mkdir_result ~= 1 then
		return nil, "Could not create parent directory: " .. dir
	end
	local fd, error = uv.fs_open(file, "w", tonumber('755', 8))
	if not fd then
		return nil, error
	end
	_, error = uv.fs_close(fd)
	if error then
		return nil, error
	end
	return true -- success
end

---Rename a file or directory.
---Will update buffer names if the file (or any files contained in the directory)
---are open in buffers in Neovim.
---Will also emit appropriate lsp notifications to clients that support it
---@param from string  -- Absolute path of the file or directory to rename
---@param to string  -- Absolute path of the new name for the file or directory
---@param notify_lsp_clients boolean  -- Whether to notify LSP clients about the rename
---@return boolean|nil, string|nil, string|nil
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
		return nil, error, message
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
	return success
end

---@async
---Copy a file or directory to a new location.
---@param path string  -- Absolute file path to copy.
---@param dir string  -- Absolute path of destination directory.
---@param path_type "file" | "directory"  -- Type of path.
---@param callback function  -- Callback function to call when the copy is complete.
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
		local mkdir_result = vim.fn.mkdir(new_dir, "p")
		if mkdir_result ~= 1 then
			callback(nil, { "Error while creating directory " .. new_dir })
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
					copy_path(child_path, new_dir, type, function(err)
						if err then
							vim.list_extend(errors, err)
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
---@param callback function  -- Callback function to call when the copy is complete.
function M.copy_paths(paths, dir, callback)
	local writeable, error, message = is_writeable_dir(dir)
	if error then
		callback(nil, error, message)
		return
	elseif not writeable then
		callback(nil, "EACCES", "Directory is not writeable: " .. dir)
	end
	coroutine.wrap(function()
		local errors = {}
		local done = 0
		local co = coroutine.running()
		local stat
		for _, path in ipairs(paths) do
			stat, error = uv.fs_stat(path)
			if not stat then
				table.insert(errors, error)
				done = done + 1
			elseif stat.type ~= "file" and stat.type ~= "directory" then
				table.insert(errors, "Unsupported file type: " .. stat.type .. " for " .. path)
				done = done + 1
			else
				copy_path(path, dir, stat.type, function(success, err_copy)
					if not success then
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
function M.move_paths(paths, dir, opts)
	opts = opts or {}
	local callback = opts.callback or function(_, _) end
	local notify_lsp_clients = opts.notify_lsp_clients or false

	local writeable, error = is_writeable_dir(dir)
	if error then
		callback({ error = error })
		return
	elseif not writeable then
		callback({ error = "EACCES", message = "Directory is not writeable: " .. dir })
	end
	coroutine.wrap(function()
		local co = coroutine.running()
		local done = 0
		local errors = {}
		for _, path in ipairs(paths) do
			local old_path = vim.fs.normalize(path)
			local new_path = vim.fs.joinpath(dir, vim.fs.basename(path))
			vim.schedule(function()
				local success
				success, error = M.rename_path(old_path, new_path, notify_lsp_clients)
				if error or not success then
					table.insert(errors, {
						[error] = ("Could not move %s to %\n%s"):format(old_path, new_path, error)
					})
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
