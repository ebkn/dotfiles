#!/bin/bash
#
# links.test.sh
#
# Pins the linking half of setup: link_with_backup and backup_path
# (common.sh), link_dotfiles (links.sh) and bin/relink, which re-runs
# link_dotfiles on every update-all.
#
# Every way this goes wrong is quiet. A missing source is a warning and exit 0;
# check mode that touched the filesystem would make relink's "preview" the
# change itself; and the -ef guard exists because a destination reached through
# a parent directory symlinked into the repo used to have the REPO file moved
# out to ~/backup and replaced by a link to itself -- data loss, from a setup
# script, on a re-run.
#
# Everything runs against a throwaway $HOME and BACKUP_DIR, set for the whole
# run. The repository is this checkout, read only: a case that needs a source
# file makes its own.
#
# Written for bash 3.2 (/bin/bash on macOS).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
trap '/bin/rm -rf "$TMP"' EXIT
H="$TMP/home"
B="$TMP/backup"
R="$TMP/repo"
export HOME="$H" BACKUP_DIR="$B" DOTFILES_DIR="$ROOT"

fails=0
t() { # t <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}
kind() { # what is at a path: link -> target, file:<content>, dir, or absent
  if [ -L "$1" ]; then
    printf 'link -> %s' "$(readlink "$1")"
  elif [ -f "$1" ]; then
    printf 'file:%s' "$(cat "$1")"
  elif [ -d "$1" ]; then
    printf 'dir'
  else
    printf 'absent'
  fi
}

# lib <command...> -- run one command with common.sh and links.sh sourced, in a
# subshell so nothing leaks between cases, then print the LINK_DRIFT it left.
# common.sh installs an ERR trap meant for the init scripts; it is dropped, as
# bin/relink does. The command's status is the subshell's.
lib() {
  (
    # shellcheck source=bin/init/common.sh
    . "$ROOT/bin/init/common.sh"
    # shellcheck source=bin/init/links.sh
    . "$ROOT/bin/init/links.sh"
    trap - ERR
    LINK_DRIFT=0
    "$@"
    rc=$?
    echo "drift=$LINK_DRIFT"
    exit "$rc"
  )
}
fresh() {
  /bin/rm -rf "${H:?}" "${B:?}" "${R:?}"
  mkdir -p "$H" "$R"
  printf 'repo content' >"$R/conf"
}
# Everything in $HOME, except ~/.cache/rosetta: Rosetta's x86 emulation writes
# that into any $HOME when the CI-matching amd64 container runs on Apple
# silicon. It is the container's, not the code's, and the runner has none.
home_contents() { find "$H" -mindepth 1 ! -path "$H/.cache" ! -path "$H/.cache/rosetta*" | sort; }

# --- link_with_backup ---------------------------------------------------------

fresh
lib link_with_backup "$R/conf" "$H/.conf" >/dev/null
t "an absent destination becomes a link to the source" "link -> $R/conf" "$(kind "$H/.conf")"

fresh
out=$(lib link_with_backup "$R/nope" "$H/.nope" 2>&1)
rc=$?
t "a missing source is skipped with a warning" "1" "$(printf '%s' "$out" | grep -c 'missing source for link')"
t "and returns 0, so a setup run carries on" "0" "$rc"
t "and creates nothing" "absent" "$(kind "$H/.nope")"

# A real file at the destination is the user's: it is moved out, byte for byte,
# before the link takes its place.
fresh
printf 'mine' >"$H/.conf"
lib link_with_backup "$R/conf" "$H/.conf" >/dev/null
t "a real file at the destination is backed up" "file:mine" "$(kind "$B/.conf")"
t "and replaced by the link" "link -> $R/conf" "$(kind "$H/.conf")"

# Already right: nothing moves, nothing is backed up.
fresh
ln -s "$R/conf" "$H/.conf"
lib link_with_backup "$R/conf" "$H/.conf" >/dev/null
t "a correct link is left alone" "link -> $R/conf" "$(kind "$H/.conf")"
t "with nothing backed up" "absent" "$(kind "$B")"

# The data-loss regression. ~/.cfg is itself a link into the repo, so
# ~/.cfg/conf is a REAL file that already IS the repo file. Without the -ef
# guard, backup_path moved the repo file to ~/backup and ln -s left a link to
# itself in its place.
fresh
mkdir -p "$R/cfg"
printf 'repo content' >"$R/cfg/conf"
ln -s "$R/cfg" "$H/.cfg"
lib link_with_backup "$R/cfg/conf" "$H/.cfg/conf" >/dev/null
t "a destination reached through a symlinked parent leaves the repo file intact" \
  "file:repo content" "$(kind "$R/cfg/conf")"
t "and backs nothing up" "absent" "$(kind "$B")"

# --- check mode (LINK_CHECK=1) ---------------------------------------------------
# What relink shows before asking. It must report and record, and change nothing:
# a preview that applied itself would make the [y/N] a formality.

fresh
printf 'mine' >"$H/.conf"
out=$(LINK_CHECK=1 lib link_with_backup "$R/conf" "$H/.conf")
t "check mode reports a real file in the way as drift" "1" "$(printf '%s' "$out" | grep -c '^drift: ')"
t "and records it" "1" "$(printf '%s' "$out" | grep -cx 'drift=1')"
t "and leaves the file where it was" "file:mine" "$(kind "$H/.conf")"
t "with nothing backed up" "absent" "$(kind "$B")"

fresh
out=$(LINK_CHECK=1 lib link_with_backup "$R/conf" "$H/.conf")
t "check mode reports an absent link as missing" "1" "$(printf '%s' "$out" | grep -c '^missing: ')"
t "and creates nothing" "absent" "$(kind "$H/.conf")"

# A script moved inside bin/ leaves ~/.local/bin/<name> dangling, and every
# caller sends stderr to /dev/null -- so this is the one place it shows.
fresh
mkdir -p "$H/.local/bin"
ln -s "$R/old-name" "$H/.local/bin/tool"
out=$(LINK_CHECK=1 lib link_with_backup "$R/conf" "$H/.local/bin/tool")
t "a dangling link is reported as drift" "1" "$(printf '%s' "$out" | grep -c '^drift: ')"
lib link_with_backup "$R/conf" "$H/.local/bin/tool" >/dev/null
t "and re-pointed when applied" "link -> $R/conf" "$(kind "$H/.local/bin/tool")"

# --- backup_path ------------------------------------------------------------------
# A name already in ~/backup gets a timestamped copy rather than overwriting it.
# Within one second the timestamp repeats -- and setup backs up two files with
# one basename back to back (two settings.json, two AGENTS.md) -- so a second
# collision in the same second must not overwrite the first either.
both_backups() {
  backup_path "$H/a/settings.json"
  backup_path "$H/b/settings.json"
}
fresh
mkdir -p "$B" "$H/a" "$H/b"
printf 'oldest' >"$B/settings.json"
printf 'first' >"$H/a/settings.json"
printf 'second' >"$H/b/settings.json"
lib both_backups >/dev/null
t "an existing backup is never overwritten" "file:oldest" "$(kind "$B/settings.json")"
t "and every later backup of the same name is kept" "first second" \
  "$(for f in "$B"/settings.json.*; do [ -f "$f" ] && cat "$f" && echo; done | sort | tr '\n' ' ' | sed 's/ $//')"

# --- link_dotfiles over a fresh $HOME ---------------------------------------------
# The real list, against this checkout. Check mode on an empty home must only
# report: the one missing source it may warn about is ~/CLAUDE.md, the source of
# the chained ~/AGENTS.md link, which check mode has not created. Any other
# missing source is a typo in links.sh -- the link would never be made, and
# relink would never notice.
fresh
/bin/rm -rf "${R:?}"
out=$(LINK_CHECK=1 lib link_dotfiles 2>&1)
t "check mode on an empty home warns only about the chained CLAUDE.md" "$H/CLAUDE.md" \
  "$(printf '%s\n' "$out" | sed -n 's/^warning: missing source for link (skipping): \(.*\) -> .*/\1/p')"
t "and creates nothing at all" "" "$(home_contents)"
out=$(lib link_dotfiles 2>&1)
t "applying it warns about no missing source" "0" "$(printf '%s\n' "$out" | grep -c 'missing source')"
out=$(LINK_CHECK=1 lib link_dotfiles 2>&1)
t "after which a check finds no drift" "drift=0" "$(printf '%s\n' "$out" | tail -n 1)"
# Skills are linked one by one so the consumer dir stays a real directory, and a
# tool installing a skill there writes outside the repo.
t "the Claude skills dir is a real directory, not a link into the repo" "dir" "$(kind "$H/.claude/skills")"
t "holding a link per owned skill" "link -> $ROOT/root/.agents/skills/review-test" \
  "$(kind "$H/.claude/skills/review-test")"

# --- relink ---------------------------------------------------------------------
# It previews, asks, and applies only on yes; and it never loads launchd agents,
# which is a decision about the machine that bin/launchd-load makes on request.
mkdir -p "$TMP/stub"
cat >"$TMP/stub/launchctl" <<STUB
#!/bin/sh
echo "\$*" >>"$TMP/launchctl.log"
STUB
chmod +x "$TMP/stub/launchctl"
relink_with() { # relink_with <answer>
  printf '%s\n' "$1" | PATH="$TMP/stub:$PATH" bash "$ROOT/bin/relink" 2>&1
}
fresh
/bin/rm -rf "${R:?}"
out=$(relink_with n)
# (The [y/N] prompt has no newline, so the answer's line starts with it.)
t "relink answered no says it skipped" "1" "$(printf '%s\n' "$out" | grep -c '\[y/N\] skipped\.$')"
t "and creates nothing" "" "$(home_contents)"
relink_with y >/dev/null
t "relink answered yes applies the links" "link -> $ROOT/.tmux.conf" "$(kind "$H/.tmux.conf")"
out=$(relink_with n)
t "after which it reports nothing to do" "dotfiles symlinks are up to date." "$(printf '%s\n' "$out" | tail -n 1)"
t "and it never touched launchctl" "absent" "$(kind "$TMP/launchctl.log")"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
