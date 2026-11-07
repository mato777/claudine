local map = vim.keymap.set
local tb = function(name, opts)
  return function()
    require("telescope.builtin")[name](opts or {})
  end
end
local sessions = function(fn)
  return function()
    require("claude_sessions")[fn]()
  end
end

-- Files (Telescope)
map("n", "<leader>ff", tb("find_files"), { desc = "Find files" })
map("n", "<leader>fg", tb("live_grep"), { desc = "Grep in project" })
map("n", "<leader>fb", tb("buffers"), { desc = "Open buffers" })
map("n", "<leader>fr", tb("oldfiles", { only_cwd = true }), { desc = "Recent files" })
map("n", "<leader>fh", tb("help_tags"), { desc = "Help" })
map("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle file tree" })
map("n", "<leader>E", "<cmd>NvimTreeFindFile<cr>", { desc = "Reveal current file in tree" })

-- Layout: [tree] [files / Claude] [sessions]
map("n", "<leader>cl", function()
  require("claude_layout").open()
end, { desc = "Open Claude workspace layout" })
map("n", "<leader>cS", function()
  require("claude_sidebar").toggle()
end, { desc = "Toggle sessions sidebar" })
map("n", "<leader>cn", function()
  require("claude_layout").new_session()
end, { desc = "New Claude session" })

-- Jump between columns, from anywhere (also while typing in Claude):
-- Option+1 sessions · Option+2 Claude · Option+3 file tree · Option+4 open file
local jump = {
  function()
    require("claude_sidebar").focus()
  end,
  function()
    vim.cmd("ClaudeCodeFocus")
  end,
  function()
    vim.cmd.stopinsert()
    require("nvim-tree.api").tree.open({ focus = true })
  end,
  function()
    local w = require("claude_layout").state.file_win
    if w and vim.api.nvim_win_is_valid(w) then
      vim.cmd.stopinsert()
      vim.api.nvim_set_current_win(w)
    end
  end,
}
for i, fn in ipairs(jump) do
  map("n", "<leader>" .. i, fn, { desc = "Jump to column " .. i })
end

-- Move between windows with Option+h/j/k/l, also while typing in Claude.
for _, k in ipairs({ "h", "j", "k", "l" }) do
  map({ "n", "t" }, "<M-" .. k .. ">", "<Cmd>wincmd " .. k .. "<CR>", { desc = "Window " .. k })
end

-- Option+1 file tree · Option+2 sessions (Command+1/2 too, where the terminal
-- forwards Command keys), also while typing in Claude:
--   first press: show the column (if hidden) and put the cursor in it;
--   press again while in it: hide it and return to Claude.
local function back_to_claude()
  require("claude_layout").focus_claude()
end
local toggle_tree = function()
  local tree = require("nvim-tree.api").tree
  if vim.bo.filetype == "NvimTree" then
    tree.close()
    back_to_claude()
  else
    vim.cmd.stopinsert()
    tree.open({ focus = true })
  end
end
local toggle_sessions = function()
  local sidebar = require("claude_sidebar")
  if vim.bo.filetype == "claude_sessions" then
    sidebar.close()
    back_to_claude()
  else
    sidebar.focus()
  end
end
for _, lhs in ipairs({ "<M-1>", "<D-1>" }) do
  map({ "n", "t" }, lhs, toggle_tree, { desc = "Toggle file tree" })
end
for _, lhs in ipairs({ "<M-2>", "<D-2>" }) do
  map({ "n", "t" }, lhs, toggle_sessions, { desc = "Toggle sessions sidebar" })
end

-- Option+t: shell in the project folder below Claude; again: hide it, back to Claude.
map({ "n", "t" }, "<M-t>", function()
  require("claude_layout").toggle_shell()
end, { desc = "Toggle shell terminal" })

-- Session search in a centered popup, also while typing in Claude:
-- Option+s by title/prompts · Option+g inside the full conversations.
map({ "n", "t" }, "<M-s>", sessions("pick"), { desc = "Find a Claude session" })
map({ "n", "t" }, "<M-g>", sessions("grep"), { desc = "Search inside Claude sessions" })

-- Claude
map("n", "<leader>cc", "<cmd>ClaudeCode<cr>", { desc = "Focus Claude / go back" })
map("n", "<leader>cf", "<cmd>ClaudeCodeFocus<cr>", { desc = "Focus Claude" })
map("n", "<leader>cr", sessions("pick"), { desc = "Claude sessions (resume)" })
map("n", "<leader>c/", sessions("grep"), { desc = "Search inside Claude sessions" })
map("n", "<leader>cb", "<cmd>ClaudeCodeAdd %<cr>", { desc = "Add current file to Claude" })
map("v", "<leader>cs", "<cmd>ClaudeCodeSend<cr>", { desc = "Send selection to Claude" })
map("n", "<leader>ca", "<cmd>ClaudeCodeDiffAccept<cr>", { desc = "Accept Claude diff" })
map("n", "<leader>cd", "<cmd>ClaudeCodeDiffDeny<cr>", { desc = "Reject Claude diff" })

-- Links: gf / gF open the path under the cursor (path:line works), also from the
-- Claude terminal; <leader>o opens it with the macOS default app.
local term = require("config.term")
term.setup_typing_guard()
map("n", "gf", term.open_link, { desc = "Open file under cursor" })
map("n", "gF", term.open_link, { desc = "Open file:line under cursor" })
-- Option+o: list the files, images, folders and URLs Claude mentioned; Enter opens one.
map({ "n", "t" }, "<M-o>", term.pick_links, { desc = "Open a link Claude mentioned" })
-- Double-click a path, folder or URL in Claude's output to open it.
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function(ev)
    map({ "n", "t" }, "<2-LeftMouse>", function()
      local pos = vim.fn.getmousepos()
      if pos.winid ~= 0 and pos.line > 0 then
        vim.api.nvim_set_current_win(pos.winid)
        pcall(vim.api.nvim_win_set_cursor, pos.winid, { pos.line, math.max(pos.column - 1, 0) })
        term.open_link()
      end
    end, { buffer = ev.buf, desc = "Open path under mouse" })
  end,
})
map("n", "<leader>o", function()
  vim.ui.open(vim.fn.fnamemodify(vim.fn.expand("<cfile>"), ":p"))
end, { desc = "Open with default app" })

-- Windows
for _, k in ipairs({ "h", "j", "k", "l" }) do
  map("n", "<C-" .. k .. ">", "<C-w>" .. k)
end

-- Resize the current split (works inside the Claude terminal too).
-- Alt+Left/Right = narrower/wider, Alt+Up/Down = taller/shorter; Alt+= equalizes.
local resize = {
  ["<M-Left>"] = "vertical resize -5",
  ["<M-Right>"] = "vertical resize +5",
  ["<M-Up>"] = "resize +3",
  ["<M-Down>"] = "resize -3",
  ["<M-=>"] = "wincmd =",
}
for lhs, cmd in pairs(resize) do
  map({ "n", "t" }, lhs, "<cmd>" .. cmd .. "<cr>", { desc = cmd })
end

-- Attention sound (a session needs you): :ClaudeSound toggles it.
vim.api.nvim_create_user_command("ClaudeSound", function()
  require("claude_attention").toggle_sound()
end, { desc = "Toggle the 'Claude needs you' sound" })
