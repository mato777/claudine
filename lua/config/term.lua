local M = {}

-- True when the terminal speaks the kitty graphics protocol (Ghostty, kitty, WezTerm),
-- which snacks.image needs to draw images inside Neovim.
function M.has_images()
  local e = vim.env
  local term, prog = e.TERM or "", e.TERM_PROGRAM or ""
  return e.KITTY_WINDOW_ID ~= nil
    or e.GHOSTTY_RESOURCES_DIR ~= nil
    or e.WEZTERM_PANE ~= nil
    or term:match("kitty") ~= nil
    or term:match("ghostty") ~= nil
    or prog == "ghostty"
    or prog == "WezTerm"
end

local IMAGE_EXT = { png = true, jpg = true, jpeg = true, gif = true, webp = true, bmp = true, svg = true }

-- First normal (non-terminal, non-floating) window in the tab, if any.
local function editor_window()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].buftype == "" and vim.api.nvim_win_get_config(w).relative == "" then
      return w
    end
  end
end

-- Open a link target: URLs in the browser, images in macOS Preview when the
-- terminal can't draw them, folders in a file finder, files above Claude.
local function classify(path)
  if path:match("^https?://") then
    return "url"
  end
  if vim.fn.isdirectory(path) == 1 then
    return "dir"
  end
  local ext = (path:match("%.([%w]+)$") or ""):lower()
  return IMAGE_EXT[ext] and "image" or "file"
end
M.classify = classify

local over_ssh = vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil

function M.open_path(path, lnum)
  local kind = classify(path)
  if kind == "url" or (kind == "image" and not M.has_images()) then
    if over_ssh then
      -- a browser/Preview would open on the server: copy it to your Mac instead
      vim.fn.setreg("+", path)
      return vim.notify("Copied to your clipboard: " .. path)
    end
    return vim.ui.open(path)
  end
  if kind == "dir" then
    return require("telescope.builtin").find_files({ cwd = path, prompt_title = "Files in " .. vim.fn.fnamemodify(path, ":~:.") })
  end
  if vim.bo.buftype ~= "" then
    return require("claude_layout").open_file(path, lnum)
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
  end
end

-- Turn one token of Claude's output into a link, or nil.
-- Accepts URLs, file:// links, ~/x, /abs/x, rel/x, name.ext, with optional :line.
local function to_link(token, cwd)
  token = token:gsub("^[%(%[<\"'`]+", ""):gsub("[%.,;:!%?%)%]>\"'`]+$", "")
  if token:match("^https?://") then
    return #token > 10 and { kind = "url", path = token, rel = token } or nil
  end
  token = token:gsub("^file://", "")
  local lnum
  local base, num = token:match("^(.-):(%d+)$")
  if base then
    token, lnum = base, tonumber(num)
  end
  base = token:match("^(.-):%d+:%d+$") or token:match("^(.-):%d+$")
  token = base or token
  -- a bare word only counts if it looks like a file name (has an extension)
  if #token < 3 or not (token:find("/", 1, true) or token:match("%.%w+$")) then
    return
  end
  local abs = vim.fn.fnamemodify(vim.fn.expand(token), ":p"):gsub("/$", "")
  if vim.fn.filereadable(abs) == 0 and vim.fn.isdirectory(abs) == 0 then
    return
  end
  local rel = abs:sub(1, #cwd + 1) == cwd .. "/" and abs:sub(#cwd + 2) or vim.fn.fnamemodify(abs, ":~")
  return { kind = classify(abs), path = abs, rel = rel, lnum = lnum }
end

-- Open the path, folder or URL under the cursor; honours path:line.
function M.open_link()
  local link = to_link(vim.fn.expand("<cWORD>"), vim.fn.getcwd()) or to_link(vim.fn.expand("<cfile>"), vim.fn.getcwd())
  if not link then
    vim.notify("No file, folder or URL under the cursor", vim.log.levels.WARN)
    return
  end
  M.open_path(link.path, link.lnum)
end

-- Every link Claude printed (newest first): files (docs/plan.md, src/a.ts:42),
-- images, folders and URLs. Lines the terminal hard-wrapped are joined first so
-- long paths and URLs survive.
local SCAN_LINES = 3000
function M.claude_links()
  local buf = require("claude_layout").state.term_buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return {}
  end
  local n = vim.api.nvim_buf_line_count(buf)
  local raw = vim.api.nvim_buf_get_lines(buf, math.max(0, n - SCAN_LINES), n, false)
  local width = 0
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    width = math.max(width, vim.api.nvim_win_get_width(w))
  end

  local lines, cur = {}, ""
  for _, l in ipairs(raw) do
    cur = cur .. l
    if width == 0 or vim.fn.strdisplaywidth(l) < width then
      table.insert(lines, cur)
      cur = ""
    end
  end
  if cur ~= "" then
    table.insert(lines, cur)
  end

  local seen, out, cwd = {}, {}, vim.fn.getcwd()
  for i = #lines, 1, -1 do
    local found = {}
    for token in lines[i]:gmatch("[^%s|│┃]+") do
      local link = to_link(token, cwd)
      if link and not seen[link.path] then
        seen[link.path] = true
        table.insert(found, link)
      end
    end
    vim.list_extend(out, found)
  end
  return out
end

local TAG = { file = "file ", image = "image", dir = "dir  ", url = "url  " }

-- Option+o: pick a file, image, folder or URL Claude mentioned and open it.
function M.pick_links()
  local links = M.claude_links()
  if #links == 0 then
    vim.notify("No files, folders or URLs in Claude's output yet", vim.log.levels.INFO)
    return
  end
  vim.cmd.stopinsert()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local previewers = require("telescope.previewers")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")

  local previewer = previewers.new_buffer_previewer({
    title = "Preview",
    define_preview = function(self, entry)
      local l, b = entry.value, self.state.bufnr
      if l.kind == "file" then
        conf.buffer_previewer_maker(l.path, b, { bufname = self.state.bufname })
      elseif l.kind == "dir" then
        local names = {}
        for name, t in vim.fs.dir(l.path) do
          table.insert(names, name .. (t == "directory" and "/" or ""))
        end
        table.sort(names)
        vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.list_extend({ l.rel, "", "Enter: find files in this folder", "" }, names))
      else
        local how = l.kind == "url" and "Enter: open in the browser" or (M.has_images() and "Enter: open in Neovim" or "Enter: open in Preview")
        vim.api.nvim_buf_set_lines(b, 0, -1, false, { l.path, "", how })
      end
    end,
  })

  pickers
    .new({}, {
      prompt_title = "Links Claude mentioned (newest first)",
      finder = finders.new_table({
        results = links,
        entry_maker = function(l)
          return {
            value = l,
            display = TAG[l.kind] .. "  " .. l.rel .. (l.lnum and (":" .. l.lnum) or ""),
            ordinal = l.kind .. " " .. l.rel,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewer,
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local sel = state.get_selected_entry()
          actions.close(bufnr)
          if sel then
            vim.schedule(function()
              -- open from Claude's column so files land above Claude
              local cw = require("claude_layout").state.claude_win
              if cw and vim.api.nvim_win_is_valid(cw) then
                vim.api.nvim_set_current_win(cw)
              end
              M.open_path(sel.value.path, sel.value.lnum)
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

-- Typing guard for terminal splits (the Claude window).
-- Claude Code doesn't request mouse events, so Neovim drops out of terminal mode
-- whenever you click or scroll in its window; the next keys you type would then
-- run as Vim commands (Space = leader, gf opens files, ...). After such a mouse
-- exit, the first text key goes back to Claude instead, and you return to typing.
-- Press Esc after scrolling if you really want Vim keys there (e.g. gf on a path).
local MOUSE = {}
for _, k in ipairs({
  "LeftMouse", "LeftDrag", "LeftRelease", "RightMouse", "RightDrag", "RightRelease",
  "MiddleMouse", "MiddleDrag", "MiddleRelease", "2-LeftMouse", "3-LeftMouse",
  "ScrollWheelUp", "ScrollWheelDown", "ScrollWheelLeft", "ScrollWheelRight",
}) do
  MOUSE[vim.keycode("<" .. k .. ">")] = true
end
local ESC = vim.keycode("<Esc>")

function M.setup_typing_guard()
  local after_mouse = false
  local ns = vim.api.nvim_create_namespace("claude_typing_guard")

  vim.on_key(function(_, typed)
    if not typed or typed == "" then
      return
    end
    if MOUSE[typed] then
      after_mouse = true
      return
    end
    local in_term_normal = vim.api.nvim_get_mode().mode == "nt" and vim.bo.buftype == "terminal"
    if not (after_mouse and in_term_normal) then
      after_mouse = false
      return
    end
    if typed == ESC then
      after_mouse = false -- explicit: stay in Vim mode
      return
    end
    -- Plain text, Enter, Tab or Backspace: send it to the program, resume typing.
    local bytes = typed == vim.keycode("<BS>") and "\127" or typed
    if bytes:byte(1) == 0x80 then
      return -- other special keys (arrows, F-keys): leave to Vim
    end
    local chan = vim.bo.channel
    vim.schedule(function()
      if chan and chan > 0 then
        pcall(vim.api.nvim_chan_send, chan, bytes)
      end
      if vim.bo.buftype == "terminal" and vim.api.nvim_get_mode().mode == "nt" then
        vim.cmd.startinsert()
      end
    end)
    return "" -- swallow the key in Vim
  end, ns)

  vim.api.nvim_create_autocmd("TermEnter", {
    callback = function()
      after_mouse = false
    end,
  })
end

return M
