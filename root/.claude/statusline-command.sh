#!/bin/bash
# Claude Code statusLine — p10k-flavored layout.
# Renders: <dir>  <branch>[*]  ·  <model>
# Git is the only external command consulted (no language/tool version
# shell-outs) to keep the status line fast on every prompt.

input=$(cat)

dir=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')

# Abbreviate $HOME to ~, mirroring p10k's directory segment.
# The replacement tilde is escaped: under bash a leading unescaped ~ in a
# ${var/pat/repl} replacement is special-cased and the substitution no-ops.
display_dir="${dir/#$HOME/\~}"

segment="$display_dir"

# --no-optional-locks avoids contending with concurrent git operations
# (e.g. another shell mid-commit) since this runs on every prompt render.
if git -C "$dir" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    # Detached HEAD: fall back to short commit hash.
    branch=$(git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi
  if [ -n "$branch" ]; then
    if [ -n "$(git -C "$dir" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      branch="${branch}*"
    fi
    segment="${segment}  ${branch}"
  fi
fi

printf '%s  ·  %s' "$segment" "$model"
