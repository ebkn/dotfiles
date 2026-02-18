local wezterm = require 'wezterm'
local act = wezterm.action

return {
  term = 'screen-256color',

  default_prog = { '/opt/homebrew/bin/zsh', '--login' },

  window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  },

  font = wezterm.font_with_fallback({
    {family = 'Roboto Mono', weight = 'DemiBold' },
    {family = 'Roboto Mono', weight = 'DemiBold', italic = true },
    {family = 'Hiragino Kaku Gothic ProN', weight = 'Medium'},
    {family = 'Apple Color Emoji'},
  }),
  font_size = 12.5,

  color_scheme = 'OneDark (base16)',

  scrollback_lines = 100000,
  max_fps = 60,
  front_end = 'OpenGL',

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
        action = act.OpenLinkAtMouseCursor,
    },
    {
        event = { Down = { streak = 1, button = 'Right' } },
        mods = 'NONE',
        action = wezterm.action.PasteFrom 'Clipboard',
    },
  },
}
