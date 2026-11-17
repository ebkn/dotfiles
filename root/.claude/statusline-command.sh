#!/bin/bash
# Claude Code statusLine — p10k-flavored, two rows.
#   Row 1: <launch-dir>[ (working in ./<working-dir-relative-to-launch>)]
#   Row 2: <model>[ ・ <effort>][ ・ <pct>% Used][ ・ <s>%(session)・<w>%(week)]
#          [ ・ <email>][ (<config-dir>)]
# Row 1 names the directory Claude was launched from and, only when the live
# working directory has moved elsewhere, appends where it is now. Row 2 lists
# session info: model, effort, consumed context, and Claude.ai subscription
# usage limits (5-hour session window and 7-day weekly window), then the
# logged-in account and, when CLAUDE_CONFIG_DIR is not ~/.claude, that dir.
# Parsing stdin is a single jq pass with no per-field subprocess, keeping the
# status line fast on every prompt.

input=$(cat)

# Pull every field in one jq pass, one value per line. Reading each line whole
# with `IFS= read -r` preserves empty values (e.g. effort absent on models that
# don't support it) — a plain space/tab split would collapse them and misalign
# the rest. Indexing a missing object yields null in jq, so the // "" / null
# guards degrade gracefully when a field isn't present.
{
  IFS= read -r launch_dir
  IFS= read -r work_dir
  IFS= read -r model
  IFS= read -r effort
  IFS= read -r used
  IFS= read -r session_pct
  IFS= read -r week_pct
} < <(echo "$input" | jq -r '
  (.workspace.project_dir // ""),
  (.workspace.current_dir // ""),
  .model.display_name,
  (.effort.level // ""),
  (.context_window.used_percentage | if . == null then "" else (round | tostring) end),
  (.rate_limits.five_hour.used_percentage | if . == null then "" else (round | tostring) end),
  (.rate_limits.seven_day.used_percentage | if . == null then "" else (round | tostring) end)
')

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
# " ・ ". Each part is appended only when present, and the separator rides with
# the part, so an absent field leaves no dangling separator. The rate_limits
# object is absent for non-subscribers and until the first API response, so both
# session/week percentages degrade to empty and drop out silently. Within the
# limits group the two windows are joined tight (session・week); ${limits:+…}
# emits the leading separator only when the session part precedes the week part.
# NOTE: the ・ after ${limits} MUST keep its braces. The shebang is /bin/bash,
# which on macOS is bash 3.2, where an unbraced "$var" immediately followed by a
# multibyte literal ("$limits・") corrupts the expansion — eating $var and the
# char's first byte. The spaced " ・ " separators elsewhere are safe because the
# space breaks the adjacency; this tight join is only safe in ${limits}・ form.
row2="$model"
[ -n "$effort" ] && row2="$row2 ・ $effort"
[ -n "$used" ] && row2="$row2 ・ ${used}% Used"
limits=""
[ -n "$session_pct" ] && limits="${session_pct}%(session)"
[ -n "$week_pct" ] && limits="${limits:+${limits}・}${week_pct}%(week)"
[ -n "$limits" ] && row2="$row2 ・ $limits"

# Account: the stdin JSON carries no account field, so the email comes from the
# global config Claude Code itself reads -- $CLAUDE_CONFIG_DIR/.claude.json when
# the variable is set, ~/.claude.json (not ~/.claude/.claude.json) when it is
# not. The statusline command inherits Claude Code's environment, so this is
# the session's own config dir. A dir other than ~/.claude is shown beside the
# email, since several dirs may be logged in to the same account; with no
# logged-in account (API key, missing file) the dir alone remains. A second jq
# pass, but only over a file of a few hundred KB.
config_dir=${CLAUDE_CONFIG_DIR%/}
if [ -n "$config_dir" ]; then
  config_file="$config_dir/.claude.json"
else
  config_file="$HOME/.claude.json"
fi
account=""
[ -r "$config_file" ] && account=$(jq -r '.oauthAccount.emailAddress // empty' "$config_file" 2>/dev/null)
if [ -n "$config_dir" ] && [ "$config_dir" != "$HOME/.claude" ]; then
  account="${account:+$account }($(abbrev_path "$config_dir"))"
fi
[ -n "$account" ] && row2="$row2 ・ $account"

printf '%s\n%s' "$row1" "$row2"
