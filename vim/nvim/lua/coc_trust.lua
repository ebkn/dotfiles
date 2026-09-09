-- Workspace-trust gate for coc.nvim's folder configuration.
--
-- Why this exists: coc.nvim reads `<folder>/.vim/coc-settings.json` and lets it
-- override user configuration, with no trust prompt. It has no workspace-trust
-- model at all -- `trust`, `isTrusted` and `workspaceTrust` appear nowhere in
-- the bundle outside unrelated markdown rendering. A `languageserver` entry in
-- that file is `{command, args, filetypes}`, i.e. an arbitrary executable with
-- arbitrary argv: `registerClientsFromFolder` passes it to
-- `registerClientsByConfig`, whose only validation is a type check, and it
-- reaches `child_process.spawn`. The default `workspace.rootPatterns` includes
-- `.git`, so every cloned repository resolves as a workspace folder. That makes
-- `git clone && nvim README.md` -- opening a file merely to read it -- enough to
-- execute a hostile repository's code. It is exactly the threat that editor
-- workspace trust (VS Code's, and Neovim's own `exrc`/`secure`) exists to stop.
--
-- Why the gate is "don't start coc": there is no coc setting that disables
-- folder configuration; the whole config schema was searched for one. The
-- documented off-switch is `g:coc_start_at_startup = 0`, with `:CocStart` as the
-- deliberate opt-in once you have read the offending file. Note that lazy-loading
-- coc by filetype would NOT help: the attacker chooses `filetypes`.
--
-- Two loading paths in coc, and this module mirrors both:
--   1. at construction, the config file of `cwd` itself
--   2. per document, `findUp('.vim', <file path>)` -- ANY ancestor of an opened
--      file, not just the git root
-- `$HOME` is skipped here because coc skips it too (`folderToConfigfile` returns
-- undefined for it), so `~/.vim/coc-settings.json` is a user config, not a
-- folder config, and must not be reported.
--
-- Trust is a per-machine decision about directories that exist on that machine,
-- so the list lives under stdpath("state") and is deliberately not version
-- controlled.

local M = {}

local CONFIG_RELATIVE = ".vim/coc-settings.json"

local function trust_file()
  return vim.fs.joinpath(vim.fn.stdpath("state"), "coc-trusted-folders")
end

-- Absolute, symlink-resolved, no trailing slash, so that a path compares equal
-- however the user spelled it.
local function normalize(dir)
  if dir == nil or dir == "" then
    return nil
  end
  -- Never vim.fn.expand() here. It treats its argument as a wildcard pattern and
  -- applies 'wildignore', which this config sets to `*/tmp*,*.so,*.swp,*.zip` --
  -- so expand() returns an EMPTY STRING for any path under a tmp directory, and
  -- the gate silently passes every repository whose path matches. fnamemodify's
  -- :p does the only expansion wanted here (a leading ~) and ignores wildcards.
  local full = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.fnamemodify(dir, ":p")), ":p")
  -- Strip the trailing slash only when something is left. Reducing "/" to ""
  -- would make vim.fs.joinpath build a *relative* path, which fs_stat then
  -- resolves against the current directory -- so walking up to the filesystem
  -- root would report cwd's own .vim/coc-settings.json as an ancestor's.
  local trimmed = full:gsub("/+$", "")
  return trimmed ~= "" and trimmed or "/"
end

local function exists(path)
  return (vim.uv or vim.loop).fs_stat(path) ~= nil
end

--- The folder config path coc would read for `dir`, or nil when there is none.
function M.folder_config(dir)
  if dir == nil or dir == normalize(vim.env.HOME) then
    return nil
  end
  local path = vim.fs.joinpath(dir, CONFIG_RELATIVE)
  return exists(path) and path or nil
end

function M.trusted_folders()
  local set = {}
  local f = io.open(trust_file(), "r")
  if not f then
    return set
  end
  for line in f:lines() do
    local entry = vim.trim(line)
    if entry ~= "" and not entry:match("^#") then
      local dir = normalize(entry)
      if dir then
        set[dir] = true
      end
    end
  end
  f:close()
  return set
end

--- Walk up from `start_dir` and return the first ancestor that carries a folder
--- config this machine has not trusted, as { dir = ..., config = ... }.
function M.find_untrusted(start_dir)
  local dir = normalize(start_dir)
  if not dir then
    return nil
  end
  local trusted = M.trusted_folders()
  -- The directory itself first, then every ancestor: coc's findUp does the same,
  -- and the nearest one is the one worth naming in the warning.
  local candidates = { dir }
  for parent in vim.fs.parents(dir) do
    candidates[#candidates + 1] = normalize(parent)
  end
  for _, candidate in ipairs(candidates) do
    local config = M.folder_config(candidate)
    if config and not trusted[candidate] then
      return { dir = candidate, config = config }
    end
  end
  return nil
end

function M.trust(dir)
  local target = normalize(dir or vim.fn.getcwd())
  if not target then
    return
  end
  if M.trusted_folders()[target] then
    vim.notify("coc: already trusted: " .. target, vim.log.levels.INFO)
    return
  end
  local path = trust_file()
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f, err = io.open(path, "a")
  if not f then
    vim.notify("coc: cannot write " .. path .. ": " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  f:write(target .. "\n")
  f:close()
  vim.notify("coc: trusted " .. target .. "\nRun :CocStart to start the service.", vim.log.levels.INFO)
end

-- Folders already reported, so the startup gate and the buffer watcher do not
-- warn twice about the same one.
local warned = {}

local function coc_running()
  return vim.fn.exists("*coc#rpc#started") == 1 and vim.fn["coc#rpc#started"]() == 1
end

local function warn(found, running)
  warned[found.dir] = true
  local lines = {
    "coc.nvim: untrusted folder configuration found",
    "  " .. found.config,
    "",
    "It can name an arbitrary program to run via `languageserver`, and coc",
    "applies it with no trust prompt of its own.",
    "",
  }
  if running then
    -- Reached through the per-buffer path, so coc is already up and a server may
    -- already have been registered. Say so plainly rather than implying it was
    -- prevented.
    lines[#lines + 1] = "coc is ALREADY RUNNING -- read the file, then :CocRestart if it is fine."
  else
    lines[#lines + 1] = "coc was not started. Read the file, then either:"
    lines[#lines + 1] = "  :CocStart              start once, without trusting"
    lines[#lines + 1] = "  :CocTrustFolder        trust " .. found.dir .. " permanently"
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)
end

--- Decide whether coc may start. Must run BEFORE coc.nvim is sourced -- both of
--- its autostart points (`plugin/coc.vim` at source time and its VimEnter
--- handler) read `g:coc_start_at_startup`, so a lazy.nvim `config` hook is too
--- late and only `init` works.
function M.gate_startup()
  local found = M.find_untrusted(vim.fn.getcwd())
  if not found then
    return
  end
  vim.g.coc_start_at_startup = 0
  -- getcwd() is available this early but the UI is not, so defer the message or
  -- it scrolls past before the first screen is drawn.
  vim.schedule(function()
    warn(found, false)
  end)
end

--- Catch the folder configs the startup gate cannot see: coc resolves a folder
--- per document via findUp from the file, so a file opened outside cwd -- or in
--- a subdirectory carrying its own `.vim/` -- brings in a config of its own.
--- This can only report, not prevent: by the time a buffer is read, coc has
--- either been gated off (and nothing happens) or is already running.
function M.watch_buffers()
  vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
    group = vim.api.nvim_create_augroup("CocTrustWatch", { clear = true }),
    callback = function(args)
      -- Only meaningful while coc is actually up: a stopped coc reads no folder
      -- config, so there is nothing to report. Ask the service rather than
      -- inferring from g:coc_start_at_startup, which stays 0 after a :CocStart.
      if not coc_running() then
        return
      end
      local name = args.file
      if name == nil or name == "" then
        return
      end
      local found = M.find_untrusted(vim.fs.dirname(vim.fn.fnamemodify(name, ":p")))
      if found and not warned[found.dir] then
        warn(found, true)
      end
    end,
  })
end

function M.setup()
  vim.api.nvim_create_user_command("CocTrustFolder", function(opts)
    M.trust(opts.args ~= "" and opts.args or nil)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Trust a directory's .vim/coc-settings.json (default: cwd)",
  })
  M.watch_buffers()
end

return M
