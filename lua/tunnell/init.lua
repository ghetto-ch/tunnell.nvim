local M = {}

local defaults = {
	tmux_target = '{right-of}',
	cell_header = '# %%',
}

-- Derives a cell header from the buffer's `commentstring` (e.g. '// %s' -> '// %%'),
-- falling back to `defaults.cell_header` when `commentstring` is empty
local function default_cell_header()
	if vim.bo.commentstring ~= '' then
		return vim.bo.commentstring:format('%%')
	end
	return defaults.cell_header
end

-- Sets buffer-variables `cell_header` and `tmux_target` to values given by user via `vim.fn.input`
local function config()
	-- cell_header
	vim.b.cell_header = vim.fn.input({
		prompt = 'Cell header: ',
		-- autocomplete with current cell header if exists, otherwise autocomplete with language default
		default = vim.b.cell_header and vim.b.cell_header or default_cell_header(),
	})

	-- tmux_target
	vim.b.tmux_target = vim.fn.input({
		prompt = 'Tmux target pane: ',
		-- autocomplete with current target if exists, otherwise autocomplete with global
		default = vim.b.tmux_target and vim.b.tmux_target or defaults.tmux_target,
	})
end

-- Tunnells range `r` to target
--
-- Reads `r.line1` and `r.line2`
local function tunnell_range(r)
	-- grab range from `r.line1` to `r.line2` and load it into the tmux buffer directly,
	-- avoiding a `:w !cmd` filter (which always triggers a "press ENTER" prompt)
	local lines = vim.api.nvim_buf_get_lines(0, r.line1 - 1, r.line2, false)

	-- let filetypes with REPL-specific quirks (e.g. ghci's ':{'/':}' multiline markers)
	-- transform the lines before they're sent; see after/ftplugin/haskell.lua
	if vim.b.tunnell_wrap then
		lines = vim.b.tunnell_wrap(lines)
	end

	vim.fn.system({ 'tmux', 'load-buffer', '-' }, table.concat(lines, '\n') .. '\n')

	-- tunnell lines
	local target = vim.b.tmux_target and vim.b.tmux_target or defaults.tmux_target
	vim.fn.system('tmux paste-buffer -dpr -t ' .. target)

	-- tunnell <CR> to run cell in REPL
	vim.fn.system('tmux send-keys -t ' .. target .. ' Enter')
end

-- Tunnells paragraph to target
--
-- Cursor does not have to be at the start of the paragraph, but anywhere inside it
local function tunnell_paragraph()
	-- define start of paragraph
	-- 'b'  search Backward instead of forward
	-- 'n'  do Not move the cursor
	-- 'W'  don't Wrap around the end of the file
	local start_line = vim.fn.search('^$', 'bnW')

	-- if no blank line found above cursor, paragraph starts at top of file. Otherwise,
	-- paragraph starts one line below the blank line
	if start_line == 0 then
		start_line = 1
	else
		start_line = start_line + 1
	end

	-- define end of paragraph
	local end_line = vim.fn.search('^$', 'nW')

	-- if no blank line found below cursor, cursor is in the last paragraph so end line
	-- should be the last line of the file. Otherwise, end line is one line above the blank line
	if end_line == 0 then
		end_line = vim.fn.line('$')
	else
		end_line = end_line - 1
	end

	-- tunnell paragraph range
	tunnell_range({ line1 = start_line, line2 = end_line })
end

-- Tunnells enclosing function to target
--
-- Cursor must be inside a function; uses treesitter to find the smallest enclosing
-- node whose type looks like a function/method definition
local function tunnell_function()
	local node = vim.treesitter.get_node()
	if not node then
		print('No treesitter parser/node found at cursor, sending paragraph.')
		tunnell_paragraph()
		return
	end

	while
		node and not (node:type():match('function') or node:type():match('method'))
	do
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
--
-- Cursor does not have to be on the cell header, but anywhere inside the cell
local function tunnell_cell()
	-- load cell_header
	local cell_header = vim.b.cell_header and vim.b.cell_header
		or default_cell_header()

	-- '\V' (very nomagic) makes every character literal except '\', so comment markers
	-- containing regex-special characters (e.g. '/* %% */', '// %%') are matched as-is
	local pattern = '\\V' .. vim.fn.escape(cell_header, '\\')

	-- define start of cell
	-- 'b'  search Backward instead of forward
	-- 'c'  accept a match at the Cursor position
	-- 'n'  do Not move the cursor
	-- 'W'  don't Wrap around the end of the file
	local start_line = vim.fn.search(pattern, 'bcnW')

	-- if no header is found above cursor, do nothing
	if start_line == 0 then
		print('No cell header found above cursor, sending function.')
		tunnell_function()
		return
	end

	-- define end of cell
	local end_line = vim.fn.search(pattern, 'nW')

	-- if no header found below cursor, cursor is in the last cell so end line should be the
	-- last line of the file. Otherwise, end line is one line above next cell header
	if end_line == 0 then
		end_line = vim.fn.line('$')
	else
		end_line = end_line - 1
	end

	-- tunnell cell range
	tunnell_range({ line1 = start_line, line2 = end_line })

	-- put cursor on next cell (search() avoids the '/pattern' ex-command, whose '/'
	-- delimiter would otherwise need separate escaping for markers containing '/')
	vim.fn.search(pattern)
end

-- Inserts a new line below the cursor containing the cell header, cursor stays in
-- normal mode at the end of it
local function insert_cell_header()
	local cell_header = vim.b.cell_header and vim.b.cell_header
		or default_cell_header()

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
