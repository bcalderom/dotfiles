-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set:
-- https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Open netrw file explorer in the current window
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

-- Move selected lines down in visual mode and reindent
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")

-- Move selected lines up in visual mode and reindent
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- Join lines but keep the cursor in the same position
vim.keymap.set("n", "J", "mzJ`z")

-- Scroll half a page down and keep cursor centered
vim.keymap.set("n", "<C-d>", "<C-d>zz")

-- Scroll half a page up and keep cursor centered
vim.keymap.set("n", "<C-u>", "<C-u>zz")

-- Go to next search result, center screen, and open folds
vim.keymap.set("n", "n", "nzzzv")

-- Go to previous search result, center screen, and open folds
vim.keymap.set("n", "N", "Nzzzv")

-- Reindent a paragraph and return cursor to original position
vim.keymap.set("n", "=ap", "ma=ap'a")

-- Paste over a visual selection without overwriting the yank register
vim.keymap.set("x", "<leader>p", [["_dP]])

-- Yank to system clipboard (normal + visual)
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]])

-- Yank entire line to system clipboard
vim.keymap.set("n", "<leader>Y", [["+Y]])

-- Delete without copying to any register
vim.keymap.set({ "n", "v" }, "<leader>d", '"_d')

-- Substitute the word under cursor throughout the file (case-insensitive),
-- with cursor positioned to type the replacement
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])

-- Make the current file executable
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

-- Source (reload) the current file
vim.keymap.set("n", "<leader><leader>", function()
  vim.cmd("so")
end)
