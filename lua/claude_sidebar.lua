-- Right sidebar: Claude sessions of this folder.
--   top:    sessions running in this Neovim (▶ = the one on screen)
--   ──────  separator
--   below:  history, newest first
--
--   Enter / double-click  show it in the middle (running: instant switch,
--                          history: resumes it, alongside the running ones)
--   n  new session      x  stop a running session    /  fuzzy search
--   g/ search inside    y  copy session id    r  refresh    q  close

local M = {}

local buf, win
local line_items = {} -- line number -> session entry
local ns = vim.api.nvim_create_namespace("claude_sidebar")

local function valid(w)
  return w and vim.api.nvim_win_is_valid(w)
end

local function entry_at_cursor()
  return line_items[vim.api.nvim_win_get_cursor(0)[1]]
end

local function first_entry_line()
  local best
  for lnum in pairs(line_items) do
    best = (not best or lnum < best) and lnum or best
  end
  return best
end

local function render()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local layout = require("claude_layout")
  local sessions = require("claude_sessions")
  local dir = sessions.project_dir()
  local history = vim.fn.isdirectory(dir) == 1 and sessions.index(dir) or {}
  local by_id = {}
  for _, e in ipairs(history) do
    by_id[e.id] = e
  end
  local width = valid(win) and vim.api.nvim_win_get_width(win) or 36
  local current = layout.state.current

  local lines, hls = {}, {}
  local function add(text, hl, item)
    table.insert(lines, vim.fn.strcharpart(text, 0, width - 1))
    if hl then
      hls[#lines] = hl
    end
    line_items[#lines] = item
  end
  line_items = {}

  local run = layout.running()
  add(" Claude sessions", "Title")
  add(" Enter switch · n new · ? help", "Comment")
  add("")
  local pending = require("claude_attention").pending
  local waiting = 0
  for _, t in ipairs(run) do
    waiting = waiting + (pending[t.id] and 1 or 0)
  end
  add(" Running (" .. #run .. ")" .. (waiting > 0 and (" · " .. waiting .. " need you") or ""), waiting > 0 and "WarningMsg" or "Title")
  local is_running = {}
  if #run == 0 then
    add("   none — Enter on one below", "Comment")
  end
  for _, t in ipairs(run) do
    is_running[t.id] = true
    local e = by_id[t.id]
    local title = e and e.title ~= "" and e.title or ("New session " .. os.date("%H:%M", t.started))
    local item = e or { id = t.id, title = title, mtime = t.started, prompts = {}, size = 0 }
    local mark = pending[t.id] and " ! " or (t.id == current and " ▶ " or " ● ")
    local hl = pending[t.id] and "WarningMsg" or (t.id == current and "Special" or "String")
    add(mark .. title, hl, item)
  end
  add(" " .. string.rep("─", width - 2), "WinSeparator")
  add(" History (" .. (#history - #vim.tbl_keys(is_running)) .. ")", "Title")
  for _, e in ipairs(history) do
    if not is_running[e.id] then
      add("   " .. os.date("%m-%d %H:%M", e.mtime) .. " " .. (e.title ~= "" and e.title or e.id), nil, e)
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for lnum, hl in pairs(hls) do
    vim.hl.range(buf, ns, hl, { lnum - 1, 0 }, { lnum - 1, -1 })
  end
  for lnum, e in pairs(line_items) do
    if not hls[lnum] then
      vim.hl.range(buf, ns, "Comment", { lnum - 1, 3 }, { lnum - 1, 14 }) -- the date
    end
  end
end
M.refresh = render

-- Move the cursor to the session on screen (or the first entry).
local function cursor_to_current()
  if not valid(win) then
    return
  end
  local current = require("claude_layout").state.current
  for lnum, e in pairs(line_items) do
    if e.id == current then
      return vim.api.nvim_win_set_cursor(win, { lnum, 0 })
    end
  end
  local first = first_entry_line()
  if first then
    vim.api.nvim_win_set_cursor(win, { first, 0 })
  end
end

local function map(lhs, fn, desc)
  vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
end

local function setup_buffer()
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "claude_sessions"
  vim.bo[buf].bufhidden = "hide"
  vim.api.nvim_buf_set_name(buf, "Claude sessions")

  local layout = function()
    return require("claude_layout")
  end
  local switch = function()
    local e = entry_at_cursor()
    if e then
      layout().resume(e.id)
    end
  end
  map("<CR>", switch, "Switch to session")
  map("<2-LeftMouse>", switch, "Switch to session")
  map("n", function()
    layout().new_session()
  end, "New session")
  map("x", function()
    local e = entry_at_cursor()
    if e then
      layout().stop(e.id, e.title)
    end
  end, "Stop running session")
  map("/", function()
    require("claude_sessions").pick()
  end, "Fuzzy search sessions")
  map("g/", function()
    require("claude_sessions").grep()
  end, "Search inside sessions")
  map("r", render, "Refresh")
  map("y", function()
    local e = entry_at_cursor()
    if e then
      vim.fn.setreg("+", e.id)
      vim.notify("Copied " .. e.id)
    end
  end, "Copy session id")
  map("q", M.close, "Close sidebar")
  map("?", function()
    vim.notify(table.concat({
      "Enter / double-click  show in the middle",
      "   !  = that session is waiting for you (it rang)",
      "   running: instant switch, history: resumes it",
      "n   new session",
      "x   stop a running session",
      "/   fuzzy search titles + prompts",
      "g/  search inside all sessions",
      "y   copy session id",
      "r   refresh",
      "q   close sidebar",
    }, "\n"), vim.log.levels.INFO, { title = "Claude sessions" })
  end, "Help")

  vim.api.nvim_create_autocmd("BufEnter", { buffer = buf, callback = render })
end

-- Refresh every 20 s while visible so new sessions and titles show up.
local timer
local function start_timer()
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  timer:start(20000, 20000, vim.schedule_wrap(function()
    if valid(win) then
      render()
    end
  end))
end

function M.open(width)
  if valid(win) then
    return
  end
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    setup_buffer()
  end
  local prev = vim.api.nvim_get_current_win()
  vim.cmd("botright vsplit")
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, width or 36)
  local wo = vim.wo[win]
  wo.winfixwidth = true
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.wrap = false
  wo.cursorline = true
  wo.spell = false
  render()
  cursor_to_current()
  if valid(prev) then
    vim.api.nvim_set_current_win(prev)
  end
  start_timer()
end

function M.focus()
  if not valid(win) then
    M.open()
  end
  vim.api.nvim_set_current_win(win)
  vim.cmd.stopinsert()
  render()
  cursor_to_current()
end

function M.close()
  if valid(win) then
    vim.api.nvim_win_close(win, false)
  end
  win = nil
end

function M.toggle()
  if valid(win) then
    M.close()
  else
    M.open()
  end
end

return M
