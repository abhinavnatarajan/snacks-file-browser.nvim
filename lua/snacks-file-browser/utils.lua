local M = {}
local uv = vim.uv

-- Recursively creates an absolute directory and all its parent directories asynchronously.
-- (Implemented iteratively, assumes path is absolute if not nil/empty)
--
-- @param path string The absolute directory path to create.
--        If path is nil or empty, behavior is to attempt mkdir on that value, which will fail.
-- @param mode number|nil Optional. The file mode (permissions) for the directories,
--        e.g., tonumber("755", 8). Defaults to tonumber("755", 8).
-- @param callback function|nil Optional. A callback function `function(err)` that is
--        called upon completion. `err` is nil on success, or an error object
--        (table with `code`, `name`, `message`, `errno`) on failure.
function M.mkdir(path, mode, callback)
	local final_cb = callback or function() end
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

---@return boolean|nil, string|nil
local function is_writeable_dir(path, callback)
	uv.fs_stat(path, function(err, stat)
		if err or not stat then
			callback(err)
			return
		elseif stat.type ~= "directory" then
			callback("Path is not a directory: " .. path)
			return
		end
		uv.fs_access(path, "w", function(err_inner, perm)
			if err_inner then
				callback(err_inner)
			elseif not perm then
				callback("Directory is not writeable: " .. path)
			end
			callback(nil) -- success
		end)
	end)
end

---Asynchronously create a file at the given path
---@param file string  -- Absolute path to the file to create
---@param callback function  -- Callback function to call when the file is created
---callback should accept two arguments: success (boolean) and error message (string)
---callback takes place in a fast_context
function M.create_file(file, callback)
	callback = callback or function(_) end
	-- Create the parent directory, or make sure it is writeable
	local dir = vim.fs.dirname(file)
	M.mkdir(dir, nil, function(err)
		if err then
			callback("Could not create directory: " .. dir .. "\n" .. err)
			return
		end
		is_writeable_dir(dir, function(err_inner0)
			if err_inner0 then
				callback(err_inner0)
				return
			end
			uv.fs_open(file, "w", tonumber('755', 8), function(err_inner1, file_descriptor)
				if err then
					callback("Could not create file: " .. file .. "\n" .. err_inner1)
					return
				end
				uv.fs_close(file_descriptor, function(err_inner2)
					if err_inner2 then
						callback("Could not create file: " .. file .. "\n" .. err_inner2)
						return
					end
					callback(nil) -- success
				end)
			end)
		end)
	end)
end

---Asynchronously rename a file or directory
---Will update buffer names if the file (or any files contained in the directory)
---are open in buffers in Neovim.
---Will also emit appropriate lsp notifications to clients that support it
---@param from string  -- Absolute path of the file or directory to rename
---@param to string  -- Absolute path of the new name for the file or directory
---@param notify_lsp_clients boolean  -- Whether to notify LSP clients about the rename
---@param callback function  -- Callback function to call when the rename is complete
function M.rename_path(from, to, notify_lsp_clients, callback)
	callback = callback or function(_) end

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

	local on_rename = function(err, _)
		if err then
			callback(err)
			return
		end

		vim.schedule(
			function()
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
		callback(nil) -- success
	end

	uv.fs_rename(from, to, on_rename)
end

---Copy a file or directory to a new location
---@param path string  -- Absolute file path to copy
---@param dir string  -- Absolute path of destination directory
local function copy_path(path, dir, path_type, callback)
	if path_type == "file" then
		local destination = vim.fs.joinpath(dir, vim.fs.basename(path))
		uv.fs_copyfile(path, destination, { excl = false, ficlone = true, ficlone_force = false },
			function(err_copy)
				if err_copy then
					callback({ err_copy })
					return
				end
				callback(nil) --success
			end)
	elseif path_type == "directory" then
		local new_dir = vim.fs.joinpath(dir, vim.fs.basename(path))
		M.mkdir(new_dir, nil, coroutine.wrap(function(err_mkdir)
			if err_mkdir then
				callback({ "Error while creating directory " .. new_dir .. ": " .. err_mkdir })
				return
			end
			local errors = {}
			local children = vim.fs.dir(path, { follow = false })
			local co = coroutine.running()
			for name, type in children do
				if type ~= "file" and type ~= "directory" then
					errors[#errors + 1] = "Unsupported file type: " .. type .. " for " .. name
					goto continue
				end
				local child_path = vim.fs.joinpath(path, name)
				copy_path(child_path, new_dir, type, function(err_inner)
					if err_inner then
						vim.list_extend(errors, err_inner or {})
					end
					coroutine.resume(co)
				end)
				coroutine.yield()
				::continue::
			end
			callback(#errors > 0 and errors or nil)
		end))
	end
end

---Copy a list of files or paths to a new location
---@param paths string[]  -- List of file paths to copy
---@param dir string  -- Destination directory
---@return (table|nil), (nil|string)
function M.copy_paths(paths, dir, callback)
	is_writeable_dir(dir, coroutine.wrap(function(err)
		if err then
			callback({ err })
			return
		end
		local errors = {}
		local done = 0
		local num_files = #paths
		for _, path in ipairs(paths) do
			uv.fs_stat(path, function(err_stat, stat)
				if err_stat then
					vim.list_extend(errors, { err_stat })
					done = done + 1
				elseif not stat then
					vim.list_extend(errors, { "Could not stat path: " .. path })
					done = done + 1
				elseif stat.type ~= "file" and stat.type ~= "directory" then
					vim.list_extend(errors, { "Unsupported file type: " .. stat.type .. " for " .. path })
					done = done + 1
				else
					copy_path(path, dir, stat.type, function(err_copy)
						if err_copy then
							vim.list_extend(errors, err_copy)
						end
						done = done + 1
						if done == num_files then
							callback(#errors > 0 and errors or nil)
						end
					end)
					return
				end
				if done == num_files then
					callback(#errors > 0 and errors or nil)
				end
			end)
		end
	end))
end

---Move a file or directory to a new location
---@param paths string[]  -- List of absolute file paths to move
---@param dir string  -- Destination directory
function M.move_paths(paths, dir, opts)
	opts = opts or {}
	local callback = opts.callback or function(_, _) end
	local notify_lsp_clients = opts.notify_lsp_clients or false

	is_writeable_dir(dir, coroutine.wrap(function(err)
		if err then
			callback(err)
			return
		end
		local count = 0
		local errors = {}
		local co = coroutine.running()
		for _, path in ipairs(paths) do
			local old_path = vim.fs.normalize(path)
			local new_path = vim.fs.joinpath(dir, vim.fs.basename(path))
			vim.schedule(function()
				M.rename_path(
					old_path,
					new_path,
					notify_lsp_clients,
					function(err_rename)
						if err_rename then
							errors[#errors + 1] = "Could not move " ..
								old_path .. " to " .. new_path .. "\n" .. err_rename
						else
							count = count + 1
						end
						coroutine.resume(co)
					end
				)
			end)
			coroutine.yield()
		end
		callback(#errors > 0 and errors or nil, count)
	end))
end

return M
