local o = vim.opt

o.number = true
o.mouse = "a"
o.clipboard = "unnamedplus"
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
  -- Copy: OSC 52 to your Mac. Paste (p): the last thing copied in this Neovim
  -- (reading the Mac's clipboard over SSH isn't reliable; Command+V still works).
  local osc52 = require("vim.ui.clipboard.osc52")
  local last = { {}, "v" }
  local function copy(reg)
    local send = osc52.copy(reg)
    return function(lines, regtype)
      last = { lines, regtype }
      send(lines, regtype)
    end
  end
  local function paste()
    return last
  end
  vim.g.clipboard = {
    name = "OSC 52 (copy to the Mac over SSH)",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end
o.ignorecase = true
o.smartcase = true
o.splitright = true
o.splitbelow = true
o.signcolumn = "yes"
o.undofile = true
o.updatetime = 250
o.scrolloff = 4
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.confirm = true

-- A thick, visible split bar so it's easy to grab with the mouse and drag
-- (e.g. to resize the Claude split). laststatus=3 = one statusline, cleaner bars.
o.laststatus = 3
o.fillchars:append({ vert = "┃", horiz = "━", horizup = "┻", horizdown = "┳", vertleft = "┫", vertright = "┣", verthoriz = "╋" })
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#7aa2f7", bold = true })
  end,
})

-- Markdown and text read better wrapped; tree-sitter parsers for markdown ship with Neovim.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "text" },
  callback = function(ev)
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    if vim.bo[ev.buf].filetype == "markdown" then
      pcall(vim.treesitter.start, ev.buf)
    end
  end,
})
