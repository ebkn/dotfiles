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

  audible_bell = "Disabled",

  -- https://github.com/wez/wezterm/issues/2630
  keys = {
    { mods = "CTRL", key = "q", action=wezterm.action{ SendString="\x11" } },
  }
}
