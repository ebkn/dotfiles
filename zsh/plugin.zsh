# load plugins by zinit
#
### Added by Zinit's installer
if [[ ! -f $HOME/.zinit/bin/zinit.zsh ]]; then
    print -P "%F{33}▓▒░ %F{220}Installing DHARMA Initiative Plugin Manager (zdharma/zinit)…%f"
    command mkdir -p "$HOME/.zinit" && command chmod g-rwX "$HOME/.zinit"
    command git clone git@github.com:zdharma-continuum/zinit.git "$HOME/.zinit/bin" && \
        print -P "%F{33}▓▒░ %F{34}Installation successful.%f" || \
        print -P "%F{160}▓▒░ The clone has failed.%f"
fi
source "$HOME/.zinit/bin/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit
### End of Zinit installer's chunk

zinit ice proto=ssh depth=1

# --- Synchronous (needed before first prompt) ---
# Only plugins that affect prompt rendering or color output are loaded
# synchronously. All others use `wait lucid` to defer loading until
# after the first prompt, reducing blocking startup time.

# color (must load before other plugins that produce colored output)
zinit light chrissicool/zsh-256color

# zsh theme (renders the prompt, cannot be deferred)
zinit light romkatv/powerlevel10k # see ./zsh/.p10k.zsh

# --- Deferred (loaded after first prompt via `wait lucid`) ---

# auto suggestion (loaded synchronously so suggestions appear on first keystroke)
zinit light zsh-users/zsh-autosuggestions

# syntax highlight
zinit ice wait lucid
zinit light zdharma-continuum/fast-syntax-highlighting

# completion
zinit ice wait lucid
zinit light zsh-users/zsh-completions

# notify after completion
zinit ice wait lucid
zinit light MichaelAquilina/zsh-auto-notify

# interactive jq (atload: bind ^j after the widget is defined to avoid
# "unhandled ZLE widget" error from fast-syntax-highlighting)
zinit ice wait lucid atload"bindkey '^j' jq-complete"
zinit light reegnz/jq-zsh-plugin

# Use -C to skip compaudit security scan (~22ms) and reuse the cached
# completion dump. The dump is regenerated automatically when
# zsh-completions or other plugins update completion definitions.
autoload bashcompinit && bashcompinit
autoload -Uz compinit && compinit -C
