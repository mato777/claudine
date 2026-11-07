-- Three-column workspace:  [ file tree ] [ files above / Claude ] [ sessions ]
--
-- * The middle column shows one Claude session at a time. Several sessions can
--   run at once: each lives in its own terminal buffer, and switching only swaps
--   which buffer the middle column shows (nothing is stopped).
-- * Claude runs through a custom claudecode terminal provider, so it always lives
--   in that window (no plugin-managed splits).
-- * Files open in a split above Claude in the middle column.
-- * The right sidebar lists running sessions first, then this folder's history.

local M = {}

local SESSIONS_WIDTH = 36
local TREE_WIDTH = 34
local FILE_HEIGHT = 0.6 -- share of the middle column a file split takes

local state = {
  claude_win = nil, -- middle-column window that shows Claude
  file_win = nil, -- split above Claude for files
  terms = {}, -- session id -> { id, buf, job, started }
  order = {}, -- running session ids, in start order
  current = nil, -- session id shown in the middle column
  -- aliases for the current session (used by links, sidebar, tests)
  term_buf = nil,
  session_id = nil,
}
M.state = state

local function valid_win(w)
  return w and vim.api.nvim_win_is_valid(w)
end

local function valid_buf(b)
  return b and vim.api.nvim_buf_is_valid(b)
end

local function running(t)
  return t and t.job and vim.fn.jobwait({ t.job }, 0)[1] == -1
end

local function refresh_sidebar()
  local ok, sidebar = pcall(require, "claude_sidebar")
  if ok then
    sidebar.refresh()
  end
end

local function set_current(id)
  state.current = id
  state.session_id = id
  state.term_buf = id and state.terms[id] and state.terms[id].buf or nil
end

-- Running sessions, in start order.
function M.running()
  local out = {}
  for _, id in ipairs(state.order) do
    local t = state.terms[id]
    if running(t) then
      table.insert(out, t)
    end
  end
  return out
end

-- The window Claude should live in; recreated in the middle if it was closed.
local function claude_window()
  if valid_win(state.claude_win) then
    return state.claude_win
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
    if ft ~= "claude_sessions" and ft ~= "NvimTree" and vim.api.nvim_win_get_config(w).relative == "" then
      state.claude_win = w
      return w
    end
  end
  vim.cmd("vsplit")
  state.claude_win = vim.api.nvim_get_current_win()
  return state.claude_win
end

local function enter_terminal_mode()
  if vim.bo.buftype == "terminal" then
    vim.cmd.startinsert()
  end
end

local function show(id, focus)
  local t = state.terms[id]
  if not (t and valid_buf(t.buf)) then
    return
  end
  set_current(id)
  require("claude_attention").clear(id)
  local win = claude_window()
  vim.api.nvim_win_set_buf(win, t.buf)
  if focus then
    vim.api.nvim_set_current_win(win)
    enter_terminal_mode()
  end
  refresh_sidebar()
end

local function new_uuid()
  return vim.trim(vim.fn.system("uuidgen")):lower()
end

---------------------------------------------------------------------------
-- claudecode terminal provider
---------------------------------------------------------------------------
local provider = {}
M.provider = provider

function provider.setup() end

function provider.is_available()
  return true
end

-- claudecode sends selections / @-mentions to this buffer: the session on screen.
function provider.get_active_bufnr()
  local t = state.current and state.terms[state.current]
  return t and valid_buf(t.buf) and t.buf or nil
end

local function start(cmd_string, env_table, id, focus)
  local win = claude_window()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.api.nvim_win_set_buf(win, buf)
  local t = { id = id, buf = buf, started = os.time() }
  state.terms[id] = t
  table.insert(state.order, id)
  set_current(id)
  vim.api.nvim_win_call(win, function()
    t.job = vim.fn.jobstart(cmd_string, {
      term = true,
      env = env_table,
      cwd = vim.fn.getcwd(),
      on_exit = function()
        t.job = nil
        for i, x in ipairs(state.order) do
          if x == id then
            table.remove(state.order, i)
            break
          end
        end
        vim.schedule(refresh_sidebar)
      end,
    })
  end)
  vim.b[buf].claude_terminal = true
  vim.b[buf].claude_session_id = id
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    buffer = buf,
    callback = function()
      require("claude_attention").clear(id)
      vim.schedule(enter_terminal_mode) -- arriving in Claude = ready to type
    end,
  })
  if focus then
    vim.api.nvim_set_current_win(win)
    enter_terminal_mode()
  end
  refresh_sidebar()
end

-- cmd_string comes from claudecode: "<terminal_cmd> [args]". A --resume <id>
-- switches to (or starts) that session; no id means "the current session",
-- or a brand-new one with an id we choose (--session-id) so we can track it.
function provider.open(cmd_string, env_table, _, focus)
  focus = focus ~= false
  local id = cmd_string:match("%-%-resume[= ](%S+)") or cmd_string:match("%-%-session%-id[= ](%S+)")
  local force_new = cmd_string:find("--claude-layout-new", 1, true) ~= nil
  cmd_string = cmd_string:gsub("%s*%-%-claude%-layout%-new", "")

  if id and running(state.terms[id]) then
    return show(id, focus)
  end
  if not id and not force_new and running(state.terms[state.current]) then
    return show(state.current, focus)
  end
  if not id then
    id = new_uuid()
    cmd_string = cmd_string .. " --session-id " .. id
  end
  start(cmd_string, env_table, id, focus)
end

local function stop(id)
  local t = state.terms[id]
  if not t then
    return
  end
  if running(t) then
    vim.fn.jobstop(t.job)
    vim.wait(1000, function()
      return not running(t)
    end, 20)
  end
  state.terms[id] = nil
  for i, x in ipairs(state.order) do
    if x == id then
      table.remove(state.order, i)
      break
    end
  end
  if valid_buf(t.buf) then
    if valid_win(state.claude_win) and vim.api.nvim_win_get_buf(state.claude_win) == t.buf then
      -- keep the middle column: show another running session, or an empty buffer
      local next_t = M.running()[1]
      vim.api.nvim_win_set_buf(state.claude_win, next_t and next_t.buf or vim.api.nvim_create_buf(false, true))
      set_current(next_t and next_t.id or nil)
    end
    pcall(vim.api.nvim_buf_delete, t.buf, { force = true })
  end
  if state.current == id then
    set_current(nil)
  end
  refresh_sidebar()
end

-- claudecode's close: stop the session on screen.
function provider.close()
  if state.current then
    stop(state.current)
  end
end

-- In this layout Claude is always visible, so "toggle" means focus it / go back.
function provider.focus_toggle(cmd_string, env_table, config)
  local t = state.current and state.terms[state.current]
  -- a request for a specific / new session always opens it, never toggles away
  local targeted = cmd_string:find("--resume", 1, true) or cmd_string:find("--session-id", 1, true)
    or cmd_string:find("--claude-layout-new", 1, true)
  if not targeted and running(t) and vim.api.nvim_get_current_buf() == t.buf then
    vim.cmd("wincmd p")
    return
  end
  provider.open(cmd_string, env_table, config, true)
end
provider.simple_toggle = provider.focus_toggle
provider.toggle = provider.focus_toggle

function provider.ensure_visible()
  if state.current then
    show(state.current, false)
  end
end

---------------------------------------------------------------------------
-- Files: open in a split above Claude
---------------------------------------------------------------------------
function M.open_file(path, lnum)
  if not valid_win(state.file_win) then
    local cw = claude_window()
    vim.api.nvim_set_current_win(cw)
    vim.cmd("aboveleft split")
    state.file_win = vim.api.nvim_get_current_win()
    local total = vim.api.nvim_win_get_height(state.file_win) + vim.api.nvim_win_get_height(cw)
    vim.api.nvim_win_set_height(state.file_win, math.floor(total * FILE_HEIGHT))
  end
  vim.api.nvim_set_current_win(state.file_win)
  vim.cmd.edit(vim.fn.fnameescape(path))
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
  end
end

---------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------
-- Show a session in the middle column: instant if it's running, otherwise it
-- starts (resumed) next to the ones already running.
function M.resume(id)
  if running(state.terms[id]) then
    return show(id, true)
  end
  vim.cmd("ClaudeCode --resume " .. id)
end

function M.new_session()
  vim.cmd("ClaudeCode --claude-layout-new")
end

-- Stop a running session (it stays in the history and can be resumed later).
function M.stop(id, title)
  local t = state.terms[id]
  if not running(t) then
    return
  end
  local label = title and ('"' .. title .. '"') or id
  if vim.fn.confirm("Stop Claude session " .. label .. "?\nIt stays in the list below and can be resumed later.", "&Stop\n&Cancel", 2) == 1 then
    stop(id)
  end
end

-- Put the cursor in Claude (the session on screen), ready to type.
function M.focus_claude()
  if state.current and running(state.terms[state.current]) then
    return show(state.current, true)
  end
  vim.cmd("ClaudeCode")
end

---------------------------------------------------------------------------
-- Shell: a terminal in the project folder, below Claude in the middle column
---------------------------------------------------------------------------
local SHELL_HEIGHT = 0.3
local shell = { buf = nil, win = nil }
M.shell = shell

-- Option+t: open/focus the shell (ready to type or paste); again while in it:
-- hide it and return to Claude. The shell keeps running while hidden.
function M.toggle_shell()
  if valid_win(shell.win) and vim.api.nvim_get_current_win() == shell.win then
    vim.api.nvim_win_hide(shell.win)
    shell.win = nil
    return M.focus_claude()
  end
  if not valid_win(shell.win) then
    local cw = claude_window()
    local total = vim.api.nvim_win_get_height(cw)
    vim.api.nvim_set_current_win(cw)
    vim.cmd("belowright split")
    shell.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_height(shell.win, math.max(6, math.floor(total * SHELL_HEIGHT)))
    vim.wo[shell.win].winfixheight = true
  end
  vim.api.nvim_set_current_win(shell.win)
  if valid_buf(shell.buf) and vim.bo[shell.buf].channel > 0 then
    vim.api.nvim_win_set_buf(shell.win, shell.buf)
  else
    shell.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[shell.buf].bufhidden = "hide"
    vim.api.nvim_win_set_buf(shell.win, shell.buf)
    local buf = shell.buf
    vim.fn.jobstart(vim.o.shell, {
      term = true,
      cwd = vim.fn.getcwd(),
      on_exit = function()
        vim.schedule(function()
          -- `exit` in the shell: close it; Option+t starts a fresh one
          if valid_win(shell.win) and vim.api.nvim_win_get_buf(shell.win) == buf then
            pcall(vim.api.nvim_win_close, shell.win, true)
          end
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
          if shell.buf == buf then
            shell.buf, shell.win = nil, nil
          end
        end)
      end,
    })
    vim.api.nvim_buf_set_name(shell.buf, "Shell: " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":~"))
    vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
      buffer = shell.buf,
      callback = function()
        vim.schedule(enter_terminal_mode)
      end,
    })
  end
  enter_terminal_mode()
end

---------------------------------------------------------------------------
-- Build the layout
---------------------------------------------------------------------------
function M.open()
  local cw = claude_window()
  vim.api.nvim_set_current_win(cw)

  require("claude_sidebar").open(SESSIONS_WIDTH)

  local tree = require("nvim-tree.api").tree
  if not tree.is_visible() then
    tree.open({ focus = false })
  end

  vim.api.nvim_set_current_win(state.claude_win)
  vim.cmd("ClaudeCode")
end

M.TREE_WIDTH = TREE_WIDTH

return M
