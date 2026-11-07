-- Browse and resume the Claude Code sessions of the current folder.
-- Sessions live in ~/.claude/projects/<cwd with non-alphanumerics as "-">/<id>.jsonl.
-- Files can be 100+ MB, so only the first and last 256 KB are read, and the
-- result is cached by (mtime, size).

local M = {}

local CHUNK = 256 * 1024
local MAX_PROMPTS = 20
local CACHE = vim.fn.stdpath("cache") .. "/claude-sessions.json"
local JSON_OPTS = { luanil = { object = true, array = true } }

function M.project_dir(cwd)
  local encoded = (cwd or vim.fn.getcwd()):gsub("[^%w]", "-")
  return vim.fn.expand("~/.claude/projects/") .. encoded
end

local function read_cache()
  local f = io.open(CACHE, "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read("*a"), JSON_OPTS)
  f:close()
  return ok and type(data) == "table" and data or {}
end

local function write_cache(data)
  local f = io.open(CACHE, "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

local function prompt_text(d)
  if d.type ~= "user" or d.isMeta == true or d.isSidechain == true then
    return
  end
  local c = d.message and d.message.content
  local t
  if type(c) == "string" then
    t = c
  elseif type(c) == "table" then
    for _, part in ipairs(c) do
      if part.type == "text" then
        t = part.text
        break
      end
    end
  end
  if not t or t:match("^%s*<") or t:match("^Caveat:") then
    return
  end
  return vim.trim(t)
end

local function scan(chunk, acc)
  for line in chunk:gmatch("[^\n]+") do
    local is_user = line:find('"type":"user"', 1, true)
    local is_title = line:find('"customTitle"', 1, true) or line:find('"aiTitle"', 1, true)
    if is_user or is_title then
      local ok, d = pcall(vim.json.decode, line, JSON_OPTS)
      if ok and type(d) == "table" then
        if d.customTitle then
          acc.custom = d.customTitle
        elseif d.aiTitle then
          acc.ai = d.aiTitle
        else
          local t = prompt_text(d)
          if t and #acc.prompts < MAX_PROMPTS then
            table.insert(acc.prompts, t)
          end
        end
      end
    end
  end
end

local function index_file(path, stat)
  local f = io.open(path, "rb")
  if not f then
    return
  end
  local acc = { prompts = {} }
  scan(f:read(CHUNK) or "", acc)
  if stat.size > CHUNK then
    f:seek("set", math.max(CHUNK, stat.size - CHUNK))
    scan(f:read("*a") or "", acc) -- picks up the latest title
  end
  f:close()
  local first = acc.prompts[1] or ""
  return {
    id = vim.fn.fnamemodify(path, ":t:r"),
    file = path,
    mtime = stat.mtime.sec,
    size = stat.size,
    prompts = acc.prompts,
    title = acc.custom or acc.ai or first:gsub("%s+", " "):sub(1, 80),
  }
end

-- All sessions of `dir`, newest first.
function M.index(dir)
  local cache, out, changed = read_cache(), {}, false
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:match("%.jsonl$") then
      local path = dir .. "/" .. name
      local stat = vim.uv.fs_stat(path)
      if stat then
        local e = cache[path]
        if not (e and e.mtime == stat.mtime.sec and e.size == stat.size) then
          e = index_file(path, stat)
          cache[path] = e
          changed = true
        end
        if e and (e.title ~= "" or #e.prompts > 0) then
          table.insert(out, e)
        end
      end
    end
  end
  if changed then
    write_cache(cache)
  end
  table.sort(out, function(a, b)
    return a.mtime > b.mtime
  end)
  return out
end

function M.preview_lines(e)
  local lines = {
    "# " .. (e.title ~= "" and e.title or e.id),
    "",
    ("`%s` · %s · %.1f MB"):format(e.id, os.date("%Y-%m-%d %H:%M", e.mtime), e.size / 1048576),
    "",
  }
  for i, p in ipairs(e.prompts) do
    table.insert(lines, ("## Prompt %d"):format(i))
    table.insert(lines, "")
    vim.list_extend(lines, vim.split(p:sub(1, 1500), "\n"))
    table.insert(lines, "")
  end
  return lines
end

function M.resume(id)
  require("claude_layout").resume(id)
end

local function session_previewer(lookup)
  local previewers = require("telescope.previewers")
  return previewers.new_buffer_previewer({
    title = "Session",
    define_preview = function(self, entry)
      local e = lookup(entry)
      local lines = e and M.preview_lines(e) or { "(no preview)" }
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.bo[self.state.bufnr].filetype = "markdown"
      vim.wo[self.state.winid].wrap = true
    end,
  })
end

local function attach(get_id)
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  return function(bufnr, map)
    actions.select_default:replace(function()
      local sel = state.get_selected_entry()
      actions.close(bufnr)
      if sel then
        M.resume(get_id(sel))
      end
    end)
    map({ "i", "n" }, "<C-y>", function()
      local sel = state.get_selected_entry()
      if sel then
        vim.fn.setreg("+", get_id(sel))
        vim.notify("Copied session id " .. get_id(sel))
      end
    end)
    return true
  end
end

local function require_dir()
  local dir = M.project_dir()
  if vim.fn.isdirectory(dir) == 0 then
    vim.notify("No Claude sessions for " .. vim.fn.getcwd(), vim.log.levels.WARN)
    return
  end
  return dir
end

-- <leader>cr: fuzzy-find sessions by title and prompts, Enter resumes.
function M.pick()
  local dir = require_dir()
  if not dir then
    return
  end
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values

  pickers
    .new({}, {
      prompt_title = "Claude sessions  (Enter resume · Ctrl-y copy id)",
      finder = finders.new_table({
        results = M.index(dir),
        entry_maker = function(e)
          return {
            value = e,
            display = os.date("%m-%d %H:%M", e.mtime) .. "  " .. e.title,
            ordinal = (e.title .. " " .. table.concat(e.prompts, " ")):sub(1, 3000),
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = session_previewer(function(entry)
        return entry.value
      end),
      attach_mappings = attach(function(sel)
        return sel.value.id
      end),
    })
    :find()
end

-- <leader>c/: ripgrep through the full session transcripts, Enter resumes.
function M.grep()
  local dir = require_dir()
  if not dir then
    return
  end
  local by_id = {}
  for _, e in ipairs(M.index(dir)) do
    by_id[e.id] = e
  end
  local make_entry = require("telescope.make_entry")
  local base = make_entry.gen_from_vimgrep({})
  local id_of = function(entry)
    return vim.fn.fnamemodify(entry.filename, ":t:r")
  end

  require("telescope.builtin").live_grep({
    prompt_title = "Search inside Claude sessions",
    search_dirs = { dir },
    glob_pattern = "*.jsonl",
    additional_args = { "--max-depth", "1", "--fixed-strings", "-M", "300", "--max-columns-preview" },
    entry_maker = function(line)
      local entry = base(line)
      if not entry then
        return
      end
      local e = by_id[id_of(entry)]
      entry.display = (e and e.title or id_of(entry)) .. "  │ " .. vim.trim(entry.text or ""):sub(1, 160)
      return entry
    end,
    previewer = session_previewer(function(entry)
      return by_id[id_of(entry)]
    end),
    attach_mappings = attach(id_of),
  })
end

return M
