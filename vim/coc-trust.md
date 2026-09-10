# coc.nvim workspace trust

`vim/nvim/lua/coc_trust.lua`, wired from `plugins/instantly/completion.lua`.

## The problem

coc reads `<folder>/.vim/coc-settings.json` and lets it **override user
configuration with no trust prompt** — it has no workspace-trust model at all
(`trust`/`isTrusted`/`workspaceTrust` appear nowhere in its bundle outside
unrelated markdown rendering).

A `languageserver` entry there is `{command, args, filetypes}`: an arbitrary
executable with arbitrary argv. `registerClientsFromFolder` reads it from
`workspaceFolderValue`, `registerClientsByConfig` only type-checks it, and it
reaches `child_process.spawn`.

The default `workspace.rootPatterns` includes `.git`, so **every cloned
repository is a workspace folder** and `git clone && nvim README.md` — opening a
file merely to read it — runs the repo's code.

Verified end to end here: with the folder trusted the payload fires, with it
untrusted it does not.

## The only gate is not starting coc

There is **no coc setting that disables folder config** (the whole schema was
searched), so the gate is `g:coc_start_at_startup = 0`, with `:CocStart` or
`:CocTrustFolder` as the opt-in.

## Four things will silently break this if touched

1. **The gate must run in lazy.nvim's `init`, never `config`.** coc reads
   `g:coc_start_at_startup` when `plugin/coc.vim` is sourced, which lazy does
   *before* `config` — so a `config` hook is too late and coc starts anyway.
2. **Never use `vim.fn.expand()` to normalize a path here.** It treats its
   argument as a wildcard pattern and applies `'wildignore'`, which
   `vim/base.vim:72` sets to `*/tmp*,*.so,*.swp,*.zip` — so `expand()` returns
   an **empty string** for any path under a `tmp` directory and the gate passes
   every repo whose path matches, with no error. `fnamemodify(dir, ':p')` does
   the one expansion wanted (a leading `~`) and ignores wildcards.
3. **Reducing the filesystem root to `""` when trimming a trailing slash** makes
   `vim.fs.joinpath` build a **relative** path, which `fs_stat` then resolves
   against the current directory — so walking up to `/` reports cwd's own config
   as an ancestor's.
4. **Lazy-loading coc by filetype is not a mitigation** — the attacker picks
   `filetypes`.

## Two loading paths are mirrored, because coc has two

The config file of `cwd` at construction, and `findUp('.vim', <file path>)` per
document, which reaches **any ancestor of an opened file**, not just the git
root.

The startup gate *prevents*; the `BufReadPre`/`BufNewFile` watcher only
*reports*, since by then coc is either gated off (nothing happens) or already
running.

`$HOME` is skipped on purpose, matching coc's own `folderToConfigfile`, so
`~/.vim/coc-settings.json` is a user config and not reported.

## The trust list is not version-controlled

It is a per-machine decision about paths on that machine, so it lives at
`stdpath("state")/coc-trusted-folders`.
