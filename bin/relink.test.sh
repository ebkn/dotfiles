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
#   - a missing source is a warning and exit 0, so a setup run carries on;
#   - LINK_CHECK=1 reports and touches nothing, a dangling link included;
#   - every source link_dotfiles names exists, and one apply leaves no drift;
#   - relink applies only on an explicit yes, never calls launchctl, and an
#     apply that left a link missing or wrong exits non-zero rather than saying
#     "done.";
#   - ensure_ssh_base_include leaves the shared ssh defaults applying to every
#     host while each host's own value still wins (see its section).
#
# Every case runs against a throwaway $HOME and $BACKUP_DIR. The unit cases use
# a small fake repo; the relink cases read the real checkout (only read: every
# link points into it, nothing is written there).

set -u

DIR=$(mktemp -d)
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# The caller's PATH, for the relink runs below to prepend their stub to. `unit`
# changes PATH only inside its subshell, so $PATH would do as well -- but the
# linter cannot tell, and flags every later read of it (SC2031).
BASE_PATH=$PATH
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
# .cache is pruned: under amd64 emulation on Apple Silicon (bin/test-in-docker
# with TEST_DOCKER_PLATFORM=linux/amd64)
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

# The target EXISTS: a link into an old checkout still resolves, and a check
# that took any live link for a correct one would leave it pointing there for
# good, with relink reporting "up to date". (A dangling one is the case below.)
fresh
mkdir -p "$DIR/case/old-checkout"
printf 'old-rc\n' >"$DIR/case/old-checkout/rc"
ln -s "$DIR/case/old-checkout/rc" "$H/.rc"
unit link_with_backup "$R/rc" "$H/.rc"
eq "a live link pointing elsewhere is replaced" "$R/rc" "$(readlink "$H/.rc")"
eq "and the old link is kept in the backup dir" "$DIR/case/old-checkout/rc" "$(readlink "$B/.rc")"

fresh
unit link_with_backup "$R/nope" "$H/.nope"
eq "a missing source returns 0, so a setup run carries on" "0" "$?"
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

# --- backups never replace one another -----------------------------------------
# $BACKUP_DIR/settings.json already exists from an earlier run, and two real
# files of that name are backed up in the same second. links.sh has several
# destinations sharing a basename (settings.json, AGENTS.md, each skill).
fresh
mkdir -p "$B" "$H/a" "$H/b"
printf 'old-backup\n' >"$B/settings.json"
printf 'first\n' >"$H/a/settings.json"
printf 'second\n' >"$H/b/settings.json"
two_backups() {
  link_with_backup "$R/rc" "$H/a/settings.json"
  link_with_backup "$R/rc" "$H/b/settings.json"
}
unit two_backups
kept=$(cat "$B"/settings.json* 2>/dev/null | sort | tr '\n' ' ')
eq "two same-second backups of one name and the earlier backup all survive" \
  "first old-backup second " "$kept"

# --- LINK_CHECK=1 ----------------------------------------------------------------
fresh
ln -s "$R/rc" "$H/.ok"
mkdir -p "$DIR/case/old-checkout"
printf 'old-rc\n' >"$DIR/case/old-checkout/rc"
ln -s "$DIR/case/old-checkout/rc" "$H/.drifted"
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

# A script moved inside bin/ leaves ~/.local/bin/<name> dangling, and every
# caller sends stderr to /dev/null -- so this is the one place it shows.
fresh
mkdir -p "$H/.local/bin"
ln -s "$R/old-name" "$H/.local/bin/tool"
LINK_CHECK=1 unit link_with_backup "$R/rc" "$H/.local/bin/tool"
has "a dangling link is reported as drift" "$(cat "$DIR/out")" "drift:   $H/.local/bin/tool"
unit link_with_backup "$R/rc" "$H/.local/bin/tool"
eq "and re-pointed when applied" "$R/rc" "$(readlink "$H/.local/bin/tool")"

# --- link_dotfiles over an empty $HOME -------------------------------------------
# The real list, against this checkout. Check mode on an empty home must only
# report: the one missing source it may warn about is ~/CLAUDE.md, the source
# of the chained ~/AGENTS.md link, which check mode has not created. Any other
# missing source is a typo in links.sh -- the link would never be made, and
# relink would never notice.
dotfiles() { # [LINK_CHECK=1] dotfiles -- link_dotfiles into $RH; prints the drift
  # shellcheck disable=SC2016 # expanded by the inner bash, against its own env
  HOME="$RH" BACKUP_DIR="$RH/backup" DOTFILES_DIR="$REPO" bash -c '
    . "$DOTFILES_DIR/bin/init/common.sh"
    . "$DOTFILES_DIR/bin/init/links.sh"
    trap - ERR
    LINK_DRIFT=0
    link_dotfiles
    echo "drift=$LINK_DRIFT"' >"$DIR/out" 2>"$DIR/err"
}
RH="$DIR/dotfiles-home"
rm -rf "$RH"
mkdir -p "$RH"
LINK_CHECK=1 dotfiles
eq "check mode on an empty home warns only about the chained CLAUDE.md" "$RH/CLAUDE.md" \
  "$(sed -n 's/^warning: missing source for link (skipping): \(.*\) -> .*/\1/p' "$DIR/err")"
eq "and creates nothing at all" "$RH/" "$(snapshot "$RH")"
dotfiles
eq "applying it warns about no missing source" "0" "$(grep -c 'missing source' "$DIR/err")"
LINK_CHECK=1 dotfiles
eq "after which a check finds no drift" "drift=0" "$(tail -n 1 "$DIR/out")"
# Skills are linked one by one so the consumer dir stays a real directory, and
# a tool installing a skill there writes outside the repo.
if [ -d "$RH/.claude/skills" ] && [ ! -L "$RH/.claude/skills" ]; then
  ok "the Claude skills dir is a real directory, not a link into the repo"
else
  fail "the Claude skills dir is a real directory, not a link into the repo"
fi
eq "holding a link per owned skill" "$REPO/root/.agents/skills/review-test" \
  "$(readlink "$RH/.claude/skills/review-test")"
# ~/.npmrc carries npm's 7-day cooldown and ignore-scripts, and a machine
# without it installs with neither, silently. It was linked only inline by the
# platform scripts, so relink never restored a missing one.
eq "the npm cooldown config is linked" "$REPO/.npmrc" "$(readlink "$RH/.npmrc")"

# --- relink, over the real link_dotfiles ---------------------------------------
# launchctl is stubbed to record any call: relink links LaunchAgents but never
# loads them, which is a decision about the machine that bin/launchd-load makes
# on request.
mkdir -p "$DIR/lstub"
printf '#!/bin/sh\necho "$*" >>"%s/launchctl.log"\n' "$DIR" >"$DIR/lstub/launchctl"
chmod +x "$DIR/lstub/launchctl"
relink_run() { # <stdin text or -> ; uses $RH as HOME
  if [ "$1" = - ]; then
    HOME="$RH" BACKUP_DIR="$RH/backup" DOTFILES_DIR="$REPO" PATH="$DIR/lstub:$BASE_PATH" \
      "$REPO/bin/relink" </dev/null >"$DIR/out" 2>"$DIR/err"
  else
    printf '%s\n' "$1" | HOME="$RH" BACKUP_DIR="$RH/backup" DOTFILES_DIR="$REPO" \
      PATH="$DIR/lstub:$BASE_PATH" "$REPO/bin/relink" >"$DIR/out" 2>"$DIR/err"
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
eq "answering y exits 0" "0" "$?"
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
eq "and no run touched launchctl" "no" "$([ -e "$DIR/launchctl.log" ] && echo yes || echo no)"

# On that synced home, one link moved into an old checkout that still exists.
# relink decides "up to date" from LINK_DRIFT alone, so the drift line is not
# enough: a flag set only for missing links would print it and then say up to
# date, fixing nothing.
mkdir -p "$DIR/old-checkout"
printf 'old\n' >"$DIR/old-checkout/.tmux.conf"
ln -sfn "$DIR/old-checkout/.tmux.conf" "$RH/.tmux.conf"
relink_run -
has "a live link into an old checkout is listed as drift" "$(cat "$DIR/out")" \
  "drift:   $RH/.tmux.conf does not point to $REPO/.tmux.conf"
lacks "and relink does not call the home up to date" "$(cat "$DIR/out")" "up to date"
relink_run y
eq "and answering y re-points it" "$REPO/.tmux.conf" "$(readlink "$RH/.tmux.conf")"

# An apply that left links undone must not report success. update-all runs
# relink last, so "done." and exit 0 here read as a synced machine.
#
# The failures are in the MIDDLE and the last link succeeds. That is the case
# the fix is about: link_dotfiles's own status is the last link's, so with
# every link failing, a relink that trusted that status would also pass here.
# Both obstacles are regular files where a directory belongs, which root cannot
# get past either, unlike a chmod:
#   - ~/.config is a file, so the links under it are never created (missing);
#   - ~/backup is a file, so the real ~/.tigrc cannot be moved aside and its
#     link fails on the file in the way (still wrong, and still the user's).
rm -rf "$RH"
mkdir -p "$RH"
printf 'not a dir\n' >"$RH/.config"
printf 'not a dir\n' >"$RH/backup"
printf 'mine\n' >"$RH/.tigrc"
relink_run y
status=$?
eq "a failed apply exits 1" "1" "$status"
lacks "a failed apply does not say done." "$(cat "$DIR/out")" "done."
has "a failed apply lists a link still missing" "$(cat "$DIR/err")" "still missing: $RH/.config/nvim"
has "a failed apply lists a link still wrong" "$(cat "$DIR/err")" \
  "still drift:   $RH/.tigrc does not point to $REPO/.tigrc"
eq "a failed apply leaves the file in the way intact" "mine" "$(cat "$RH/.tigrc")"
eq "a failed apply still runs to the end: the last link is created" \
  "$REPO/root/.agents/skills/retrospective/session-review" "$(readlink "$RH/.local/bin/session-review")"
eq "a failed apply still creates the links it can" "$REPO/.tmux.conf" "$(readlink "$RH/.tmux.conf")"

rm -rf "$RH"
mkdir -p "$RH"
if HOME="$RH" DOTFILES_DIR="$DIR/no-such-repo" "$REPO/bin/relink" </dev/null >"$DIR/out" 2>"$DIR/err"; then
  fail "a missing dotfiles dir exits non-zero"
else
  ok "a missing dotfiles dir exits non-zero"
fi
has "and names the directory it looked for" "$(cat "$DIR/err")" "dotfiles dir not found: $DIR/no-such-repo"
eq "and creates nothing" "$RH/" "$(snapshot "$RH")"

# --- ensure_ssh_base_include ---------------------------------------------------
# ~/.ssh/config is machine-local; the shared Host * defaults are linked in as
# config_base and pulled in by one Include. Where that line sits decides two
# things, and both were wrong once:
#   - scope: an Include after a Host block is conditional on that block, so a
#     bare Include appended after the last host applied the defaults to that one
#     host only (the macOS form: only mbp2022 got them);
#   - precedence: ssh takes the first value it reads, so an Include at the top
#     let the defaults beat every host's own setting (the WSL form).
# The fix is "Host *" then the Include, last in the file. The ssh -G cases are
# the contract; the text cases pin the migration of each broken form.
#
# The function rewrites a file the user owns, with no backup, so every case
# compares the whole result, not just the lines it adds: what it must keep
# matters as much as what it moves.
SC="$DIR/ssh"
ssh_case() { # <initial config, or - for none>
  # Its own $HOME and $BACKUP_DIR (`unit` exports them), not the last section's.
  fresh
  rm -rf "$SC"
  mkdir -p "$SC"
  printf 'Host *\n  ServerAliveInterval 15\n' >"$SC/base"
  # ssh refuses an Include target others can write, so under umask 002 an
  # unchmodded base would fail every ssh -G case below for that reason alone.
  chmod 644 "$SC/base"
  # What a relative Include reads: ssh resolves it under $HOME/.ssh, so with
  # HOME="$H" a default-target case is checked by ssh -G as well. 17, not the
  # real config_base's 15, so a run that forgot to pass HOME cannot pass by
  # reading the developer's own file.
  mkdir -p "$H/.ssh"
  printf 'Host *\n  ServerAliveInterval 17\n' >"$H/.ssh/config_base"
  chmod 644 "$H/.ssh/config_base"
  [ "$1" = "-" ] || printf '%s' "$1" >"$SC/config"
}
# With an absolute target, so a case reads no file under $HOME at all.
ensure() {
  unit ensure_ssh_base_include "$SC/config" "$SC/base"
  ST=$?
}
# As macos.sh and wsl.sh call it: no target, so the default config_base -- the
# literal the old scripts left on every machine -- is what must be matched.
ensure_default() {
  unit ensure_ssh_base_include "$SC/config"
  ST=$?
}
# The status and stderr of the last call: a caller runs under set -e, so a
# non-zero return would stop setup there with the file already written.
clean_run() { # <label>
  eq "$1: exits 0" "0" "$ST"
  eq "$1: says nothing" "" "$(cat "$DIR/err")"
}
# What ssh resolves for <host>, without connecting. ssh's own error is shown on
# failure rather than discarded: an empty value says nothing about why.
resolved() { # <host> <option>
  local v
  v=$(ssh -G -F "$SC/config" "$1" 2>"$DIR/ssh-err" | awk -v k="$2" '$1 == k { print $2 }')
  if [ -n "$v" ]; then printf '%s' "$v"; else printf 'ssh -G failed: %s' "$(head -n 1 "$DIR/ssh-err")"; fi
}
flat() { paste -sd '|' - <"$SC/config"; }

if ! command -v ssh >/dev/null 2>&1; then
  # Not a skip: without ssh -G the cases below cannot see what they pin.
  fail "ssh is installed for the ssh config cases"
fi

ssh_case "Host github.com
  User git

Host mbp2022
  ServerAliveInterval 30

Include $SC/base
"
eq "control: in the old macOS form the defaults miss an unrelated host" "0" "$(resolved example.com serveraliveinterval)"
ensure
clean_run "macOS form"
eq "macOS form: the defaults now reach an unrelated host" "15" "$(resolved example.com serveraliveinterval)"
eq "macOS form: and github.com" "15" "$(resolved github.com serveraliveinterval)"
eq "macOS form: a host's own value still wins" "30" "$(resolved mbp2022 serveraliveinterval)"
eq "macOS form: every host is kept and the Include moves inside Host *" \
  "Host github.com|  User git||Host mbp2022|  ServerAliveInterval 30||Host *|Include $SC/base" "$(flat)"

ssh_case "Include $SC/base

Host mbp2022
  ServerAliveInterval 30
"
eq "control: in the old WSL form the defaults beat a host's own value" "15" "$(resolved mbp2022 serveraliveinterval)"
ensure
clean_run "WSL form"
eq "WSL form: a host's own value now wins" "30" "$(resolved mbp2022 serveraliveinterval)"
eq "WSL form: the defaults still reach an unrelated host" "15" "$(resolved example.com serveraliveinterval)"
eq "WSL form: the Include is moved to the end, not copied" \
  "Host mbp2022|  ServerAliveInterval 30||Host *|Include $SC/base" "$(flat)"

ssh_case "Host mbp2022
  ServerAliveInterval 30
"
ensure
clean_run "no Include yet"
eq "no Include yet: the hosts are kept and the Include is appended" \
  "Host mbp2022|  ServerAliveInterval 30||Host *|Include $SC/base" "$(flat)"
eq "no Include yet: the defaults reach an unrelated host" "15" "$(resolved example.com serveraliveinterval)"

ssh_case -
ensure
clean_run "no config at all"
eq "no config at all: one is created holding just the Include" "Host *|Include $SC/base" "$(flat)"
eq "no config at all: it is private to the user (0600 exactly)" "$SC/config" "$(find "$SC/config" -perm 600)"

# The user's own Host * block is the user's. Mid-file it must survive; and when
# it is the very block the Include sat in, with settings after the Include, its
# header must stay, or those settings fold into the host block above.
ssh_case "Host *
  Compression yes

Host mbp2022
  ServerAliveInterval 30

Include $SC/base
"
ensure
eq "a user's own Host * block mid-file is kept" \
  "Host *|  Compression yes||Host mbp2022|  ServerAliveInterval 30||Host *|Include $SC/base" "$(flat)"
eq "and still reaches an unrelated host" "yes" "$(resolved example.com compression)"

ssh_case "Host mbp2022
  ServerAliveInterval 30

Host *
Include $SC/base
  Compression yes
"
eq "control: a setting after the Include in Host * reaches an unrelated host" "yes" "$(resolved example.com compression)"
ensure
clean_run "settings after the Include"
eq "settings after the Include keep their Host * scope" "yes" "$(resolved example.com compression)"
eq "settings after the Include: the user's Host * stays, only the Include moves" \
  "Host mbp2022|  ServerAliveInterval 30||Host *|  Compression yes||Host *|Include $SC/base" "$(flat)"

# The literal forms the old scripts left behind, repaired through the default
# target exactly as the callers invoke it.
ssh_case "Host mbp2022
  ServerAliveInterval 30

Include config_base
"
ensure_default
clean_run "old macos.sh output"
eq "old macos.sh output: repaired in place" \
  "Host mbp2022|  ServerAliveInterval 30||Host *|Include config_base" "$(flat)"

# Old macos.sh appended to a config with no final newline, leaving the Include
# right under a host's last setting, which must not go with it.
ssh_case "Host mbp2022
  ServerAliveInterval 30
Include config_base
"
ensure_default
eq "an Include right under a setting: the setting is kept" \
  "Host mbp2022|  ServerAliveInterval 30||Host *|Include config_base" "$(flat)"

# On a machine with no config, old wsl.sh wrote the Include then a blank line,
# and old macos.sh a blank line then the Include.
for old in "Include config_base

" "
Include config_base
"; do
  ssh_case "$old"
  ensure_default
  eq "an old config holding only the Include becomes just the two lines" "Host *|Include config_base" "$(flat)"
done

ssh_case "Include ~/.orbstack/ssh/config

Host mbp2022
  ServerAliveInterval 30

Include config_base
"
ensure_default
eq "an unrelated Include at the top stays at the top" \
  "Include ~/.orbstack/ssh/config||Host mbp2022|  ServerAliveInterval 30||Host *|Include config_base" "$(flat)"

# The repo's .sshconfig template began with `Include ~/.ssh/config_base` -- the
# same file to ssh, which reads a relative Include in a user config from
# ~/.ssh -- and macos.sh moved it into place, then appended the bare form after
# the last host. A Mac set up from it holds both; both must go, or the one at
# the top keeps the defaults ahead of every host's own value.
ssh_case "Include ~/.ssh/config_base

Host github.com
  User git

Host mbp2022
  ServerAliveInterval 30

Include config_base
"
eq "control: from the old template the defaults beat a host's own value" \
  "17" "$(HOME="$H" resolved mbp2022 serveraliveinterval)"
ensure_default
clean_run "a config from the old template"
eq "a config from the old template: the ~/.ssh form at the top goes too" \
  "Host github.com|  User git||Host mbp2022|  ServerAliveInterval 30||Host *|Include config_base" "$(flat)"
eq "a config from the old template: a host's own value now wins" \
  "30" "$(HOME="$H" resolved mbp2022 serveraliveinterval)"
eq "a config from the old template: the defaults still reach an unrelated host" \
  "17" "$(HOME="$H" resolved example.com serveraliveinterval)"

# Only that exact spelling of the same file: another file under ~/.ssh is
# someone else's Include, whether its name only starts like ours or only ends
# like it.
ssh_case "Include ~/.ssh/config_base.local
Include ~/.ssh/old/config_base

Host mbp2022
  ServerAliveInterval 30
"
ensure_default
eq "Includes of other files under ~/.ssh stay" \
  "Include ~/.ssh/config_base.local|Include ~/.ssh/old/config_base||Host mbp2022|  ServerAliveInterval 30||Host *|Include config_base" "$(flat)"

# The template itself must not reintroduce the line: setup places the Include,
# and one written at the top of the template is the precedence bug again. A
# template that cannot be read is a failure, not a pass: grep's "no match" and
# "no file" must not collapse into one answer.
if [ ! -f "$REPO/.sshconfig" ]; then
  fail "the repo's .sshconfig template exists to be checked" "$REPO/.sshconfig"
elif grep -qiE '^[[:space:]]*include[[:space:]=].*config_base' "$REPO/.sshconfig"; then
  fail "the repo's .sshconfig template carries no Include of config_base" "$(grep -niE 'include' "$REPO/.sshconfig")"
else
  ok "the repo's .sshconfig template carries no Include of config_base"
fi

# A run on every setup must converge: the second leaves the file untouched --
# not rewritten with the same bytes. A hard link taken in between still names
# the same file afterwards only if nothing was moved over it.
ssh_case "Host mbp2022
  ServerAliveInterval 30

Include $SC/base
"
ensure
cp "$SC/config" "$SC/after-first"
ln "$SC/config" "$SC/same-file"
ensure
clean_run "a second run"
if cmp -s "$SC/after-first" "$SC/config"; then ok "a second run leaves the bytes the same"; else fail "a second run leaves the bytes the same"; fi
if [ "$SC/config" -ef "$SC/same-file" ]; then ok "a second run does not rewrite the file"; else fail "a second run does not rewrite the file"; fi

# An unreadable config is the user's file in a state we cannot see. It must be
# left exactly as it is and the call must say so, even with no errexit around
# it. Needs a non-root runner: root reads a 000 file anyway.
ssh_case "Host mbp2022
  ServerAliveInterval 30
"
chmod 000 "$SC/config"
ensure
chmod 600 "$SC/config"
if [ "$(id -u)" -eq 0 ]; then
  fail "an unreadable config is left alone" "running as root, which reads it anyway"
else
  if [ "$ST" -ne 0 ]; then ok "an unreadable config returns non-zero"; else fail "an unreadable config returns non-zero"; fi
  eq "an unreadable config is left as it was" "Host mbp2022|  ServerAliveInterval 30" "$(flat)"
  has "an unreadable config is named in a warning" "$(cat "$DIR/err")" "could not read $SC/config"
  eq "an unreadable config leaves no temp file" "" "$(find "$SC" -name 'config.tmp')"
fi

if [ "$fails" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$fails failure(s)"
  exit 1
fi
