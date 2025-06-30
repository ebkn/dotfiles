return {
  {
    "dart-lang/dart-vim-plugin",
    ft = { "dart" },
    config = function()
      vim.cmd([[
        function! TriggerFlutterHotReload() abort
          silent execute '!kill -SIGUSR1 $(pgrep -f "[f]lutter_tool.*run")'
        endfunction
        augroup dart-vim-plugin
          autocmd!
          autocmd FileType dart BufWritePost *.dart call TriggerFlutterHotReload()
        augroup END
        let g:dart_style_guide = 2
        let g:dart_format_on_save = 1
        let g:dartfmt_options = ['--fix', '-l 180']
      ]])
    end,
  },
}