local wezterm = require 'wezterm'

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

  default_cursor_style = 'SteadyBlock',
  force_reverse_video_cursor = true,

  audible_bell = "SystemBeep",

  -- https://github.com/wez/wezterm/issues/2630
  leader = { key = 'q', mods = 'CTRL', timeout_milliseconds = 1000 },

  keys = {
    { mods = "CTRL", key = "q", action=wezterm.action{ SendString="\x11" } },
    -- 分割
    { mods = "LEADER", key = "v", action = wezterm.action { SplitHorizontal = { domain = "CurrentPaneDomain" } }, },
    { mods = "LEADER", key = "s", action = wezterm.action { SplitVertical = { domain = "CurrentPaneDomain" } }, },
    { mods = "LEADER", key = "w", action = wezterm.action.CloseCurrentPane { confirm = true } },
    -- 移動
    { mods = "LEADER", key = 'h', action = wezterm.action.ActivatePaneDirection 'Left' },
    { mods = "LEADER", key = 'j', action = wezterm.action.ActivatePaneDirection 'Down' },
    { mods = "LEADER", key = 'k', action = wezterm.action.ActivatePaneDirection 'Up' },
    { mods = "LEADER", key = 'l', action = wezterm.action.ActivatePaneDirection 'Right' },
    -- リサイズ
    { mods = "LEADER|SHIFT", key = 'h', action = wezterm.action.AdjustPaneSize { 'Left', 10 } },
    { mods = "LEADER|SHIFT", key = 'j', action = wezterm.action.AdjustPaneSize { 'Down', 10 } },
    { mods = "LEADER|SHIFT", key = 'k', action = wezterm.action.AdjustPaneSize { 'Up', 10 } },
    { mods = "LEADER|SHIFT", key = 'l', action = wezterm.action.AdjustPaneSize { 'Right', 10 } },
    -- コピーモード
    { mods = "LEADER", key = 'u', action = wezterm.action.ActivateCopyMode },
  },

  mouse_bindings = {
    {
        event = { Down = { streak = 1, button = 'Right' } },
        mods = 'NONE',
        action = wezterm.action.PasteFrom 'Clipboard',
    },
  },
}
