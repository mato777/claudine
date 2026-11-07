-- "This session needs you": a sound + a mark in the sessions sidebar.
--
-- Claude sessions started from Neovim load a hooks settings file generated at
-- startup (hooks_file() below, so paths fit any machine). The hooks run
-- bin/claude-attention when Claude
--   * stops and waits for your next message (Stop),
--   * shows a permission prompt or dialog (Notification),
--   * is about to ask you a question or approve a plan (AskUserQuestion / ExitPlanMode).
-- The script calls ping() here over Neovim's $NVIM socket.

local M = {}

M.sound = "/System/Library/Sounds/Glass.aiff" -- any file from /System/Library/Sounds
M.enabled = true

M.over_ssh = vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil

-- Write the hooks settings for Claude and return its path. Generated (not
-- checked in) so the script path is right on every machine.
function M.hooks_file()
  local script = vim.fn.stdpath("config") .. "/bin/claude-attention"
  local function hook(event)
    return { { type = "command", command = vim.fn.shellescape(script) .. " " .. event } }
  end
  local settings = {
    hooks = {
      Stop = { { hooks = hook("stop") } },
      Notification = { { hooks = hook("notification") } },
      PreToolUse = { { matcher = "AskUserQuestion|ExitPlanMode", hooks = hook("question") } },
    },
  }
  local path = vim.fn.stdpath("state") .. "/claude-hooks.json"
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(settings) }, path)
  return path
end

-- Glass sound on a local Mac; otherwise (SSH, Linux) the terminal bell, which
-- travels through SSH/tmux to Warp on your Mac.
function M.ring()
  if vim.fn.has("mac") == 1 and not M.over_ssh and vim.fn.executable("afplay") == 1 then
    pcall(vim.system, { "afplay", M.sound })
  else
    pcall(vim.api.nvim_ui_send, "\a")
  end
end
M.pending = {} -- session id -> event that needs you

local last_ring = {}

local function title_of(id)
  local ok, sessions = pcall(require, "claude_sessions")
  if not ok then
    return id
  end
  for _, e in ipairs(sessions.index(sessions.project_dir())) do
    if e.id == id then
      return e.title ~= "" and e.title or id
    end
  end
  return "New session"
end

local function refresh()
  local ok, sidebar = pcall(require, "claude_sidebar")
  if ok then
    sidebar.refresh()
  end
end

function M.ping(event, sid, ntype)
  vim.schedule(function()
    if ntype == "idle_prompt" then
      return -- Claude's "still waiting" reminder after a Stop: already rang
    end
    local L = require("claude_layout")
    if sid == "" or not L.state.terms[sid] then
      return
    end
    -- Mark it unless you're already in that session's window.
    local in_it = sid == L.state.current and vim.api.nvim_get_current_buf() == L.state.term_buf
    if not in_it then
      M.pending[sid] = event
      refresh()
      vim.notify("Claude needs you: " .. title_of(sid), vim.log.levels.WARN)
    end
    local now = vim.uv.now()
    if M.enabled and (not last_ring[sid] or now - last_ring[sid] > 3000) then -- one ring per burst
      last_ring[sid] = now
      M.ring()
    end
  end)
  return 0
end

function M.clear(id)
  if id and M.pending[id] then
    M.pending[id] = nil
    refresh()
  end
end

function M.toggle_sound()
  M.enabled = not M.enabled
  vim.notify("Claude attention sound " .. (M.enabled and "on" or "off"))
end

return M
