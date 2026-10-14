# Image for bin/test-in-docker: the GitHub runner, as far as the tmux suites
# can tell. See bin/test-in-docker.md for why each line is here -- every
# difference from the runner is a failure this container would invent.
#
# linux/amd64 (passed by bin/test-in-docker) even on Apple Silicon: the runner
# is amd64, and the fzf pin below is the amd64 tarball's checksum.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# bsdutils carries script(1), which the suites use to hand tmux a pty;
# less (tmux-cheatsheet pages through it), netcat-openbsd, procps and
# openssh-client (relink.test.sh resolves configs with ssh -G) are on the runner
# image and absent here.
RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
    ca-certificates curl git jq less zsh bsdutils netcat-openbsd procps openssh-client \
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
# brewfiles/Brewfile-shell. Bump all three places together.
RUN version=0.74.3 \
  && expected=3501a595e4b5c40a6b047340a0e8f805c46fd4e61ef95ef8a136ba8c61cf6f22 \
  && cd /tmp \
  && curl -fsSL -o fzf.tar.gz \
    "https://github.com/junegunn/fzf/releases/download/v${version}/fzf-${version}-linux_amd64.tar.gz" \
  && echo "${expected}  fzf.tar.gz" | sha256sum --check --strict \
  && tar -xzf fzf.tar.gz \
  && install -m 0755 fzf /usr/local/bin/fzf \
  && rm -f fzf fzf.tar.gz

# Same as the "Install pandoc" step in the workflow and the pandoc note in
# brewfiles/Brewfile-shell. Bump all three places together. read-doc.test.sh
# asserts on pandoc's rendered HTML, and read-doc needs --syntax-highlighting,
# which older distro packages do not have.
RUN version=3.12 \
  && expected=67d7d011fed8c8543306022b985b9b2499ab9b74818df91d8727c7e9ebc5ba06 \
  && cd /tmp \
  && curl -fsSL -o pandoc.tar.gz \
    "https://github.com/jgm/pandoc/releases/download/${version}/pandoc-${version}-linux-amd64.tar.gz" \
  && echo "${expected}  pandoc.tar.gz" | sha256sum --check --strict \
  && tar -xzf pandoc.tar.gz \
  && install -m 0755 "pandoc-${version}/bin/pandoc" /usr/local/bin/pandoc \
  && rm -rf pandoc.tar.gz "pandoc-${version}"

# Same as the "Install GNU parallel" step in the workflow and the parallel note
# in brewfiles/Brewfile-shell. Bump all three places together. bin/test
# schedules the suites with it; installed ahead of test-in-docker running its
# suites through bin/test (testing.md, migration step 4) -- today the
# container's loop still runs them one by one. bzip2 (above) unpacks the
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
