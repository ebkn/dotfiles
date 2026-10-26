# Sourced by zsh/path.zsh, so every interactive shell runs brew with these,
# and by bin/init/{macos,ubuntu,wsl}.sh, which run before any such shell
# exists: a fresh machine's brew bundle is the largest install it ever does.
# Plain POSIX sh, no shebang: one file, so the hardening cannot drift between
# the shells that read it.
# shellcheck shell=bash

# Homebrew packages managed outside Homebrew (Volta/official installers).
export HOMEBREW_FORBIDDEN_FORMULAE="node npm pnpm yarn claude"

# Supply-chain hardening for Homebrew.
# Verify Sigstore attestations on bottles to ensure they were built by
# Homebrew's official CI rather than tampered with downstream. With no GitHub
# credentials (HOMEBREW_GITHUB_API_TOKEN, a `gh` login or the macOS Keychain)
# every bottle but gh's then fails to install, rather than going unverified;
# setup asks for a gh login first (ensure_homebrew_github_auth in common.sh).
# The setup workflows alone switch it off with HOMEBREW_NO_VERIFY_ATTESTATIONS,
# which Homebrew lets win: one API call per bottle exhausts CI's token.
export HOMEBREW_VERIFY_ATTESTATIONS=1
# Refuse HTTP-to-HTTPS redirects during downloads.
export HOMEBREW_NO_INSECURE_REDIRECT=1
# Not HOMEBREW_ALLOWED_TAPS: it did refuse third-party taps, but Homebrew
# deprecated it with no replacement (7c2a921, 2026-09-13), so it warns on every
# brew command and will later be ignored without a word. HOMEBREW_FORBIDDEN_TAPS
# is a denylist, which cannot name a tap not yet seen. No tap is in use
# (brewfiles/ has no `tap` line); keeping it that way is left to review
# (2026-10).
# Not HOMEBREW_CASK_OPTS=--require-sha: it has no per-cask exemption, and 4 of
# brewfiles/Brewfile-cask (google-chrome, google-drive, google-japanese-ime,
# spotify) are `sha256 :no_check`, so they would fail to install or upgrade. The
# other checksums are taken by Homebrew's autobump from the vendor's own file,
# so they catch a CDN swap after the bump, not a compromised vendor (2026-10).
