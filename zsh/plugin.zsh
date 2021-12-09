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

# color
zinit light chrissicool/zsh-256color
# zinit light ael-code/zsh-colored-man-pages

# auto suggestion
zinit light zsh-users/zsh-autosuggestions

# syntax highlight
zinit light zdharma-continuum/fast-syntax-highlighting

# completion
zinit light zsh-users/zsh-completions

# zsh theme
zinit light romkatv/powerlevel10k # see ./zsh/.p10k.zsh

# notify after completion
zinit light MichaelAquilina/zsh-auto-notify

# interactive jq
zinit light reegnz/jq-zsh-plugin
bindkey '^j' jq-complete

# cache compinit once a day
# https://gist.github.com/ctechols/ca1035271ad134841284
autoload -Uz compinit
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
	compinit;
else
	compinit -C;
fi;
