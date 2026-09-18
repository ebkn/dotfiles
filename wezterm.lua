local wezterm = require 'wezterm'
local act = wezterm.action

local is_windows = wezterm.target_triple:find('windows') ~= nil

-- Default shell: macOS uses Homebrew zsh; on Windows launch zsh inside
-- WSL's default distro from $HOME.
-- Why the full Linuxbrew path: wsl.exe -e bypasses login shells and
-- only inherits /etc/environment's PATH, which does not include
-- /home/linuxbrew/.linuxbrew/bin. A bare `zsh` therefore would not
-- resolve. Once zsh -l starts, zsh/path.zsh adds Linuxbrew to PATH.
-- This path matches install_or_upgrade_login_shell in bin/init/wsl.sh.
local default_prog
if is_windows then
  default_prog = { 'wsl.exe', '--cd', '~', '--', '/home/linuxbrew/.linuxbrew/bin/zsh', '-l' }
else
  default_prog = { '/opt/homebrew/bin/zsh', '--login' }
end

-- Open links and immediately refocus WezTerm so consecutive
-- Cmd+Clicks work without needing a plain click in between.
-- NOTE: open-uri only fires for CompleteSelectionOrOpenLinkAtMouseCursor,
-- NOT for OpenLinkAtMouseCursor (see mouse_bindings below).
-- macOS only: uses /usr/bin/open and osascript. On Windows we leave
-- open-uri unhandled so WezTerm's default ShellExecute path runs.
if not is_windows then
  wezterm.on('open-uri', function(_window, _pane, uri)
    wezterm.run_child_process({ '/usr/bin/open', uri })
    -- Refocus WezTerm after the browser steals focus.
    -- Runs in a background subshell so it doesn't block the UI.
    wezterm.run_child_process({
      '/bin/sh', '-c',
      "(sleep 0.4; osascript -e 'tell application \"WezTerm\" to activate') &",
    })
    return false
  end)
end

-- Raise the OS window that owns a pane, on demand from outside WezTerm.
-- `wezterm cli activate-tab` only switches the tab *within* its window; it never
-- brings that window forward, so a cross-window jump from bin/tmux-agents lands
-- on a tab the user cannot see. As of 20240203 the CLI has no window-focus verb
-- and window:focus() is Lua-only, so user-var-changed is the only door in.
-- bin/tmux-agents writes the OSC 1337 SetUserVar sequence straight to the target
-- pane's tty, which makes `window` below the window that owns that pane.
-- Receive a document forwarded by `read-doc` running inside an ssh session and
-- render it HERE. Inside ssh, read-doc cannot call open(1) — that would launch
-- a browser on the far end, where nobody is looking — so it writes the source
-- to the terminal as OSC 1337 SetUserVar and this side does the rendering.
--
-- The SOURCE crosses the wire, not the HTML: the remote then needs no pandoc,
-- and read-doc/style.css on THIS machine stays the single source of truth for
-- the typography rather than whichever checkout the far end happens to have.
--
-- Note the trust boundary this opens. Any process that can write to a pane —
-- including `cat` on a file from somewhere else — can now cause a file write
-- and a browser launch here. That is the same class of exposure as the OSC 52
-- clipboard writes tmux is already configured to forward, but the action is
-- larger, so the name is stripped to a bare filename and the body is capped.
local READ_DOC_MAX = 1024 * 1024

wezterm.on('user-var-changed', function(window, _pane, name, value)
  if name == 'focus_window' then
    window:focus()
    return
  end

  if name ~= 'read_doc' then
    return
  end

  -- Payload is "<basename>\n<content>"; the name travels so the extension
  -- survives, which is what drives read-doc's language detection and title.
  local doc_name, body = value:match('^([^\n]*)\n(.*)$')
  if not doc_name or #body == 0 or #body > READ_DOC_MAX then
    wezterm.log_error('read_doc: rejected payload')
    return
  end

  -- Strip path separators and control characters rather than allow-listing
  -- word characters: an allow-list would mangle every Japanese filename,
  -- while removing "/" and C0 is what actually prevents escaping the dir.
  doc_name = doc_name:gsub('[/%z\1-\31]', '_'):sub(1, 120)
  if doc_name == '' or doc_name:match('^%.+$') then
    doc_name = 'document.md'
  end

  local dir = (os.getenv('TMPDIR') or '/tmp') .. '/read-doc-inbox'
  -- Synchronous: the write below must not race the directory's creation.
  wezterm.run_child_process({ '/bin/mkdir', '-p', dir })

  local path = dir .. '/' .. doc_name
  local f = io.open(path, 'wb')
  if not f then
    wezterm.log_error('read_doc: cannot write ' .. path)
    return
  end
  f:write(body)
  f:close()

  -- Backgrounded: read-doc shells out to pandoc and then to open(1), which is
  -- far too slow to run on the UI thread.
  --
  -- Spawned through sh purely to repair PATH. A GUI app on macOS inherits the
  -- launchd environment -- /usr/bin:/bin:/usr/sbin:/sbin -- with no Homebrew
  -- prefix, so read-doc launched straight from here cannot find pandoc and
  -- dies with "pandoc not found in PATH" where nothing shows the message.
  -- background_child_process takes no env argument, hence the wrapper.
  wezterm.background_child_process({
    '/bin/sh', '-c',
    'PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" exec "$1" "$2"',
    'read-doc',
    wezterm.home_dir .. '/.local/bin/read-doc',
    path,
  })
end)

-- Tab colour as the ssh indicator.
--
-- tmux's set-titles-string prefixes a remote pane's title with "≫" (see
-- .tmux.conf). That is correct but nearly invisible: one narrow glyph in a row
-- of text, marking the one fact worth noticing at a glance -- that everything
-- typed in this tab lands on another machine. Colour carries it; the marker
-- does not have to, so it is dropped from the rendered label and replaced by a
-- word, on the same purple the tmux status bar and pane border use.
--
-- Non-ssh tabs return a plain string, which is what the default renderer
-- produces, so their appearance is unchanged. Returning the string rather than
-- nil keeps that a decision made here instead of a fallback being relied on.
local SSH_TAB_MARK = '≫'
-- Everforest dark hard: purple (#d699b6) on bg_purple (#463f48) for the tab in
-- front; a dimmed pair for the ones behind, so "which tab am I in" still reads
-- after "which of these are remote".
local SSH_TAB_ACTIVE = { bg = '#463f48', fg = '#d699b6' }
local SSH_TAB_INACTIVE = { bg = '#332c36', fg = '#a88fa3' }

-- What WezTerm itself would show: an explicitly set tab title, else the active
-- pane's title (which under tmux is set-titles-string).
local function tab_label(tab)
  local explicit = tab.tab_title
  if explicit and #explicit > 0 then
    return explicit
  end
  return tab.active_pane.title or ''
end

wezterm.on('format-tab-title', function(tab, _tabs, _panes, _config, _hover, max_width)
  local title = tab_label(tab)
  if not title:find(SSH_TAB_MARK, 1, true) then
    return wezterm.truncate_right(title, max_width)
  end
  -- Replace with a space, then collapse: the marker can sit behind an agent
  -- state glyph ("❓≫ main"), and deleting it outright would glue the two
  -- together.
  title = title:gsub(SSH_TAB_MARK, ' '):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
  local colors = tab.is_active and SSH_TAB_ACTIVE or SSH_TAB_INACTIVE
  return {
    { Background = { Color = colors.bg } },
    { Foreground = { Color = colors.fg } },
    { Attribute = { Intensity = tab.is_active and 'Bold' or 'Normal' } },
    { Text = wezterm.truncate_right(' SSH · ' .. title .. ' ', max_width) },
  }
end)


local keys = {
  { mods = "CTRL", key = "q", action=wezterm.action{ SendString="\x11" } },
  -- Ctrl+T で現在のディレクトリを保持して新しいタブを開く
  -- OSC 7 (zsh/directory.zsh) + allow-passthrough (.tmux.conf) で CWD を取得
  { mods = "CTRL", key = "t", action = wezterm.action_callback(function(window, pane)
    local cwd_url = pane:get_current_working_dir()
    if cwd_url then
      window:perform_action(act.SpawnCommandInNewTab {
        cwd = cwd_url.file_path,
      }, pane)
    else
      window:perform_action(act.SpawnTab 'CurrentPaneDomain', pane)
    end
  end)},
  -- Cmd+W で現在のtmux windowを閉じる
  { mods = "CMD", key = "w", action = wezterm.action.PromptInputLine {
    description = 'Close tmux window? (y/n)',
    action = wezterm.action_callback(function(window, pane, line)
      if line == 'y' or line == 'Y' then
        -- tmux root table に割り当てた F12 を送る。
        -- 文字列送信しないため、vim や実行中プロセスでも漏れない。
        window:perform_action(act.SendKey { key = 'F12' }, pane)
      end
    end),
  }},
  -- tmux を利用するので今は利用していない
  -- 分割
  -- { mods = "LEADER", key = "v", action = wezterm.action { SplitHorizontal = { domain = "CurrentPaneDomain" } }, },
  -- { mods = "LEADER", key = "s", action = wezterm.action { SplitVertical = { domain = "CurrentPaneDomain" } }, },
  -- { mods = "LEADER", key = "w", action = wezterm.action.CloseCurrentPane { confirm = true } },
  -- 移動
  -- { mods = "LEADER", key = 'h', action = wezterm.action.ActivatePaneDirection 'Left' },
  -- { mods = "LEADER", key = 'j', action = wezterm.action.ActivatePaneDirection 'Down' },
  -- { mods = "LEADER", key = 'k', action = wezterm.action.ActivatePaneDirection 'Up' },
  -- { mods = "LEADER", key = 'l', action = wezterm.action.ActivatePaneDirection 'Right' },
  -- リサイズ
  -- { mods = "LEADER|SHIFT", key = 'h', action = wezterm.action.AdjustPaneSize { 'Left', 15 } },
  -- { mods = "LEADER|SHIFT", key = 'j', action = wezterm.action.AdjustPaneSize { 'Down', 15 } },
  -- { mods = "LEADER|SHIFT", key = 'k', action = wezterm.action.AdjustPaneSize { 'Up', 15 } },
  -- { mods = "LEADER|SHIFT", key = 'l', action = wezterm.action.AdjustPaneSize { 'Right', 15 } },
  -- コピーモード
  -- { mods = "LEADER", key = 'u', action = wezterm.action.ActivateCopyMode },
}

-- Windows 流儀の Ctrl+C / Ctrl+V を有効化。WezTerm のデフォルトは Ctrl+Shift+C /
-- Ctrl+Shift+V だが、Windows ユーザーには馴染みが薄い。Ctrl+C は選択がある
-- ときだけコピーし、無ければ通常通り SIGINT を送るので vim や実行中プロセス
-- を壊さない。macOS では Cmd+C/V がデフォルトなので Windows ターゲット時のみ。
-- Windows: Ctrl+C/V for copy/paste (macOS uses Cmd+C/V natively).
-- Ctrl+C copies when there is a terminal selection; otherwise SIGINT is
-- sent so vim/shell Ctrl+C still works.  Ctrl+V always pastes — vim's
-- visual-block mode is accessible via Ctrl+Q instead.
if is_windows then
  table.insert(keys, { mods = 'CTRL', key = 'c', action = wezterm.action_callback(function(window, pane)
    local sel = window:get_selection_text_for_pane(pane)
    if sel ~= '' then
      window:perform_action(act.CopyTo 'Clipboard', pane)
      window:perform_action(act.ClearSelection, pane)
    else
      window:perform_action(act.SendKey { key = 'c', mods = 'CTRL' }, pane)
    end
  end) })
  table.insert(keys, { mods = 'CTRL', key = 'v', action = act.PasteFrom 'Clipboard' })
end

return {
  -- $TERM value advertised to the shell (and tmux).
  -- tmux's terminal-overrides in .tmux.conf match this value to enable
  -- RGB (true color) and OSC 52 clipboard forwarding.
  term = 'xterm-256color',

  default_prog = default_prog,

  window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  },

  font = wezterm.font_with_fallback({
    {family = 'JetBrains Mono', weight = 'Medium', harfbuzz_features = {'calt=0', 'clig=0', 'liga=0'} },
    {family = 'JetBrains Mono', weight = 'Medium', italic = true, harfbuzz_features = {'calt=0', 'clig=0', 'liga=0'} },
    {family = 'Hiragino Kaku Gothic ProN', weight = 'Medium'},
    {family = 'Apple Color Emoji'},
  }),
  font_size = 13,
  line_height = 1.2,

  -- Terminal-level color palette. WezTerm uses this to render all output.
  -- Keep in sync with Neovim's colorscheme (vim/color.vim) so that
  -- ANSI colors and UI chrome share a consistent look.
  color_scheme = 'Everforest Dark (Gogh)',

  show_tab_index_in_tab_bar = false,
  tab_max_width = 160,
  -- Disable two-finger swipe / mouse wheel over the tab bar from switching
  -- tabs. macOS trackpad swipes are easy to trigger accidentally.
  mouse_wheel_scrolls_tabs = false,
  window_frame = {
    font_size = 11.5,
    font = wezterm.font({ family = 'JetBrains Mono', weight = 'Medium', stretch = 'Expanded' }),
  },

  scrollback_lines = 100000,
  max_fps = 120,
  front_end = 'WebGpu',

  default_cursor_style = 'SteadyBlock',
  force_reverse_video_cursor = true,

  audible_bell = "SystemBeep",
  visual_bell = {
    fade_in_function = 'EaseIn',
    fade_in_duration_ms = 150,
    fade_out_function = 'EaseOut',
    fade_out_duration_ms = 150,
  },
  colors = {
    visual_bell = '#202020',
  },

  -- https://github.com/wez/wezterm/issues/2630
  -- tmux を利用するので今は利用していない
  -- leader = { key = 'q', mods = 'CTRL', timeout_milliseconds = 1000 },

  keys = keys,

  -- Cmd bypasses tmux mouse reporting so Cmd+Click can open links
  bypass_mouse_reporting_modifiers = 'SUPER',

  mouse_bindings = {
    {
        event = { Down = { streak = 1, button = 'Right' } },
        mods = 'NONE',
        action = wezterm.action.PasteFrom 'Clipboard',
    },
  },
}
