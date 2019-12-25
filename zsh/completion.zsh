# add / after directory
setopt auto_param_slash
setopt mark_dirs

# autocomplete
setopt auto_list
setopt auto_menu

# smartcase
zstyle ':completion:*' matcher-list '' \
  'm:{a-z\-}={A-Z\_}' \
  'r:[^[:alpha:]]||[[:alpha:]]=** r:|=* m:{a-z\-}={A-Z\_}' \
  'r:|?=** m:{a-z\-}={A-Z\_}'

# highlight selection
zstyle ':completion:*' menu select
