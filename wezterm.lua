local wezterm = require 'wezterm'
local act = wezterm.action

-- Open links and immediately refocus WezTerm so consecutive
-- Cmd+Clicks work without needing a plain click in between.
-- NOTE: open-uri only fires for CompleteSelectionOrOpenLinkAtMouseCursor,
-- NOT for OpenLinkAtMouseCursor (see mouse_bindings below).
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

return {
  -- $TERM value advertised to the shell (and tmux).
  -- tmux's terminal-overrides in .tmux.conf match this value to enable
  -- RGB (true color) and OSC 52 clipboard forwarding.
  term = 'xterm-256color',

  default_prog = { '/opt/homebrew/bin/zsh', '--login' },

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
  tab_max_width = 40,
  window_frame = {
    font_size = 14,
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

  keys = {
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
  },

  -- Cmd bypasses tmux mouse reporting so Cmd+Click can open links
  bypass_mouse_reporting_modifiers = 'SUPER',


  mouse_bindings = {
    {
        event = { Up = { streak = 1, button = 'Left' } },
        mods = 'SUPER',
        action = act.CompleteSelectionOrOpenLinkAtMouseCursor,
    },
    {
        event = { Down = { streak = 1, button = 'Right' } },
        mods = 'NONE',
        action = wezterm.action.PasteFrom 'Clipboard',
    },
  },
}
