# Image for bin/test-in-docker: the GitHub runner, as far as the tmux suites
# can tell. See bin/test-in-docker.md for why each line is here -- every
# difference from the runner is a failure this container would invent.
#
# linux/amd64 (passed by bin/test-in-docker) even on Apple Silicon: the runner
# is amd64, and the fzf pin below is the amd64 tarball's checksum.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# bsdutils carries script(1), which the suites use to hand tmux a pty;
# less (tmux-cheatsheet pages through it), netcat-openbsd and procps are on the
# runner image and absent here.
RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
    ca-certificates curl git jq less zsh bsdutils netcat-openbsd procps \
    build-essential libevent-dev libncurses-dev pkg-config bison \
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

# Same as the "Install fzf" step in the workflow.
RUN version=0.74.3 \
  && expected=3501a595e4b5c40a6b047340a0e8f805c46fd4e61ef95ef8a136ba8c61cf6f22 \
  && cd /tmp \
  && curl -fsSL -o fzf.tar.gz \
    "https://github.com/junegunn/fzf/releases/download/v${version}/fzf-${version}-linux_amd64.tar.gz" \
  && echo "${expected}  fzf.tar.gz" | sha256sum --check --strict \
  && tar -xzf fzf.tar.gz \
  && install -m 0755 fzf /usr/local/bin/fzf \
  && rm -f fzf fzf.tar.gz

# UTF-8, or tmux renders every wide glyph as `_`. The runner has it.
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# A non-root user, or the kernel ignores the chmod a permission case sets up
# and the case reports a bug that does not exist. The repo is mounted from the
# host with another owner, which git refuses without safe.directory.
RUN useradd -m tester \
  && su tester -c "git config --global safe.directory '*'"
USER tester
WORKDIR /work
