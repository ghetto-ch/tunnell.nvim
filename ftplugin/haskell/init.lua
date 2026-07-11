-- ghci requires multiline input to be wrapped between ':{' and ':}';
-- not needed for single-line input
vim.b.tunnell_wrap = function(lines)
	if #lines <= 1 then
		return lines
	end

	local wrapped = { ':{' }
	vim.list_extend(wrapped, lines)
	table.insert(wrapped, ':}')
	return wrapped
end
