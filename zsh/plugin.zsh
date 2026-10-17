# load plugins by zinit
#
# Supply-chain pins: zinit and every plugin run inside every shell, with the
# user's keys and tokens in reach, so each is held at a commit and moves only
# when a commit here moves it. To update one, change its SHA and run
# `zinit update` (a plugin) or start a new shell (zinit). Never add `depth` to
# a pinned ice: the shallow clone cannot check out the pin, and every shell
# after the first loads the newest commit without a word. See zsh/README.md.
_zinit_repo=zdharma-continuum/zinit
_zinit_pin=f466c8805d8890f76bed8cf0972e0f7310fc5fc9
_zinit_bin=$HOME/.zinit/bin

### Added by Zinit's installer
if [[ ! -f $_zinit_bin/zinit.zsh ]]; then
    print -P "%F{33}▓▒░ %F{220}Installing DHARMA Initiative Plugin Manager (zdharma/zinit)…%f"
    command mkdir -p "$HOME/.zinit" && command chmod g-rwX "$HOME/.zinit"
    command git clone "git@github.com:$_zinit_repo.git" "$_zinit_bin" && \
        print -P "%F{33}▓▒░ %F{34}Installation successful.%f" || \
        print -P "%F{160}▓▒░ The clone has failed.%f"
fi

# zinit is not a plugin, so no ver ice holds it; this does. A detached HEAD file
# holds the bare SHA, so `read` checks it without a fork on every start, and
# only a mismatch (a fresh clone, or a moved pin) reaches git. Detached also
# turns zinit's self-update, which `zinit update --all` runs, into a no-op: it
# only pulls a branch with an upstream. A failure warns rather than stops the
# shell, which would leave the machine without one.
if [[ -r $_zinit_bin/.git/HEAD ]] && read -r _zinit_head < $_zinit_bin/.git/HEAD \
    && [[ $_zinit_head != $_zinit_pin ]]; then
  if ! command git -C "$_zinit_bin" cat-file -e "$_zinit_pin^{commit}" 2>/dev/null; then
    command git -C "$_zinit_bin" fetch --quiet origin 2>/dev/null
  fi
  command git -C "$_zinit_bin" -c advice.detachedHead=false checkout --quiet --detach "$_zinit_pin" 2>/dev/null \
    || print -u2 -- "plugin.zsh: cannot check out zinit's pin $_zinit_pin; running ${_zinit_head#ref: } unpinned"
fi
unset _zinit_head

source "$_zinit_bin/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit
### End of Zinit installer's chunk

# --- Synchronous (needed before first prompt) ---
# Only plugins that affect prompt rendering or color output are loaded
# synchronously. All others use `wait lucid` to defer loading until
# after the first prompt, reducing blocking startup time.

# color (must load before other plugins that produce colored output)
zinit ice ver"559fee48bb74b75cec8b9887f8f3e046f01d5d8f"
zinit light chrissicool/zsh-256color

# zsh theme (renders the prompt, cannot be deferred)
zinit ice ver"d05a1b00f9a61f9578bf9dc19b8451942dde8734"
zinit light romkatv/powerlevel10k # see ./zsh/.p10k.zsh

# --- Deferred (loaded after first prompt via `wait lucid`) ---

# auto suggestion (loaded synchronously so suggestions appear on first keystroke)
zinit ice ver"85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5"
zinit light zsh-users/zsh-autosuggestions

# syntax highlight
zinit ice wait lucid ver"4672ad5dd9ad68a7effc1476d65afb7c584ce2b3"
zinit light zdharma-continuum/fast-syntax-highlighting

# completion
zinit ice wait lucid ver"989b23277ab33e8d5e82df6aed936e846db9d8b8"
zinit light zsh-users/zsh-completions

# notify after completion
zinit ice wait lucid ver"b51c934d88868e56c1d55d0a2a36d559f21cb2ee"
zinit light MichaelAquilina/zsh-auto-notify

# interactive jq (atload: bind ^j after the widget is defined to avoid
# "unhandled ZLE widget" error from fast-syntax-highlighting)
zinit ice wait lucid atload"bindkey '^j' jq-complete" ver"3aa96cc33a260ad4495d703da0fc6528110e6475"
zinit light reegnz/jq-zsh-plugin

# `compinit -C` skips the compaudit security scan (~22ms) and, crucially, the
# $fpath rescan — it trusts ~/.zcompdump as-is and never regenerates it. That is
# fast, but the dump only autoloads completion functions (_mv, _ignored, …) by
# name; their files are resolved from the live $fpath at call time. A zsh upgrade
# removes the previous version's Cellar function dir, so a dump built for the old
# version keeps pointing at files that are gone, yielding "function definition
# file not found". The dump's first line records the zsh version it was built
# for, so rebuild (plain `compinit`) when that no longer matches $ZSH_VERSION and
# reuse the cache (`compinit -C`) otherwise. (`read` keeps this fork-free.)
autoload bashcompinit && bashcompinit
autoload -Uz compinit
_zdump="${ZDOTDIR:-$HOME}/.zcompdump"
if [[ -r "$_zdump" ]] && read -r _zdump_head < "$_zdump" && [[ "$_zdump_head" == *"version: $ZSH_VERSION"* ]]; then
  compinit -C -d "$_zdump"
else
  compinit -d "$_zdump"
fi
unset _zdump _zdump_head
