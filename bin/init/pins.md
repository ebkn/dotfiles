# Installer pins (`bin/init/pins.sh`)

Setup used to run `curl … | bash` against six URLs that answered with whatever
was newest: Homebrew's `install.sh` from `HEAD`, `get.volta.sh`,
`sdk.cloud.google.com`, `claude.ai/install.sh`, plus `volta install node`
and Docker's apt key. None had a version, none a checksum, and none sat behind
the 7-day holds the package managers have (`.npmrc`, `pip.conf`, `uv.toml`,
…). A compromised release or a hijacked endpoint ran on a new machine the
minute it was served.

Each one is now a version and a sha256 in `pins.sh`. `fetch_verified` in
`common.sh` downloads beside the destination and keeps the file only when it
hashes to the pin; an empty pin fails, so a missing line never means
"unchecked". `pinned_sha256 <TOOL>` picks `<TOOL>_SHA256_<OS>_<ARCH>` for this
machine and refuses a platform with no pin.

## What each pin covers, and what it does not

| Pin | Covers | Not covered |
| --- | --- | --- |
| `HOMEBREW_INSTALL_*` | the installer script | Homebrew itself: the script clones its latest tag, and `brew update` moves it from then on |
| `VOLTA_*` | the release tarball | — |
| `NODE_VERSION` | the default node | Volta does not check node against a checksum; HTTPS from nodejs.org only |
| `GCLOUD_*` | the SDK tarball; `update-all` updates components to the same version | components' own downloads (checked by gcloud against its manifest) |
| `CLAUDE_*` | the first install | Claude Code updates itself afterwards. `claude install <version>` may fetch that version again from Anthropic's server, checked against its manifest, not against `pins.sh` |
| `DOCKER_APT_KEY_SHA256` | the apt signing key | — apt checks every Docker package against the key |

## Bumping

Pick a release **at least 7 days old**, matching the other cooldowns. Replace
every checksum of that tool in the same commit: a version with an old checksum
fails setup loudly, which is the point, but on the next new machine instead of
in review.

```sh
# Homebrew/install: a commit, then the script's hash
gh api "repos/Homebrew/install/commits?until=<date>&per_page=1" --jq '.[0].sha'
curl -fsSL https://raw.githubusercontent.com/Homebrew/install/<sha>/install.sh | shasum -a 256

# Volta: one tarball per asset (macos is universal; linux, linux-arm)
curl -fsSL https://github.com/volta-cli/volta/releases/download/v<v>/volta-<v>-<asset>.tar.gz | shasum -a 256

# gcloud: darwin-arm, darwin-x86_64, linux-x86_64, linux-arm (~90 MB each)
curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-<v>-<asset>.tar.gz | shasum -a 256

# Claude Code: the build date, then the per-platform checksums
curl -fsSL https://downloads.claude.ai/claude-code-releases/<v>/manifest.json \
  | jq '.buildDate, (.platforms | with_entries(select(.key | test("^(darwin|linux)-(arm64|x64)$"))) | map_values(.checksum))'

# Docker's key: compare the fingerprint with docs.docker.com before hashing
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --show-keys --with-fingerprint
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | shasum -a 256
```

The Claude checksums come from Anthropic's own manifest, so they are only as
good as that server at the moment you read it; download one binary and hash it
yourself if a bump looks surprising.

The setup workflows exercise the `LINUX_X64` and `DARWIN_ARM64` pins on every
push. The other platforms' checksums are checked only on a machine of that
kind.
