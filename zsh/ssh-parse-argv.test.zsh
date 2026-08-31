#!/usr/bin/env zsh
# Unit tests for _ssh_parse_argv (zsh/alias.zsh).
#
# The function walks an ssh argument list the same way ssh itself does, to find
# which argument is the target host. Everything downstream depends on getting
# that right: `ssh` publishes it as @ssh_host (pane colour, status bar, and the
# host list bin/tmux-agents queries over ssh), and `myssh` hands it to autossh
# as the connection target. A misread host is therefore not a cosmetic slip —
# it points the reconnect at the wrong place.
#
# The one thing that can rot here is the list of options that take a separate
# argument: it is a hand-copied subset of ssh(1), so every openssh release that
# adds one silently breaks the parse. That is what most of these cases pin.
#
# Run: zsh zsh/ssh-parse-argv.test.zsh   (exit 0 = pass)

set -u

# Sourcing the whole module is deliberate: the test should exercise the
# function as the shell actually gets it, not a copy pasted in here.
source "${0:A:h}/ssh.zsh"

typeset -i failures=0

# assert <description> <expected-host> <expected-remote-cmd> -- <argv...>
assert() {
  local desc="$1" want_host="$2" want_cmd="$3"
  shift 4  # description, host, cmd, and the literal --
  _ssh_parse_argv "$@"
  if [[ "$_SSH_PARSE_HOST" != "$want_host" ]]; then
    printf 'FAIL %s\n  host: want %-12s got %s\n' \
      "$desc" "'$want_host'" "'$_SSH_PARSE_HOST'"
    (( failures++ ))
    return
  fi
  if [[ "$_SSH_PARSE_HAS_REMOTE_CMD" != "$want_cmd" ]]; then
    printf 'FAIL %s\n  remote cmd: want %s got %s\n' \
      "$desc" "$want_cmd" "$_SSH_PARSE_HAS_REMOTE_CMD"
    (( failures++ ))
    return
  fi
  printf 'ok   %s\n' "$desc"
}

assert 'bare host'                     myhost false -- myhost
assert 'user@host'                     me@myhost false -- me@myhost
assert 'flag taking no argument'       myhost false -- -v myhost
assert 'option argument, detached'     myhost false -- -p 2222 myhost
assert 'option argument, attached'     myhost false -- -p2222 myhost
assert 'repeated -o'                   myhost false -- -o Foo=bar -o Baz=qux myhost
assert 'remote command follows host'   myhost true  -- myhost ls -l
assert 'no host at all'                '' false -- -v

# Regression: -B (bind_interface) and -P (tag) both take a separate argument in
# ssh(1) but were missing from the option list, so their value was read as the
# host. Verified against the ssh(1) manual, not inferred.
assert 'ssh -B takes an argument'      myhost false -- -B en0 myhost
assert 'ssh -P takes an argument'      myhost false -- -P mytag myhost

# A remote command after an option-with-argument must still be seen as one:
# the argument must not be mistaken for the host and swallow the real one.
assert 'option argument then command'  myhost true  -- -p 2222 myhost uptime

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
