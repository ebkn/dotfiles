# load zplugin

source "$HOME/.zplugin/bin/zplugin.zsh"
autoload -Uz _zplugin
(( ${+_comps} )) && _comps[zplugin]=_zplugin

zpcompinit

# color
zplugin light "chrissicool/zsh-256color"
zplugin light zpm-zsh/colorize
zplugin light ael-code/zsh-colored-man-pages

# auto suggestion
zplugin light zsh-users/zsh-autosuggestions

# syntax highlight
zplugin light zdharma/fast-syntax-highlighting

# completion
zplugin light "zsh-users/zsh-completions"

# zsh theme
zplugin ice depth=1; zplugin light romkatv/powerlevel10k # see ./zsh/.p10k.zsh
