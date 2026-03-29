return {
  {
    "3rd/image.nvim",
    build = false,
    opts = {
      backend = "sixel",
      processor = "magick_cli",
      integrations = {
        markdown = {
          enabled = true,
          only_render_image_at_cursor = true,
          only_render_image_at_cursor_mode = "popup",
          filetypes = { "markdown", "vimwiki" },
        },
      },
      -- fill the window as large as possible (aspect ratio preserved by the plugin)
      max_width_window_percentage = 100,
      max_height_window_percentage = 100,
      -- auto-hide images when the window scrolls over them
      window_overlap_clear_enabled = true,
      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs" },
      -- hide images in other tmux windows to avoid bleed-through
      tmux_show_only_in_active_window = true,
      -- open image files directly in Neovim
      hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif", "*.svg" },
    },
  },
}
