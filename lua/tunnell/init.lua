local M = {}

local defaults = {
	tmux_target = '{right}',
	cell_header = '# %%',
}

local default_cell_header
local get_cell_header
local get_tmux_target
local config
local tunnell_range
local find_range
local tunnell_paragraph
local is_function
local tunnell_function
local tunnell_cell
local insert_cell_header

default_cell_header = function()
	if vim.bo.commentstring ~= '' then
		return vim.bo.commentstring:format('%%')
	end
	return defaults.cell_header
end

get_cell_header = function()
	return vim.b.cell_header or default_cell_header()
end

get_tmux_target = function()
	return vim.b.tmux_target or defaults.tmux_target
end

-- Ask user for configs. Autocomplete with defaults if available.
config = function()
	vim.b.cell_header = vim.fn.input({
		prompt = 'Cell header: ',
		default = get_cell_header(),
	})

	vim.b.tmux_target = vim.fn.input({
		prompt = 'Tmux target pane: ',
		default = get_tmux_target(),
	})
end

is_function = function(node)
	-- Use treesitter to check if we are in a function, method or similar.
	local t = node:type()
	return t:match('function') or t:match('method')
end

find_range = function(pattern, back_flags)
	local found_above = vim.fn.search(pattern, back_flags)
	local start_line = (found_above == 0) and 1 or found_above + 1

	local found_below = vim.fn.search(pattern, 'nW')
	local end_line = (found_below == 0) and vim.fn.line('$') or found_below - 1

	return start_line, end_line, found_above ~= 0
end

tunnell_range = function(r)
	local lines = vim.api.nvim_buf_get_lines(0, r.line1 - 1, r.line2, false)

	-- Call a wrapper if defined. Usually from ftplugin.
	if vim.b.tunnell_wrap then
		lines = vim.b.tunnell_wrap(lines)
	end

	vim.fn.system({ 'tmux', 'load-buffer', '-' }, table.concat(lines, '\n'))

	local target = get_tmux_target()
	vim.fn.system({ 'tmux', 'paste-buffer', '-d', '-p', '-r', '-t', target })

	-- tunnell <CR> to run cell in REPL
	vim.fn.system({ 'tmux', 'send-keys', '-t', target, 'Enter' })
end

tunnell_paragraph = function()
	-- 'b'  search Backward instead of forward
	-- 'n'  do Not move the cursor
	-- 'W'  don't Wrap around the end of the file
	local start_line, end_line = find_range('^$', 'bnW')
	tunnell_range({ line1 = start_line, line2 = end_line })
end

tunnell_function = function()
	local node = vim.treesitter.get_node()
	if not node then
		tunnell_paragraph()
		return
	end

	while node and not is_function(node) do
		node = node:parent()
	end

	if not node then
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

tunnell_cell = function()
	local cell_header = get_cell_header()

	local pattern = '\\V' .. vim.fn.escape(cell_header, '\\')

	-- 'b'  search Backward instead of forward
	-- 'c'  accept a match at the Cursor position
	-- 'n'  do Not move the cursor
	-- 'W'  don't Wrap around the end of the file
	local start_line, end_line, found = find_range(pattern, 'bcnW')

	if not found then
		tunnell_function()
		return
	end

	tunnell_range({ line1 = start_line, line2 = end_line })

	-- put cursor on next cell
	vim.fn.search(pattern)
end

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
