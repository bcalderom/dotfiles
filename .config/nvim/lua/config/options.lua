-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Show absolute line numbers on the current line
vim.opt.nu = true

-- Show relative line numbers on all other lines (useful for motions like 5j / 3k)
vim.opt.relativenumber = true

-- Enable simple, syntax-aware indentation
vim.opt.smartindent = true

-- Keep indentation from the previous line when creating a new one
vim.opt.autoindent = true

-- Enable soft line wrapping (long lines wrap visually)
vim.opt.wrap = true

-- Do not keep search matches highlighted after the search is done
vim.opt.hlsearch = false

-- Show search matches incrementally while typing the pattern
vim.opt.incsearch = true

-- Enable 24-bit (true color) support in the terminal
vim.opt.termguicolors = true

-- Keep at least 8 lines visible above and below the cursor
vim.opt.scrolloff = 8

-- Draw a vertical guide at column 80
vim.opt.colorcolumn = "80"

-- Select Telescope as the picker UI for LazyVim
vim.g.lazyvim_picker = "telescope"
