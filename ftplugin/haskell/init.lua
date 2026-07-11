-- ghci requires multiline input to be wrapped between ':{' and ':}'; single-line
-- input must NOT be wrapped, so only do it when there's more than one line
vim.b.tunnell_wrap = function(lines)
	if #lines <= 1 then
		return lines
	end

	local wrapped = { ':{' }
	vim.list_extend(wrapped, lines)
	table.insert(wrapped, ':}')
	return wrapped
end
