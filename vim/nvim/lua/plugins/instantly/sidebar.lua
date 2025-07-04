return {
  -- actions
  -- a: action
  -- m: move
  -- c: copy
  -- D: delete
  -- l: expand
  -- ?: open help
  {
    "lambdalisue/fern.vim",
    config = function()
      vim.cmd([[
        let g:fern#disable_default_mappings=1
        nnoremap <silent><C-s> :Fern . -drawer -reveal=% -toggle -stay<CR>
        function! s:init_fern() abort
          nmap <buffer><nowait> l <Plug>(fern-action-expand)
          nmap <buffer><nowait> h <Plug>(fern-action-collapse)
          nmap <buffer><nowait> D <Plug>(fern-action-remove)
          nmap <buffer><nowait> c <Plug>(fern-action-copy)
          nmap <buffer><nowait> m <Plug>(fern-action-move)
          nmap <buffer><nowait> N <Plug>(fern-action-new-file)
          nmap <buffer><nowait> <Return> <Plug>(fern-action-open)
        endfunction
        augroup fern-custom
          autocmd! *
          autocmd FileType fern call s:init_fern()
          autocmd FileType fern setlocal nonumber
        augroup END
        " show hidden files by default
        let g:fern#default_hidden=1

        " Auto reveal current file in fern
        function! s:fern_reveal_current() abort
          " Skip if current buffer is fern itself
          if &filetype ==# 'fern'
            return
          endif

          " Skip if no fern window exists
          let l:fern_win = filter(range(1, winnr('$')), 'getwinvar(v:val, "&filetype") ==# "fern"')
          if empty(l:fern_win)
            return
          endif

          let l:current = expand('%:p')
          if !empty(l:current) && filereadable(l:current)
            " Save current window
            let l:winnr = winnr()
            try
              " Switch to fern window and reveal
              execute l:fern_win[0] . 'wincmd w'
              execute 'FernReveal ' . l:current
              " Return to original window
              execute l:winnr . 'wincmd w'
            catch
              " Ignore errors silently
            endtry
          endif
        endfunction

        " Store git status hash to detect changes
        let g:fern_git_status_cache = {}

        " Get git status hash for current directory
        function! s:get_git_status_hash() abort
          let l:cwd = getcwd()
          try
            let l:status = system('git status --porcelain 2>/dev/null')
            if v:shell_error == 0
              return l:cwd . ':' . sha256(l:status)
            endif
          catch
          endtry
          return l:cwd . ':none'
        endfunction

        " Auto reload fern when files are created/deleted
        function! s:fern_reload() abort
          " Skip if current buffer is fern (to avoid flicker)
          if &filetype ==# 'fern'
            return
          endif

          " Skip if no fern window exists
          let l:fern_bufnr = filter(range(1, bufnr('$')), 'getbufvar(v:val, "&filetype") ==# "fern"')
          if empty(l:fern_bufnr)
            return
          endif

          " Check if git status actually changed
          let l:current_hash = s:get_git_status_hash()
          let l:cwd = getcwd()
          if has_key(g:fern_git_status_cache, l:cwd) && g:fern_git_status_cache[l:cwd] ==# l:current_hash
            " No changes detected, skip reload to prevent flickering
            return
          endif
          let g:fern_git_status_cache[l:cwd] = l:current_hash

          " Use win_execute to reload fern without changing window
          for bufnr in l:fern_bufnr
            let l:win = bufwinnr(bufnr)
            if l:win > 0
              try
                " Execute normal R in the fern window
                call win_execute(win_getid(l:win), 'normal R')
              catch
                " Ignore errors
              endtry
            endif
          endfor

          " Reveal current file after reload
          call timer_start(100, {-> s:fern_reveal_current()})
        endfunction

        " Reveal current file when switching buffers
        augroup fern-auto-reveal
          autocmd!
          autocmd BufEnter * call s:fern_reveal_current()
          " Auto reload on file write/new
          autocmd BufWritePost * call s:fern_reload()
          autocmd BufNewFile * call s:fern_reload()
          " Auto reload when external changes detected
          autocmd FocusGained * call s:fern_reload()
          " Removed CursorHold to reduce frequent reloading
        augroup END

        " Auto reload fern with timer (detect external changes)
        if has('timers') && !exists('g:fern_auto_reload_timer')
          function! FernAutoReload(timer)
            " Skip if current buffer is fern
            if &filetype !=# 'fern'
              call s:fern_reload()
            endif
          endfunction
          " Keep 1 second interval for quick external changes detection
          let g:fern_auto_reload_timer = timer_start(1000, 'FernAutoReload', {'repeat': -1})
        endif
      ]])
    end,
  },

  {
    "lambdalisue/fern-git-status.vim",
    dependencies = { "lambdalisue/fern.vim" },
    config = function()
      vim.cmd([[
        let g:fern_git_status#disable_ignored=0
        let g:fern_git_status#disable_untracked=0
        let g:fern_git_status#disable_submodules=0
        let g:fern_git_status#disable_directories=0
      ]])
    end,
  },

  {
    "antoinemadec/FixCursorHold.nvim",
  },

  {
    "LumaKernel/fern-mapping-reload-all.vim",
    dependencies = { "lambdalisue/fern.vim" },
    config = function()
      vim.cmd([[
        function s:init_fern_mapping_reload_all()
          nmap <buffer> R <Plug>(fern-action-reload:all)
        endfunction
        augroup my-fern-mapping-reload-all
          autocmd! *
          autocmd FileType fern call s:init_fern_mapping_reload_all()
        augroup END
      ]])
    end,
  },
}