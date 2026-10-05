# update-all: bring every package manager, plugin manager and language server on
# this machine up to date, then re-sync the dotfiles symlinks via relink.
#
# Apart from the aliases because it is the one thing in here that is run
# deliberately and occasionally rather than typed all day -- and because it is
# the list most likely to need editing.

# Warn when this Mac runs a kernel whose TCP clock stops, and has been up long
# enough for that to be near. On macOS 26.0-26.3 tcp_now stops advancing once it
# overflows, 49.7 days after boot: TIME_WAIT sockets are never reaped again, the
# ephemeral ports leak away, and days later every outbound connection fails with
# "Can't assign requested address" while ping still works. Nothing announces the
# deadline, so this does. macOS 26.4 fixed it, which is why the release is
# checked: on a fixed kernel this would be a false alarm on every run. See
# zsh/README.md.
_uptime_reboot_warning() {
  [[ $OSTYPE == darwin* ]] || return 0
  # One value per line, in the order asked:
  #   25.1.0
  #   { sec = 1785885898, usec = 482779 } Wed Aug  5 08:24:58 2026
  local -a info
  info=("${(@f)$(sysctl -n kern.osrelease kern.boottime 2>/dev/null)}")
  # Darwin 25.0-25.3 is macOS 26.0-26.3. Not $OSTYPE: that is the release zsh
  # was built for, not the kernel that is running.
  [[ ${info[1]-} == 25.<0-3>.* ]] || return 0
  [[ ${info[2]-} == '{ sec = '<->,* ]] || return 0
  local -i boot=${${info[2]#*sec = }%%,*}
  # Wall-clock uptime, although the kernel counts only time awake: on a machine
  # that sleeps this is early, never late. 30 rather than something nearer 49
  # because it is only seen when update-all is run.
  local -i days=$(( ($(date +%s) - boot) / 86400 ))
  (( days >= 30 )) || return 0
  print -u2 -- "warning: up $days days, and this macOS (Darwin ${info[1]}) stops its TCP clock after 49.7 days awake."
  print -u2 -- "         Outbound connections then fail. Reboot before that, or update to macOS 26.4+ (fixed)."
}

update-all() {
  brew upgrade
  brew upgrade --cask
  zinit ice proto=ssh depth=1
  zinit update --all
  nvim --headless +'CocUpdate' +qa
  nvim --headless +'TSUpdate' +qa
  nvim --headless '+Lazy! sync' +qa
  go install golang.org/x/tools/...@latest
  go install github.com/cweill/gotests/...@latest
  go install github.com/mattn/efm-langserver@latest
  go install github.com/hashicorp/terraform-ls@latest
  go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest
  go install github.com/nametake/golangci-lint-langserver@latest
  go install github.com/mikefarah/yq/v4@latest
  go install github.com/x-motemen/ghq@latest
  go install github.com/cloudspannerecosystem/spanner-cli@latest
  go install github.com/aquasecurity/tfsec/cmd/tfsec@latest
  go install github.com/terraform-linters/tflint@latest
  go install mvdan.cc/gofumpt@latest
  go install tailscale.com/cmd/tailscale{,d}@main
  # --ignore-scripts=false overrides ~/.npmrc's global ignore-scripts=true: this
  # is a curated, trusted list, and some (e.g. @openai/codex) need postinstall
  # to build/fetch a native binary. Keep in sync with bin/init/{macos,ubuntu,wsl}.sh.
  npm update --location=global --ignore-scripts=false
  npm i -g --ignore-scripts=false diagnostic-languageserver
  npm i -g --ignore-scripts=false dockerfile-language-server-nodejs
  npm i -g --ignore-scripts=false markdownlint-cli
  npm i -g --ignore-scripts=false textlint
  npm i -g --ignore-scripts=false git-delete-squashed
  npm i -g --ignore-scripts=false yarn
  npm i -g --ignore-scripts=false @openai/codex
  # Audit the cwd project for known vulnerabilities (skipped outside projects).
  if [ -f package-lock.json ]; then
    npm audit || true
  fi
  gcloud components update --quiet
  # After all package updates, re-sync dotfiles symlinks so links added to the
  # repo since this machine was provisioned get created (reports drift, then
  # asks before changing anything). See bin/relink.
  if command -v relink >/dev/null 2>&1; then
    relink
  fi
  # Last, so it is what is left on screen -- and so that when the clock has
  # already stopped, it explains the network failures scrolled past above.
  _uptime_reboot_warning
}
