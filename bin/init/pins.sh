# Versions and sha256 checksums for everything setup fetches from the internet
# outside a package manager. Each one used to be `curl … | bash` of whatever
# the server returned that minute: no version, no checksum, and none of the
# 7-day holds the package managers have (bin/init/pins.md). Sourced by
# bin/init/{macos,ubuntu,wsl}.sh next to common.sh, whose installers read it,
# and by zsh/update.zsh, so plain assignments only: bash and zsh both read
# them. common.sh does not source it itself, so a test can set pins in the
# environment without this file overwriting them.
#
# Bumping: pick a release at least 7 days old, as the cooldowns do, and replace
# every checksum of that tool in the same commit. bin/init/pins.md has the
# command that produces each one; the URLs there are the ones the installers
# in common.sh fetch, and change with them.
# shellcheck shell=bash
# shellcheck disable=SC2034 # read by common.sh and zsh/update.zsh

# Homebrew/install at a commit, not HEAD. The script clones Homebrew itself
# at its latest tag; from then on `brew update` moves it, like any machine.
HOMEBREW_INSTALL_COMMIT=be041513824fd2666a0e93cf5c3b0ca3bb0eb4b6
HOMEBREW_INSTALL_SHA256=5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148

# Volta release tarballs, unpacked into ~/.volta/bin by hand: the get.volta.sh
# installer would fetch the latest release with no checksum.
VOLTA_VERSION=2.0.2
VOLTA_SHA256_DARWIN_ARM64=57f7b51d6fb975f5c48b5ddf68f75103055e19fd822e3e2ce58d2be6ab78977d
VOLTA_SHA256_DARWIN_X64=57f7b51d6fb975f5c48b5ddf68f75103055e19fd822e3e2ce58d2be6ab78977d
VOLTA_SHA256_LINUX_X64=6cec054c911fb925b629a09455775af6e95dc0f5694a4c28b63979ab9ef18037
VOLTA_SHA256_LINUX_ARM64=1eb92f8b711753aa576352b2e580b2f3fdadeab8664929ca1da3d0de65448517

# The node Volta installs as the default. A project's own `volta` pin in its
# package.json still wins inside that project.
NODE_VERSION=24.22.0

# Google Cloud CLI. Setup unpacks this release; update-all's
# `gcloud components update` moves to it, not to the newest.
GCLOUD_VERSION=589.0.0
GCLOUD_SHA256_DARWIN_ARM64=3b317feba2f2a552e9aba529a2f8d22a3b1aa77ba28a47335e03a3d26200fe64
GCLOUD_SHA256_DARWIN_X64=8159f5dc34e4229c2fb01567ba57f9b0ea1f68dd413884448124ccc85eb4a2fb
GCLOUD_SHA256_LINUX_X64=f865da648f6fdae2015abb5b32eaa0eb10520e88f0ca735cfb33795868c8d26f
GCLOUD_SHA256_LINUX_ARM64=3febb61a57ea76612973e40a2ff7bd79939161451d11130659d5c981201dca97

# Claude Code's native binary. claude.ai/install.sh always runs the newest
# build to install even a pinned version, so setup fetches this one directly.
# Once installed, Claude Code updates itself; this pins only the first install.
CLAUDE_VERSION=2.1.302
CLAUDE_SHA256_DARWIN_ARM64=5262ce9de86243fed0d21edc39b271555d56780d0112e2b194439fe1c6662d37
CLAUDE_SHA256_DARWIN_X64=b9a913114f42870ec8e38848c88c855d73f73187871ec2e1ad05bbe54029d9ac
CLAUDE_SHA256_LINUX_X64=60d7eb7f12fbb28a52533fe8be5884097403562aa02dc73991a021c7067e29a5
CLAUDE_SHA256_LINUX_ARM64=2bd4f4e5ed5cb09955b490098f745321cb5491e7ea8c752ba1e3bb010cdadb10

# Docker's apt signing key (fingerprint 9DC8 5822 9FC7 DD38 854A E2D8 8D81
# 803C 0EBF CD88). apt checks every package against it, so the key is what
# has to be right; it changes only if Docker rotates it.
DOCKER_APT_KEY_SHA256=1500c1f56fa9e26b9b8f42452a553675796ade0807cdce11975eb98170b3a570
