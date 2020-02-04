# load plugins by zinit
#
### Added by Zinit's installer
if [[ ! -f $HOME/.zinit/bin/zinit.zsh ]]; then
    print -P "%F{33}▓▒░ %F{220}Installing DHARMA Initiative Plugin Manager (zdharma/zinit)…%f"
    command mkdir -p "$HOME/.zinit" && command chmod g-rwX "$HOME/.zinit"
    command git clone https://github.com/zdharma/zinit "$HOME/.zinit/bin" && \
        print -P "%F{33}▓▒░ %F{34}Installation successful.%f" || \
        print -P "%F{160}▓▒░ The clone has failed.%f"
fi
source "$HOME/.zinit/bin/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit
### End of Zinit installer's chunk

zpcompinit

# color
zinit light "chrissicool/zsh-256color"
zinit light zpm-zsh/colorize
zinit light ael-code/zsh-colored-man-pages

# auto suggestion
zinit light zsh-users/zsh-autosuggestions

# syntax highlight
zinit light zdharma/fast-syntax-highlighting

# completion
zinit light "zsh-users/zsh-completions"

# zsh theme
zinit ice depth=1; zinit light romkatv/powerlevel10k # see ./zsh/.p10k.zsh
