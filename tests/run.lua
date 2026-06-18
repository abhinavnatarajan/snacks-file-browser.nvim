local root = vim.fn.getcwd()
vim.opt.runtimepath:append(root)
package.path = table.concat({
	vim.fs.joinpath(root, "lua", "?.lua"),
	vim.fs.joinpath(root, "lua", "?", "init.lua"),
	package.path,
}, ";")

local state = {
	notifications = {},
	bufdeleted = {},
}

package.preload["snacks"] = function()
	return {
		notify = {
			error = function(msg) table.insert(state.notifications, { level = "error", msg = msg }) end,
			info = function(msg) table.insert(state.notifications, { level = "info", msg = msg }) end,
			warn = function(msg) table.insert(state.notifications, { level = "warn", msg = msg }) end,
		},
		bufdelete = function(opts) table.insert(state.bufdeleted, opts) end,
	}
end

local Utils = require("snacks-file-browser.utils")
local Actions = require("snacks-file-browser.actions")

local tests = {}

local function test(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

local function fail(message)
	error(message, 2)
end

local function assert_true(value, message)
	if not value then fail(message or "expected truthy value") end
end

local function assert_eq(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		fail((message or "values differ") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual))
	end
end

local function assert_match(value, pattern, message)
	if type(value) ~= "string" or not value:find(pattern) then
		fail((message or "pattern not found") .. "\npattern: " .. pattern .. "\nvalue: " .. vim.inspect(value))
	end
end

local function with_tempdir(fn)
	local dir = vim.fn.tempname()
	assert_eq(vim.fn.mkdir(dir, "p"), 1, "failed to create temp dir")
	local ok, err = xpcall(function() fn(dir) end, debug.traceback)
	vim.fn.delete(dir, "rf")
	if not ok then error(err, 0) end
end

local function with_system(fn)
	local original_system = vim.system
	local ok, err = xpcall(fn, debug.traceback)
	vim.system = original_system
	if not ok then error(err, 0) end
end

local function wait_for(callback)
	assert_true(vim.wait(1000, callback, 10), "timed out waiting for callback")
end

local function write_file(path, lines)
	assert_eq(vim.fn.writefile(lines, path), 0, "failed to write " .. path)
end

test("yank_paths_to_clipboard emits CRLF text/uri-list", function()
	with_tempdir(function(dir)
		local first = vim.fs.joinpath(dir, "one file.txt")
		local second = vim.fs.joinpath(dir, "two.txt")
		write_file(first, { "one" })
		write_file(second, { "two" })

		with_system(function()
			local calls = {}
			vim.system = function(cmd, opts)
				table.insert(calls, { cmd = cmd, opts = opts })
				return { wait = function() return { code = 0, signal = 0, stdout = "" } end }
			end

			local ok, errors = Utils.yank_paths_to_clipboard({ first, second })
			assert_eq(ok, true)
			assert_eq(errors, nil)
			assert_eq(calls[1].cmd[1], "wl-copy")
			assert_eq(calls[1].cmd[3], "text/uri-list")
			assert_eq(calls[1].opts.stderr, false)
			assert_eq(calls[1].cmd[4], vim.uri_from_fname(first) .. "\r\n" .. vim.uri_from_fname(second) .. "\r\n")
		end)
	end)
end)

test("get_clipboard_paths parses local file URI forms", function()
	with_tempdir(function(dir)
		local first = vim.fs.joinpath(dir, "one file.txt")
		local second = vim.fs.joinpath(dir, "two.txt")
		write_file(first, { "one" })
		write_file(second, { "two" })

		with_system(function()
			local function clipboard(stdout)
				vim.system = function(cmd, opts)
					assert_eq(cmd, { "wl-paste", "-t", "text/uri-list", "-n" })
					assert_eq(opts.text, true)
					return { wait = function() return { code = 0, signal = 0, stdout = stdout } end }
				end
				return Utils.get_clipboard_paths()
			end

			local paths, errors = clipboard("# comment\r\n" .. vim.uri_from_fname(first) .. "\r\n" .. vim.uri_from_fname(second) .. "\n")
			assert_eq(paths, { first, second })
			assert_eq(errors, nil)

			paths, errors = clipboard("file:" .. first .. "\r\n")
			assert_eq(paths, { first })
			assert_eq(errors, nil)

			paths, errors = clipboard("file://localhost" .. first .. "\r\n")
			assert_eq(paths, { first })
			assert_eq(errors, nil)
		end)
	end)
end)

test("get_clipboard_paths rejects non-local clipboard URIs", function()
	with_system(function()
		local function clipboard(stdout)
			vim.system = function()
				return { wait = function() return { code = 0, signal = 0, stdout = stdout } end }
			end
			return Utils.get_clipboard_paths()
		end

		local paths, errors = clipboard("https://example.com/a.txt\r\n")
		assert_eq(paths, nil)
		assert_true(type(errors) == "table")
		assert_match(errors[1], "Unsupported clipboard URI scheme")

		paths, errors = clipboard("file://host.example.com/path/to/a.txt\r\n")
		assert_eq(paths, nil)
		assert_match(errors[1], "Unsupported non%-local clipboard URI")

		paths, errors = clipboard("file:////host.example.com/path/to/a.txt\r\n")
		assert_eq(paths, nil)
		assert_match(errors[1], "Unsupported non%-local clipboard URI")

		vim.system = function()
			return { wait = function() return { code = 3, signal = 0, stdout = "" } end }
		end
		paths, errors = Utils.get_clipboard_paths()
		assert_eq(paths, nil)
		assert_match(errors[1], "wl%-paste failed")
	end)
end)

test("copy_paths reports callback errors consistently", function()
	with_tempdir(function(dir)
		local done = false
		local result_ok
		local result_errors

		Utils.copy_paths({ vim.fs.joinpath(dir, "missing.txt") }, dir, function(ok, errors)
			result_ok = ok
			result_errors = errors
			done = true
		end)

		wait_for(function() return done end)
		assert_eq(result_ok, nil)
		assert_true(type(result_errors) == "table" and #result_errors == 1, "expected one copy error")
	end)
end)

test("copy_paths copies files and non-empty directories", function()
	with_tempdir(function(dir)
		local source_dir = vim.fs.joinpath(dir, "source")
		local nested = vim.fs.joinpath(source_dir, "nested.txt")
		local source_file = vim.fs.joinpath(dir, "file.txt")
		local dest = vim.fs.joinpath(dir, "dest")
		assert_eq(vim.fn.mkdir(source_dir, "p"), 1)
		assert_eq(vim.fn.mkdir(dest, "p"), 1)
		write_file(nested, { "nested" })
		write_file(source_file, { "file" })

		local done = false
		local result_ok
		local result_errors
		Utils.copy_paths({ source_file, source_dir }, dest, function(ok, errors)
			result_ok = ok
			result_errors = errors
			done = true
		end)

		wait_for(function() return done end)
		assert_eq(result_ok, true)
		assert_eq(result_errors, nil)
		assert_eq(vim.fn.filereadable(vim.fs.joinpath(dest, "file.txt")), 1)
		assert_eq(vim.fn.filereadable(vim.fs.joinpath(dest, "source", "nested.txt")), 1)
	end)
end)

test("copy action requires explicit selection", function()
	state.notifications = {}
	local original_copy_paths = Utils.copy_paths
	local called = false
	Utils.copy_paths = function()
		called = true
	end

	local ok, err = xpcall(function()
		local picker = {
			selected = function() return {} end,
			cwd = function() return root end,
			list = { set_selected = function() end },
			action = function() end,
		}
		Actions.actions.copy.action(picker, { file = vim.fs.joinpath(root, "README.md"), score = 1 })
	end, debug.traceback)
	Utils.copy_paths = original_copy_paths
	if not ok then error(err, 0) end

	assert_eq(called, false)
	assert_true(#state.notifications > 0, "expected selection notification")
	assert_eq(state.notifications[1].level, "error")
	assert_match(state.notifications[1].msg, "No items selected")
end)

local failures = 0
for _, entry in ipairs(tests) do
	state.notifications = {}
	state.bufdeleted = {}
	local ok, err = xpcall(entry.fn, debug.traceback)
	if ok then
		print("ok - " .. entry.name)
	else
		failures = failures + 1
		print("not ok - " .. entry.name)
		print(err)
	end
end

if failures > 0 then
	vim.api.nvim_err_writeln(string.format("%d test(s) failed", failures))
	vim.cmd("cq")
end

print(string.format("%d test(s) passed", #tests))
vim.cmd("qa")
