local M = {}

local defaults = {
	tmux_target = '{right-of}',
	cell_header = '# %%',
}

local default_cell_header
local get_cell_header
local get_tmux_target
local config
local tunnell_range
local find_bounds
local tunnell_paragraph
local is_function
local tunnell_function
local tunnell_cell
local insert_cell_header

-- Derives a cell header from the buffer's `commentstring` (e.g. '// %s' -> '// %%'),
-- falling back to `defaults.cell_header` when `commentstring` is empty
default_cell_header = function()
	if vim.bo.commentstring ~= '' then
		return vim.bo.commentstring:format('%%')
	end
	return defaults.cell_header
end

-- Buffer-local cell_header/tmux_target, falling back to the language-derived or
-- global default when unset
get_cell_header = function()
	return vim.b.cell_header or default_cell_header()
end

get_tmux_target = function()
	return vim.b.tmux_target or defaults.tmux_target
end

-- Sets buffer-variables `cell_header` and `tmux_target` to values given by user via `vim.fn.input`
config = function()
	-- cell_header
	vim.b.cell_header = vim.fn.input({
		prompt = 'Cell header: ',
		-- autocomplete with current cell header if exists, otherwise autocomplete with language default
		default = get_cell_header(),
	})

	-- tmux_target
	vim.b.tmux_target = vim.fn.input({
		prompt = 'Tmux target pane: ',
		-- autocomplete with current target if exists, otherwise autocomplete with global
		default = get_tmux_target(),
	})
end

-- Tunnells range `r` to target
-- Reads `r.line1` and `r.line2`
tunnell_range = function(r)
	local lines = vim.api.nvim_buf_get_lines(0, r.line1 - 1, r.line2, false)

	-- let filetypes with REPL-specific quirks (e.g. ghci's ':{'/':}' multiline markers)
	-- transform the lines before they're sent; see ftplugin/haskell/init.lua
	if vim.b.tunnell_wrap then
		lines = vim.b.tunnell_wrap(lines)
	end

	vim.fn.system({ 'tmux', 'load-buffer', '-' }, table.concat(lines, '\n'))

	-- tunnell lines (argv form, not a shell string: `target` is user-controlled input
	-- and must not be interpolated into a shell command)
	local target = get_tmux_target()
	vim.fn.system({ 'tmux', 'paste-buffer', '-d', '-p', '-r', '-t', target })

	-- tunnell <CR> to run cell in REPL
	vim.fn.system({ 'tmux', 'send-keys', '-t', target, 'Enter' })
end

-- Finds the [start_line, end_line] bounds of the block delimited by `pattern`,
-- excluding the delimiter lines themselves. Falls back to the file's first/last
-- line when no delimiter is found in that direction. Also returns whether a
-- delimiter was found above the cursor, for callers that need to special-case it
-- (e.g. tunnell_cell falling back to tunnell_function)
find_bounds = function(pattern, back_flags)
	local found_above = vim.fn.search(pattern, back_flags)
	local start_line = (found_above == 0) and 1 or found_above + 1

	local found_below = vim.fn.search(pattern, 'nW')
	local end_line = (found_below == 0) and vim.fn.line('$') or found_below - 1

	return start_line, end_line, found_above ~= 0
end

-- Tunnells paragraph to target
-- Cursor does not have to be at the start of the paragraph, but anywhere inside it
tunnell_paragraph = function()
	-- 'b'  search Backward instead of forward
	-- 'n'  do Not move the cursor
	-- 'W'  don't Wrap around the end of the file
	local start_line, end_line = find_bounds('^$', 'bnW')
	tunnell_range({ line1 = start_line, line2 = end_line })
end

-- Helper function. Whether `node`'s type looks like a function/method definition
is_function = function(node)
	local t = node:type()
	return t:match('function') or t:match('method')
end

-- Tunnells enclosing function to target
-- Cursor must be inside a function; uses treesitter to find the smallest enclosing
-- node whose type looks like a function/method definition
tunnell_function = function()
	local node = vim.treesitter.get_node()
	if not node then
		print('No treesitter parser/node found at cursor, sending paragraph.')
		tunnell_paragraph()
		return
	end

	while node and not is_function(node) do
		node = node:parent()
	end

	if not node then
		print('No enclosing function found, sending paragraph.')
		tunnell_paragraph()
		return
	end

	local start_row, _, end_row, end_col = node:range()

	-- treesitter ranges are end-exclusive; if the node ends at column 0 of `end_row`,
	-- the last line actually belonging to it is the one above
	if end_col == 0 then
		end_row = end_row - 1
	end

	-- tunnell function range (treesitter rows are 0-indexed)
	tunnell_range({ line1 = start_row + 1, line2 = end_row + 1 })
end

-- Tunnells cell to target
-- Cursor does not have to be on the cell header, but anywhere inside the cell
tunnell_cell = function()
	local cell_header = get_cell_header()

	-- '\V' (very nomagic) makes every character literal except '\', so comment markers
	-- containing regex-special characters (e.g. '/* %% */', '// %%') are matched as-is
	local pattern = '\\V' .. vim.fn.escape(cell_header, '\\')

	-- 'b'  search Backward instead of forward
	-- 'c'  accept a match at the Cursor position
	-- 'n'  do Not move the cursor
	-- 'W'  don't Wrap around the end of the file
	local start_line, end_line, found = find_bounds(pattern, 'bcnW')

	-- if no header is found above cursor, do nothing
	if not found then
		print('No cell header found above cursor, sending function.')
		tunnell_function()
		return
	end

	-- tunnell cell range
	tunnell_range({ line1 = start_line, line2 = end_line })

	-- put cursor on next cell (search() avoids the '/pattern' ex-command, whose '/'
	-- delimiter would otherwise need separate escaping for markers containing '/')
	vim.fn.search(pattern)
end

-- Inserts a new line below the cursor containing the cell header, cursor stays in
-- normal mode at the start of it
insert_cell_header = function()
	local cell_header = get_cell_header()

	local row = vim.fn.line('.')
	vim.api.nvim_buf_set_lines(0, row, row, false, { cell_header })
	vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
end

-- create user commands
vim.api.nvim_create_user_command('TunnellConfig', config, {})
vim.api.nvim_create_user_command('TunnellRange', tunnell_range, { range = true })
vim.api.nvim_create_user_command('TunnellCell', tunnell_cell, {})
vim.api.nvim_create_user_command('TunnellParagraph', tunnell_paragraph, {})
vim.api.nvim_create_user_command('TunnellFunction', tunnell_function, {})
vim.api.nvim_create_user_command('TunnellInsertCellHeader', insert_cell_header, {})

-- Setup function for users to call from their plugin managers
function M.setup(user_config)
	-- merge user-config with defaults
	defaults = vim.tbl_deep_extend('force', defaults, user_config or {})
end

return M
