#!/bin/bash
# Claude Code statusLine — p10k-flavored, two rows.
#   Row 1: <launch-dir>[ (working in ./<working-dir-relative-to-launch>)]
#   Row 2: <model>[ ・ <effort>][ ・ <pct>% Used] ・ <s>%(session)・<w>%(week)
#          [ ・ <config-dir-name>]
# Row 1 names the directory Claude was launched from and, only when the live
# working directory has moved elsewhere, appends where it is now. Row 2 lists
# session info: model, effort, consumed context, and Claude.ai subscription
# usage limits (5-hour session window and 7-day weekly window), then, when
# CLAUDE_CONFIG_DIR is not ~/.claude, that dir's name (e.g. .claude-private).
# The usage limits are always shown — from a per-login cache when the session
# has none yet — and turn red with a "credits" label once a window is full,
# i.e. once usage credits pay for the rest.
# Parsing stdin is a single jq pass with no per-field subprocess, keeping the
# status line fast on every prompt.

input=$(cat)

# Config dir: each CLAUDE_CONFIG_DIR is its own login. The statusline command
# inherits Claude Code's environment, so this is the session's own dir. The
# trailing / is stripped first, or both the comparison below and the name
# would come out wrong.
config_dir=${CLAUDE_CONFIG_DIR%/}

# Usage-limit cache. Claude Code sends rate_limits only after the session's
# first API response, and drops a window once its resets_at passes, so a fresh
# or idle session would show no usage at all. The limits belong to the
# account, not the session, so the last values any session of this login saw
# stand in until live ones arrive. One file per config dir = one per login.
# ~/.claude is a real directory (this repo links entries inside it, such as
# settings.json, hooks/ and skills, never the dir itself), so a file at its
# top level never lands in the checkout. Do not move it under hooks/.
cache_file="${config_dir:-$HOME/.claude}/statusline-rate-limits.json"
cached=$(cat "$cache_file" 2>/dev/null)

# Pull every field in one jq pass, one value per line. Reading each line whole
# with `IFS= read -r` preserves empty values (e.g. effort absent on models that
# don't support it) — a plain space/tab split would collapse them and misalign
# the rest. Indexing a missing object yields null in jq, so the // "" / null
# guards degrade gracefully when a field isn't present.
#
# Rate limits: live windows are merged over the cached ones, so a window the
# live object lacks falls back to the cache. A cached window whose resets_at
# has passed reads 0 — it has reset since, and nothing newer was seen. A
# corrupt cache is ignored rather than breaking the status line.
# over_limit is "1" when a window has reached 100%. No field tells the status
# line that extra usage (usage credits) is being drawn — Claude Code tracks it
# internally as "limit rejected, overage allowed" but exposes it only behind a
# gateway — so a full window is the signal: past it, a session that keeps
# working is running on credits. It tests the raw value, so 99.6 (shown as
# 100%) does not trip it.
{
  IFS= read -r launch_dir
  IFS= read -r work_dir
  IFS= read -r model
  IFS= read -r effort
  IFS= read -r used
  IFS= read -r session_pct
  IFS= read -r week_pct
  IFS= read -r over_limit
  IFS= read -r new_cache
} < <(echo "$input" | jq -r --arg cache "$cached" '
  def fmt: if . == null then "" else (round | tostring) end;
  def win($w):
    .[$w]
    | if . == null or .used_percentage == null then null
      elif .resets_at != null and .resets_at <= now then 0
      else .used_percentage end;
  ($cache | try fromjson catch null | if type == "object" then . else {} end) as $c
  | .rate_limits as $live
  | (if $live then $c + $live else $c end) as $rl
  | ($rl | win("five_hour")) as $s
  | ($rl | win("seven_day")) as $w
  | (.workspace.project_dir // ""),
    (.workspace.current_dir // ""),
    .model.display_name,
    (.effort.level // ""),
    (.context_window.used_percentage | fmt),
    ($s | fmt),
    ($w | fmt),
    (if [$s, $w] | any(. != null and . >= 100) then "1" else "" end),
    (if $live and $rl != $c then $rl | tojson else "" end)
')

# Rewritten only when the merged limits changed, so the common render does no
# write. The temp file + mv keeps a concurrent session from reading half a
# file; a dir that does not exist just leaves the cache unwritten.
if [ -n "$new_cache" ]; then
  if { printf '%s' "$new_cache" >"$cache_file.$$"; } 2>/dev/null; then
    mv -f "$cache_file.$$" "$cache_file" 2>/dev/null || rm -f "$cache_file.$$"
  fi
fi

# Abbreviate a path for display: ghq's github.com checkout root collapses to
# [ghq] (most repos live there, so it's the biggest win); otherwise $HOME
# collapses to ~, mirroring p10k. ghq is checked first as the more specific
# prefix. The ~ is printed by printf rather than substituted with
# ${p/#$HOME/\~}: bash 3.2 (the shebang's /bin/bash) keeps that backslash and
# prints \~, while 5.x drops it, and an unescaped ~ there expands back to $HOME
# on 5.x. Prefix stripping behaves the same on both. The quoted prefixes in
# ${p#"$ghq"/} and ${p#"$HOME"/} match literally so glob chars aren't patterns.
abbrev_path() {
  local p=$1 ghq="$HOME/ghq/github.com"
  if [ "$p" = "$ghq" ]; then
    printf '[ghq]'
  elif [ "${p#"$ghq"/}" != "$p" ]; then
    printf '[ghq]/%s' "${p#"$ghq"/}"
  elif [ "$p" = "$HOME" ]; then
    printf '~'
  elif [ "${p#"$HOME"/}" != "$p" ]; then
    # '~/%s' would trip shellcheck's SC2088; the / rides in the argument.
    printf '~%s' "/${p#"$HOME"/}"
  else
    printf '%s' "$p"
  fi
}
launch_disp=$(abbrev_path "$launch_dir")
work_disp=$(abbrev_path "$work_dir")

# Row 1: just the directory when the working dir matches the launch dir (the
# common case); otherwise show the launch dir and where work has moved to,
# relative to it with a leading ./ so it reads as relative. The quoted prefix in
# ${work_dir#"$launch_dir"/} matches literally so glob chars in the path aren't
# treated as patterns; when the working dir isn't under the launch dir the
# prefix doesn't strip and we fall back to the ~-abbreviated absolute path
# (no ./, since it isn't relative) instead of a "../.."-laden relative.
if [ -z "$launch_dir" ] || [ "$launch_dir" = "$work_dir" ]; then
  row1="$work_disp"
else
  rel="${work_dir#"$launch_dir"/}"
  if [ "$rel" = "$work_dir" ]; then
    rel="$work_disp"
  else
    rel="./$rel"
  fi
  row1="$launch_disp (working in $rel)"
fi

# Row 2: model, effort, consumed-context percentage, and usage limits joined by
# " ・ ". Model, effort and context are appended only when present, and the
# separator rides with the part, so an absent field leaves no dangling
# separator. The usage limits are always shown, so their absence is visible
# rather than mistaken for a hidden segment: a window never seen by this login
# reads --. The two windows are joined tight (session・week).
# NOTE: keep every variable before a multibyte literal braced. The shebang is
# /bin/bash, which on macOS is bash 3.2, where an unbraced "$var" immediately
# followed by a multibyte literal ("$var・") corrupts the expansion — eating
# $var and the char's first byte. The spaced " ・ " separators are safe because
# the space breaks the adjacency.
row2="$model"
[ -n "$effort" ] && row2="$row2 ・ $effort"
[ -n "$used" ] && row2="$row2 ・ ${used}% Used"
limits="${session_pct:---}%(session)・${week_pct:---}%(week)"
# On credits: white bold on red, so it is seen without reading the numbers.
if [ -n "$over_limit" ]; then
  limits=$'\033[1;97;41m'" ${limits} credits "$'\033[0m'
fi
row2="$row2 ・ $limits"

# Config dir name: says which account the session runs as. Only the name is
# shown (the dirs sit side by side in $HOME, so it is what tells them apart),
# and nothing for the default ~/.claude.
if [ -n "$config_dir" ] && [ "$config_dir" != "$HOME/.claude" ]; then
  row2="$row2 ・ ${config_dir##*/}"
fi

printf '%s\n%s' "$row1" "$row2"
