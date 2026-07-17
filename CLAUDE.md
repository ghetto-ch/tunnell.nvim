# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

tunnell.nvim is a small Neovim plugin (Lua) that sends ("tunnells") text from a buffer to a target terminal pane (tmux or WezTerm), for REPL-driven workflows. It's a minimal alternative to vim-slime. There is no build step, test suite, or CI — the entire runtime logic lives in `lua/tunnell/init.lua`.

## Development

- No build, lint, or test commands exist in this repo. Verify changes by loading the plugin in a real Neovim instance (see below) and exercising the commands manually.
- `.luarc.json` configures the Lua language server (LuaJIT runtime, `vim` global) for editor diagnostics only — it's not a CLI tool to invoke.
- Code style already in `lua/tunnell/init.lua`: tabs for indentation, single-quoted strings, functions declared as `local` forward-declarations at the top of the file then assigned lower down (not written as `local function foo()`). Match this when adding functions.

### Manual testing

Load the plugin directly from this working tree in a scratch Neovim config, e.g.:

```lua
vim.opt.rtp:prepend('/home/ghetto/Develop/neovim/tunnell.nvim')
require('tunnell').setup({})
```

Then exercise `:TunnellCell`, `:TunnellRange`, `:TunnellFunction`, `:TunnellParagraph`, `:TunnellConfig`, `:TunnellInsertCellHeader` against a real tmux or WezTerm pane, since the plugin shells out to the `tmux`/`wezterm` CLIs via `vim.fn.system`.

## Architecture

Everything is in `lua/tunnell/init.lua`, structured around one idea: figure out a line range to send, then hand it to a target-specific sender.

- **Config resolution** (`get_cell_header`, `get_target`, `get_tmux_target`, `get_wezterm_target`): all config is buffer-local (`vim.b.*`), falling back to a module-level `defaults` table. `M.setup()` merges user config into `defaults`; `:TunnellConfig` (the `config` function) prompts and sets the `vim.b.*` overrides per-buffer. There is no global/user-command-scoped config beyond these two layers.
- **Range-finding** (`find_range`, `tunnell_paragraph`, `tunnell_function`, `tunnell_cell`): each of these computes a `{start_line, end_line}` and delegates to `tunnell_range`.
  - `tunnell_cell` searches backward/forward for the configured `cell_header` pattern (default `# %%`, Jupyter-style); if no cell header is found in the buffer, it falls back to `tunnell_function`.
  - `tunnell_function` uses `vim.treesitter.get_node()` and walks up parents looking for a node whose type matches `function`/`method`; if treesitter has no parser or no function is found, it falls back to `tunnell_paragraph`.
  - `tunnell_paragraph` finds the blank-line-delimited paragraph around the cursor.
- **Sending** (`send_to_tmux`, `send_to_wezterm`, `send_to_target`): dispatches on `get_target()`. Both senders shell out via `vim.fn.system`. For WezTerm, the configured target can be a direction (`Up`/`Down`/`Left`/`Right`/`Next`/`Prev`, resolved via `wezterm cli get-pane-direction`) or a literal numeric pane-id string (matched with `^%d+$`) to target a pane in another window/tab. Both senders send a trailing Enter/`\r` after the text so the REPL executes it.
- **Per-filetype wrapping**: `tunnell_range` checks `vim.b.tunnell_wrap`, an optional buffer-local function that transforms `lines` before sending. This is how `ftplugin/<filetype>/init.lua` files customize behavior per language — e.g. `ftplugin/haskell/init.lua` wraps multi-line sends in `:{ ... :}` because ghci requires it. Add new per-language behavior by creating `ftplugin/<filetype>/init.lua` and setting `vim.b.tunnell_wrap`, not by branching inside `init.lua`.
- **User commands** are all registered at the bottom of the file (`TunnellConfig`, `TunnellRange`, `TunnellCell`, `TunnellParagraph`, `TunnellFunction`, `TunnellInsertCellHeader`) and just call the corresponding local function.
