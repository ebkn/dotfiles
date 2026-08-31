# update-all: bring every package manager, plugin manager and language server on
# this machine up to date, then re-sync the dotfiles symlinks via relink.
#
# Apart from the aliases because it is the one thing in here that is run
# deliberately and occasionally rather than typed all day -- and because it is
# the list most likely to need editing.

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
  # to build/fetch a native binary. Keep in sync with bin/init/macos.sh.
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
}
