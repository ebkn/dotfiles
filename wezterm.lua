local wezterm = require 'wezterm'

return {
  term = "screen-256color",

  default_prog = { '/opt/homebrew/bin/zsh', '--login' },

  window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  },

  font = wezterm.font("JetBrains Mono", { weight = "Bold" }),
  font_size = 13.0,

  color_scheme = "OneDark (base16)",

  scrollback_lines = 100000,
}
