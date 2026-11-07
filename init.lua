-- Minimal Neovim setup for working alongside Claude Code.
-- Plugins are managed by Neovim's built-in vim.pack (0.12+); the lockfile is
-- ~/.config/nvim/nvim-pack-lock.json. Update with :lua vim.pack.update()

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.options")
require("config.plugins")
require("config.keymaps")
