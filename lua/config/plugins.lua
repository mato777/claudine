vim.pack.add({
  "https://github.com/nvim-lua/plenary.nvim",
  "https://github.com/nvim-telescope/telescope.nvim",
  "https://github.com/folke/snacks.nvim",
  "https://github.com/coder/claudecode.nvim",
  "https://github.com/MeanderingProgrammer/render-markdown.nvim",
  "https://github.com/folke/tokyonight.nvim",
  "https://github.com/nvim-tree/nvim-tree.lua",
}, { confirm = false })

-- Omarchy's default theme (themes/tokyo-night/neovim.lua uses tokyonight-night).
require("tokyonight").setup({ style = "night" })
vim.cmd.colorscheme("tokyonight-night")

local images = require("config.term").has_images()

-- snacks: only image rendering and big-file handling.
require("snacks").setup({
  bigfile = { enabled = true },
  image = { enabled = images },
})

require("telescope").setup({
  defaults = {
    sorting_strategy = "ascending",
    layout_config = { prompt_position = "top" },
    file_ignore_patterns = { "^.git/", "node_modules/" },
  },
  pickers = {
    find_files = { hidden = true },
  },
})

-- Claude Code, connected to Neovim over the same protocol Anthropic's IDE
-- extensions use (selection, open files, diffs in Neovim). It runs in the middle
-- column of the layout (claude_layout.lua), always with bypass permissions.
require("claudecode").setup({
  terminal_cmd = "claude --dangerously-skip-permissions --settings "
    .. vim.fn.shellescape(require("claude_attention").hooks_file()), -- attention sound
  env = { NVIM_BIN = vim.v.progpath }, -- lets the hook script reach this Neovim on any machine
  focus_after_send = true, -- after <leader>cs / <leader>cb, keep typing in Claude
  diff_opts = {
    keep_terminal_focus = true, -- a proposed diff must not steal the cursor while you type
  },
  terminal = {
    provider = require("claude_layout").provider,
  },
})

-- claudecode tells Claude which buffer you're in ("In <file>" in Claude's prompt).
-- It only skips the Claude terminal, so the sessions list and the file tree were
-- reported as files ("In Claude sessions", "In NvimTree_1"). Report real files
-- only; Claude keeps showing the last real file you were in.
do
  local selection = require("claudecode.selection")
  for _, fn in ipairs({ "update_selection", "flush_visual_selection" }) do
    local orig = selection[fn]
    selection[fn] = function(...)
      if vim.bo.buftype ~= "" then
        return
      end
      return orig(...)
    end
  end
end

require("render-markdown").setup({
  file_types = { "markdown" },
})

-- File tree on the left. No Nerd Font installed, so plain-text icons.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
require("nvim-tree").setup({
  view = { side = "left", width = require("claude_layout").TREE_WIDTH, preserve_window_proportions = true },
  sync_root_with_cwd = true,
  update_focused_file = { enable = true },
  filters = { dotfiles = false, custom = { "^.git$", "^.DS_Store$" } },
  renderer = {
    group_empty = true,
    icons = {
      show = { file = false, folder = false, folder_arrow = true, git = true, modified = true },
      glyphs = {
        folder = { arrow_closed = "▸", arrow_open = "▾" },
        git = { unstaged = "M", staged = "S", unmerged = "U", renamed = "R", untracked = "?", deleted = "D", ignored = "·" },
        modified = "●",
      },
    },
  },
  actions = { open_file = { window_picker = { enable = false } } },
  on_attach = function(bufnr)
    local api = require("nvim-tree.api")
    api.config.mappings.default_on_attach(bufnr)
    -- Files open in the middle column, above Claude; folders expand as usual.
    local function open()
      local node = api.tree.get_node_under_cursor()
      if node and node.type == "file" then
        require("claude_layout").open_file(node.absolute_path)
      else
        api.node.open.edit()
      end
    end
    for _, lhs in ipairs({ "<CR>", "o", "<2-LeftMouse>" }) do
      vim.keymap.set("n", lhs, open, { buffer = bufnr, nowait = true, desc = "Open in middle column" })
    end
  end,
})

-- `nvim` with no file arguments opens the workspace layout (only with a screen:
-- `nvim --headless` checks and installs never start Claude).
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 and #vim.api.nvim_list_uis() > 0 then
      vim.schedule(require("claude_layout").open)
    end
  end,
})
