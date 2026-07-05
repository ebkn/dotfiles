#!/bin/bash
# Claude Code statusLine — p10k-flavored, two rows.
#   Row 1: <launch-dir>[ (working at <working-dir>)]
#   Row 2: <branch>[*]                <model>[ (<effort>)][  <pct>% Used]
# Row 1 names the directory Claude was launched from and, only when the live
# working directory has moved elsewhere, appends where it is now. Row 2 is
# justified like p10k's split prompts: git branch flush left, session info
# flush right. Git is the only external command consulted (no language/tool
# version shell-outs) to keep the status line fast on every prompt.

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
} < <(echo "$input" | jq -r '
  (.workspace.project_dir // ""),
  (.workspace.current_dir // ""),
  .model.display_name,
  (.effort.level // ""),
  (.context_window.used_percentage | if . == null then "" else (round | tostring) end)
')

# Abbreviate $HOME to ~, mirroring p10k's directory segment. The replacement
# tilde is escaped: under bash a leading unescaped ~ in a ${var/pat/repl}
# replacement is special-cased and the substitution no-ops.
launch_disp="${launch_dir/#$HOME/\~}"
work_disp="${work_dir/#$HOME/\~}"

# Row 1: just the directory when the working dir matches the launch dir (the
# common case); otherwise show the launch dir and where work has moved to,
# relative to it. The quoted prefix in ${work_dir#"$launch_dir"/} matches
# literally so glob chars in the path aren't treated as patterns; when the
# working dir isn't under the launch dir the prefix doesn't strip and we fall
# back to the ~-abbreviated absolute path instead of a "../.."-laden relative.
if [ -z "$launch_dir" ] || [ "$launch_dir" = "$work_dir" ]; then
  row1="$work_disp"
else
  rel="${work_dir#"$launch_dir"/}"
  [ "$rel" = "$work_dir" ] && rel="$work_disp"
  row1="$launch_disp (working at $rel)"
fi

# Branch (row 2, left) derived from the live working directory.
# --no-optional-locks avoids contending with concurrent git operations
# (e.g. another shell mid-commit) since this runs on every prompt render.
branch=""
if git -C "$work_dir" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$work_dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    # Detached HEAD: fall back to short commit hash.
    branch=$(git -C "$work_dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi
  if [ -n "$branch" ] && [ -n "$(git -C "$work_dir" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    branch="${branch}*"
  fi
fi

# Row 2, right group: model, then effort (parenthesized so it doesn't read as
# part of the model name) and consumed-context percentage when each is present.
right="$model"
[ -n "$effort" ] && right="$right ($effort)"
[ -n "$used" ] && right="$right  ${used}% Used"

# Justify row 2: branch flush left, session info flush right. Claude Code sets
# COLUMNS to the terminal width (v2.1.153+); pad the gap with spaces.
#
# Reserve the last column: filling exactly $COLUMNS lands a glyph in the final
# cell, which the terminal treats as a pending wrap and Claude Code then
# truncates with an ellipsis. Stopping one column short keeps the right group
# fully visible while still reading as flush-right.
#
# Width uses ${#var} (character count); both groups are ASCII in the common
# case so this equals the on-screen column count. A branch containing
# multi-column (e.g. CJK) glyphs shifts the right group by a few columns, since
# such a character occupies two terminal columns but counts as one here — a
# pure-bash wcwidth is not worth the per-render cost.
reserve=1
gap=$(( ${COLUMNS:-0} - ${#branch} - ${#right} - reserve ))
if [ "$gap" -ge 2 ]; then
  row2="${branch}$(printf '%*s' "$gap" '')${right}"
elif [ -n "$branch" ]; then
  # Too narrow to justify: fall back to a single "·"-joined row.
  row2="$branch  ·  $right"
else
  row2="$right"
fi

printf '%s\n%s' "$row1" "$row2"
