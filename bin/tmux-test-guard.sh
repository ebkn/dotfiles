# shellcheck shell=bash
#
# Sourced by every tmux suite: each bin/tmux-*.test.sh, and any suite that
# invokes tmux new-session or kill-server. Refuses to run anywhere but a
# container or CI. bin/tmux-test-guard.test.sh enforces the enrollment.
#
# The ones with a real server isolate themselves with TMUX_TMPDIR, and that is
# not enough on a developer machine: tmux prefers the socket named in $TMUX
# over TMUX_TMPDIR, so one missed `unset TMUX` sends new-session, send-keys and kill-server to
# the developer's own server. That happened -- a one-off probe killed every
# local session. Remembering the unset is the thing that already failed once,
# so the host is taken out of reach instead. See bin/test-in-docker.md.
#
# /.dockerenv marks a Docker container; GITHUB_ACTIONS marks the CI runner,
# which is disposable in the same way.
if [ ! -f /.dockerenv ] && [ "${GITHUB_ACTIONS:-}" != true ]; then
  echo "${0##*/}: a tmux suite; run it with bin/test-in-docker" >&2
  exit 2
fi
