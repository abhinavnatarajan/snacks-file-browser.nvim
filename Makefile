LUA_FILES := $(shell find lua tests -name '*.lua' -print)

.PHONY: test lint

test:
	nvim --headless -u NONE -l tests/run.lua

lint:
	luac -p $(LUA_FILES)
