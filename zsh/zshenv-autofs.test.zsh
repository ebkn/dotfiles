#!/usr/bin/env zsh
# Unit test for the platform guard on .zshenv's Linuxbrew probe.
#
# macOS ships /home in /etc/auto_master as an autofs map, so *any* stat under
# /home wakes automountd. Measured here: ~16ms for a path that cannot exist on
# a Mac, against ~1ms for an ordinary missing path. .zshenv is read by every
# `zsh -c`, not just by login shells, so that stat was being paid by every git
# hook and by every tmux display-popup -- it was the single largest item in the
# prefix + a latency this test was written for.
#
# The failure mode is why this is worth pinning: dropping the guard costs no
# error, no output and no wrong behaviour. PATH ends up identical. The only
# symptom is that everything gets slower, which nobody attributes to a probe
# for a directory that was never going to be there.
#
# So the assertion is on whether the /home probe *executes*, read from xtrace,
# rather than on elapsed time -- a timing assertion would be flaky on a loaded
# machine and in CI. $OSTYPE is a plain parameter, so both branches can be
# driven from either platform and macOS and Linux runs assert the same thing.
#
# Run: zsh zsh/zshenv-autofs.test.zsh   (exit 0 = pass)

set -u

repo="${0:A:h:h}"
typeset -i failures=0

check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "$want" "$got"
    (( failures++ ))
  fi
}

# -f so the real ~/.zshenv and ~/.zshrc stay out of it; the file under test is
# sourced explicitly. OSTYPE is assigned before the source so the guard sees it.
probes_home() {
  local ostype="$1" trace
  trace=$(zsh -f -c "OSTYPE=$ostype; setopt xtrace; source ${(q)repo}/.zshenv" 2>&1)
  if [[ "$trace" == *"-d /home/linuxbrew"* ]]; then print yes; else print no; fi
}

check 'macOS does not stat /home (autofs would wake automountd)' \
  no "$(probes_home darwin25.0)"

check 'Linux still probes for Linuxbrew' \
  yes "$(probes_home linux-gnu)"

# The guard must not change what ends up on PATH where Linuxbrew is real, and
# must not add it where it is not. Checked through PATH itself, because the
# xtrace assertions above would still pass if the export moved outside the if.
path_has_linuxbrew() {
  local ostype="$1" p
  p=$(zsh -f -c "OSTYPE=$ostype; source ${(q)repo}/.zshenv; print -r -- \$PATH")
  if [[ "$p" == *"/home/linuxbrew/.linuxbrew/bin"* ]]; then print yes; else print no; fi
}

check 'macOS PATH never gains a Linuxbrew entry' \
  no "$(path_has_linuxbrew darwin25.0)"

# On a Mac /home/linuxbrew does not exist, so the Linux branch correctly adds
# nothing; asserting the directory's presence is what makes this meaningful, so
# the expectation is derived from the filesystem rather than hard-coded.
if [[ -d /home/linuxbrew/.linuxbrew/bin ]]; then want=yes; else want=no; fi
check 'the Linux branch adds Linuxbrew exactly when it is installed' \
  "$want" "$(path_has_linuxbrew linux-gnu)"

if (( failures )); then
  printf '\nFAIL=%d\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
