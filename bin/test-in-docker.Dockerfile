# Image for bin/test-in-docker: the GitHub runner, as far as the tmux suites
# can tell. See bin/test-in-docker.md for why each line is here -- every
# difference from the runner is a failure this container would invent.
#
# Built for the host's architecture unless bin/test-in-docker is told
# otherwise (TEST_DOCKER_PLATFORM): the runner is amd64, but emulating it on
# Apple silicon made the tmux suites take ~60 s against ~8 s. So the
# downloaded binaries below carry a checksum for each of amd64 and arm64; the
# amd64 one is the workflow's.
FROM ubuntu:24.04

# Set by BuildKit to the platform being built: amd64 or arm64.
ARG TARGETARCH

ARG DEBIAN_FRONTEND=noninteractive

# bsdutils carries script(1), which the suites use to hand tmux a pty;
# less (tmux-cheatsheet pages through it), netcat-openbsd, procps and
# openssh-client (relink.test.sh resolves configs with ssh -G) and nodejs
# (textlint/rules.test.sh runs the local textlint rules) are on the runner
# image and absent here.
RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
    ca-certificates curl git jq less zsh bsdutils netcat-openbsd procps openssh-client nodejs \
    build-essential libevent-dev libncurses-dev pkg-config bison bzip2 \
  && rm -rf /var/lib/apt/lists/*

# Same version, source and checksum as the "Install tmux" step in
# .github/workflows/lint-and-test.yml. Bump all three places together.
RUN version=3.7c \
  && expected=7c60cae9a0e25288e2e24750aafc9e8800fc7fd4555e447e1b29ee4201cfb3bf \
  && cd /tmp \
  && curl -fsSL -o tmux.tar.gz \
    "https://github.com/tmux/tmux/releases/download/${version}/tmux-${version}.tar.gz" \
  && echo "${expected}  tmux.tar.gz" | sha256sum --check --strict \
  && tar -xzf tmux.tar.gz \
  && cd "tmux-${version}" \
  && ./configure --prefix=/usr/local >/dev/null \
  && make -j"$(nproc)" >/dev/null \
  && make install >/dev/null \
  && cd / && rm -rf /tmp/tmux*

# Same as the "Install fzf" step in the workflow and the fzf note in
# brewfiles/Brewfile-shell. Bump all three places together, and the arm64
# checksum with them (fzf_<version>_checksums.txt on the release).
RUN version=0.74.3 \
  && case "$TARGETARCH" in \
    amd64) expected=3501a595e4b5c40a6b047340a0e8f805c46fd4e61ef95ef8a136ba8c61cf6f22 ;; \
    arm64) expected=4a17a17b46bd0c4873e995533de508995c11572c0be0664a5dbcf13f60463046 ;; \
    *) echo "no fzf checksum for $TARGETARCH" >&2; exit 1 ;; \
  esac \
  && cd /tmp \
  && curl -fsSL -o fzf.tar.gz \
    "https://github.com/junegunn/fzf/releases/download/v${version}/fzf-${version}-linux_${TARGETARCH}.tar.gz" \
  && echo "${expected}  fzf.tar.gz" | sha256sum --check --strict \
  && tar -xzf fzf.tar.gz \
  && install -m 0755 fzf /usr/local/bin/fzf \
  && rm -f fzf fzf.tar.gz

# Same as the "Install pandoc" step in the workflow and the pandoc note in
# brewfiles/Brewfile-shell. Bump all three places together. read-doc.test.sh
# asserts on pandoc's rendered HTML, and read-doc needs --syntax-highlighting,
# which older distro packages do not have. pandoc publishes no checksum file;
# the arm64 one is the sha256 of the release asset.
RUN version=3.12 \
  && case "$TARGETARCH" in \
    amd64) expected=67d7d011fed8c8543306022b985b9b2499ab9b74818df91d8727c7e9ebc5ba06 ;; \
    arm64) expected=6cefcf7100e23a99447c26f89d1ff5b253f3407fcef99a9e27ae06f3ed16cb82 ;; \
    *) echo "no pandoc checksum for $TARGETARCH" >&2; exit 1 ;; \
  esac \
  && cd /tmp \
  && curl -fsSL -o pandoc.tar.gz \
    "https://github.com/jgm/pandoc/releases/download/${version}/pandoc-${version}-linux-${TARGETARCH}.tar.gz" \
  && echo "${expected}  pandoc.tar.gz" | sha256sum --check --strict \
  && tar -xzf pandoc.tar.gz \
  && install -m 0755 "pandoc-${version}/bin/pandoc" /usr/local/bin/pandoc \
  && rm -rf pandoc.tar.gz "pandoc-${version}"

# Same as the "Install GNU parallel" step in the workflow and the parallel note
# in brewfiles/Brewfile-shell. Bump all three places together. bin/test
# schedules the suites with it, here as on the runner: test-in-docker runs its
# suites through bin/test inside this image. bzip2 (above) unpacks the
# tarball; perl, which parallel is written in, comes with build-essential.
RUN version=20260922 \
  && expected=54837e9e8c16134a3c2e95f91c5fe2f7893d4cc89f252b26735713ceca866387 \
  && cd /tmp \
  && curl -fsSL -o parallel.tar.bz2 \
    "https://ftp.gnu.org/gnu/parallel/parallel-${version}.tar.bz2" \
  && echo "${expected}  parallel.tar.bz2" | sha256sum --check --strict \
  && tar -xjf parallel.tar.bz2 \
  && cd "parallel-${version}" \
  && ./configure --prefix=/usr/local >/dev/null \
  && make install >/dev/null \
  && cd / && rm -rf /tmp/parallel*

# UTF-8, or tmux renders every wide glyph as `_`. The runner has it.
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# A non-root user, or the kernel ignores the chmod a permission case sets up
# and the case reports a bug that does not exist. The repo is mounted from the
# host with another owner, which git refuses without safe.directory.
RUN useradd -m tester \
  && su tester -c "git config --global safe.directory '*'"
USER tester
WORKDIR /work
