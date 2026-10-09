#!/bin/bash
#
# relink.test.sh
#
# Pins the code that moves real files out of $HOME: link_with_backup and
# backup_path (bin/init/common.sh), and bin/relink, which runs them over
# link_dotfiles (bin/init/links.sh) on every update-all. The contract:
#
#   - a link is created where nothing is, and left alone where it is right;
#   - anything else at the destination is moved to $BACKUP_DIR first, intact,
#     and no backup ever replaces an earlier one;
#   - a destination that already IS the source through a symlinked parent is
#     left alone -- moving it would move the repo's own file (25339e9);
#   - LINK_CHECK=1 reports and touches nothing;
#   - relink applies only on an explicit yes.
#
# Every case runs against a throwaway $HOME and $BACKUP_DIR. The unit cases use
# a small fake repo; the relink cases read the real checkout (only read: every
# link points into it, nothing is written there).

set -u

DIR=$(mktemp -d)
REPO="$(cd "$(dirname "$0")/.." && pwd)"
fails=0
trap 'rm -rf "$DIR"' EXIT

ok() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  [ -z "${2-}" ] || printf '     %s\n' "$2"
  fails=$((fails + 1))
}
eq() { # <name> <want> <got>
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "want [$2], got [$3]"; fi
}
has() { # <name> <haystack> <needle>
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) fail "$1" "missing: $3" ;;
  esac
}
lacks() { # <name> <haystack> <needle>
  case "$2" in
    *"$3"*) fail "$1" "present: $3" ;;
    *) ok "$1" ;;
  esac
}
# The whole tree, with each link's target, so "nothing changed" means it.
# .cache is pruned: under amd64 emulation on Apple Silicon (bin/test-in-docker)
# Rosetta writes $HOME/.cache/rosetta for every process, and link_dotfiles
# never touches .cache, so it can only be noise.
snapshot() {
  find "$1" -name .cache -prune -o -print | sort | while IFS= read -r p; do
    if [ -L "$p" ]; then
      printf '%s -> %s\n' "$p" "$(readlink "$p")"
    elif [ -f "$p" ]; then
      printf '%s = %s\n' "$p" "$(cat "$p")"
    else
      printf '%s/\n' "$p"
    fi
  done
}

# A fresh $HOME, $BACKUP_DIR and fake repo for each unit case. The functions
# run in a subshell per case (see `unit`), so nothing leaks between them.
fresh() {
  rm -rf "$DIR/case"
  H="$DIR/case/home"
  B="$DIR/case/backup"
  R="$DIR/case/repo"
  mkdir -p "$H" "$R/rules" "$R/conf.d"
  printf 'repo-rc\n' >"$R/rc"
  printf 'repo-rules\n' >"$R/rules/default.rules"
  printf 'repo-conf\n' >"$R/conf.d/a.conf"
}
# Runs link_with_backup and friends as relink does: common.sh sourced, its ERR
# trap dropped. `date` is pinned so every backup in a case lands in the same
# second -- the condition under which two of them can collide.
unit() { # <command> [args...]
  mkdir -p "$DIR/stub"
  printf '#!/bin/sh\necho 20260101000000\n' >"$DIR/stub/date"
  chmod +x "$DIR/stub/date"
  (
    export HOME="$H" BACKUP_DIR="$B" PATH="$DIR/stub:$PATH"
    # shellcheck source=bin/init/common.sh
    . "$REPO/bin/init/common.sh"
    trap - ERR
    "$@"
  ) >"$DIR/out" 2>"$DIR/err"
}

# --- link_with_backup ---------------------------------------------------------
fresh
unit link_with_backup "$R/rc" "$H/.rc"
eq "nothing at dest: a link to the source is created" "$R/rc" "$(readlink "$H/.rc")"
eq "and nothing is backed up" "" "$(ls -A "$B" 2>/dev/null)"

fresh
printf 'mine\n' >"$H/.rc"
unit link_with_backup "$R/rc" "$H/.rc"
eq "a real file at dest is replaced by the link" "$R/rc" "$(readlink "$H/.rc")"
eq "and arrives in the backup dir intact" "mine" "$(cat "$B/.rc")"

fresh
mkdir -p "$H/.config/app"
printf 'mine\n' >"$H/.config/app/x"
unit link_with_backup "$R/conf.d" "$H/.config/app"
eq "a real directory at dest is replaced by the link" "$R/conf.d" "$(readlink "$H/.config/app")"
eq "and arrives in the backup dir with its contents" "mine" "$(cat "$B/app/x")"

fresh
ln -s "$R/rc" "$H/.rc"
before=$(snapshot "$DIR/case")
unit link_with_backup "$R/rc" "$H/.rc"
eq "a correct link is left exactly as it was" "$before" "$(snapshot "$DIR/case")"
eq "and says nothing" "" "$(cat "$DIR/out" "$DIR/err")"

fresh
ln -s "$DIR/elsewhere" "$H/.rc"
unit link_with_backup "$R/rc" "$H/.rc"
eq "a link pointing elsewhere is replaced" "$R/rc" "$(readlink "$H/.rc")"
eq "and the old link is kept in the backup dir" "$DIR/elsewhere" "$(readlink "$B/.rc")"

fresh
unit link_with_backup "$R/nope" "$H/.nope"
has "a missing source is warned about on stderr" "$(cat "$DIR/err")" "missing source"
if [ -e "$H/.nope" ] || [ -L "$H/.nope" ]; then
  fail "and no link is created for it"
else
  ok "and no link is created for it"
fi

# The 25339e9 bug: dest's parent is itself a symlink into the repo, so dest is
# the repo file. Backing it up would move the repo's own file out.
for mode in apply check; do
  fresh
  mkdir -p "$H/.codex"
  ln -s "$R/rules" "$H/.codex/rules"
  before=$(snapshot "$DIR/case")
  if [ "$mode" = check ]; then
    LINK_CHECK=1 unit link_with_backup "$R/rules/default.rules" "$H/.codex/rules/default.rules"
  else
    unit link_with_backup "$R/rules/default.rules" "$H/.codex/rules/default.rules"
  fi
  eq "$mode: a dest reached through a symlinked parent is left alone" "$before" "$(snapshot "$DIR/case")"
done

# --- LINK_CHECK=1 ----------------------------------------------------------------
fresh
ln -s "$R/rc" "$H/.ok"
ln -s "$DIR/elsewhere" "$H/.drifted"
printf 'mine\n' >"$H/.real"
before=$(snapshot "$DIR/case")
check_all() {
  LINK_DRIFT=0
  LINK_CHECK=1 link_with_backup "$R/rc" "$H/.ok"
  echo "after-ok:$LINK_DRIFT"
  LINK_CHECK=1 link_with_backup "$R/rc" "$H/.missing"
  LINK_CHECK=1 link_with_backup "$R/rc" "$H/.drifted"
  LINK_CHECK=1 link_with_backup "$R/rc" "$H/.real"
  echo "after-all:$LINK_DRIFT"
}
unit check_all
out=$(cat "$DIR/out")
eq "check mode changes nothing on disk" "$before" "$(snapshot "$DIR/case")"
has "a correct link does not count as drift" "$out" "after-ok:0"
has "an absent link is reported as missing" "$out" "missing: $H/.missing -> $R/rc"
has "a link pointing elsewhere is reported as drift" "$out" "drift:   $H/.drifted does not point to $R/rc"
has "a real file is reported as drift" "$out" "drift:   $H/.real does not point to $R/rc"
has "and drift is recorded for relink" "$out" "after-all:1"
lacks "a correct link is not reported" "$out" "$H/.ok"

# --- relink, over the real link_dotfiles ---------------------------------------
relink_run() { # <stdin text or -> ; uses $RH as HOME
  if [ "$1" = - ]; then
    HOME="$RH" BACKUP_DIR="$RH/backup" DOTFILES_DIR="$REPO" "$REPO/bin/relink" \
      </dev/null >"$DIR/out" 2>"$DIR/err"
  else
    printf '%s\n' "$1" | HOME="$RH" BACKUP_DIR="$RH/backup" DOTFILES_DIR="$REPO" \
      "$REPO/bin/relink" >"$DIR/out" 2>"$DIR/err"
  fi
}
RH="$DIR/relink-home"

for answer in n -; do
  rm -rf "$RH"
  mkdir -p "$RH"
  [ "$answer" = - ] && label="EOF" || label="answering $answer"
  relink_run "$answer"
  out=$(cat "$DIR/out")
  has "$label: the drift is listed before asking" "$out" "missing: $RH/.tmux.conf"
  has "$label: prints skipped." "$out" "skipped."
  eq "$label: creates nothing" "$RH/" "$(snapshot "$RH")"
done

rm -rf "$RH"
mkdir -p "$RH"
printf 'mine\n' >"$RH/.tigrc"
relink_run y
eq "answering y creates the links" "$REPO/.tmux.conf" "$(readlink "$RH/.tmux.conf")"
eq "and backs up a real file in the way" "mine" "$(cat "$RH/backup/.tigrc")"
# Scoped to the checkout: ~/AGENTS.md links to ~/CLAUDE.md, which on an empty
# $HOME does not exist yet during the check pass and is warned about there --
# the apply pass creates ~/CLAUDE.md first, which the next assertion pins.
lacks "every source link_dotfiles names exists in the checkout" \
  "$(cat "$DIR/err")" "missing source for link (skipping): $REPO/"
eq "a link chained through another link is created on apply" "$RH/CLAUDE.md" "$(readlink "$RH/AGENTS.md")"
relink_run -
out=$(cat "$DIR/out")
eq "a second run finds nothing to do" "dotfiles symlinks are up to date." "$out"

rm -rf "$RH"
mkdir -p "$RH"
if HOME="$RH" DOTFILES_DIR="$DIR/no-such-repo" "$REPO/bin/relink" </dev/null >"$DIR/out" 2>"$DIR/err"; then
  fail "a missing dotfiles dir exits non-zero"
else
  ok "a missing dotfiles dir exits non-zero"
fi
has "and names the directory it looked for" "$(cat "$DIR/err")" "dotfiles dir not found: $DIR/no-such-repo"
eq "and creates nothing" "$RH/" "$(snapshot "$RH")"

if [ "$fails" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$fails failure(s)"
  exit 1
fi
