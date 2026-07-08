# link_dotfiles — create the platform-common $HOME symlinks that are safe to
# re-run at any time (order-independent, no side effects beyond the link).
#
# Sourced by:
#   - bin/init/macos.sh : during initial setup
#   - bin/relink        : drift re-sync invoked from `update-all`, so links
#                         added to the repo after a machine was provisioned get
#                         created without re-running the full init script.
#
# Links that must run at a specific point (.zshrc/.zshenv before shell packages,
# .npmrc before npm) or that are wrapped in special logic (.ssh/config Include,
# sudo diff-highlight, CI-only gitconfig tweaks) stay inline in the init script
# and are intentionally NOT re-synced here.
#
# Requires: DOTFILES_DIR, HOME, and link_with_backup/backup_path (from common.sh).
# Honors LINK_CHECK=1 via link_with_backup (report drift instead of mutating).
link_dotfiles() {
  link_with_backup "${DOTFILES_DIR}/.gitignore_global" "${HOME}/.gitignore_global"
  link_with_backup "${DOTFILES_DIR}/.bash_profile" "${HOME}/.bash_profile"
  link_with_backup "${DOTFILES_DIR}/.bashrc" "${HOME}/.bashrc"
  link_with_backup "${DOTFILES_DIR}/.tmux.conf" "${HOME}/.tmux.conf"
  link_with_backup "${DOTFILES_DIR}/.vimrc" "${HOME}/.vimrc"
  # .minvimrc is kept in the repo for specific environments and is not linked by default.
  link_with_backup "${DOTFILES_DIR}/.xvimrc" "${HOME}/.xvimrc"
  link_with_backup "${DOTFILES_DIR}/.ideavimrc" "${HOME}/.ideavimrc"
  link_with_backup "${DOTFILES_DIR}/.textlintrc" "${HOME}/.textlintrc"
  link_with_backup "${DOTFILES_DIR}/.markdownlintrc" "${HOME}/.markdownlintrc"
  link_with_backup "${DOTFILES_DIR}/.clang-format" "${HOME}/.clang-format"
  link_with_backup "${DOTFILES_DIR}/vim/nvim" "${HOME}/.config/nvim"
  link_with_backup "${DOTFILES_DIR}/vim/coc/package.json" "${HOME}/.config/coc/extensions/package.json"
  link_with_backup "${DOTFILES_DIR}/cursor/keybindings.json" "${HOME}/Library/Application Support/Cursor/User/keybindings.json"
  link_with_backup "${DOTFILES_DIR}/cursor/settings.json" "${HOME}/Library/Application Support/Cursor/User/settings.json"
  link_with_backup "${DOTFILES_DIR}/root/CLAUDE.md" "${HOME}/CLAUDE.md"
  # Expose alternate instruction filenames used by local agent tools.
  link_with_backup "${HOME}/CLAUDE.md" "${HOME}/AGENTS.md"
  link_with_backup "${DOTFILES_DIR}/root/.github/copilot-instructions.md" "${HOME}/.github/copilot-instructions.md"
  link_with_backup "${DOTFILES_DIR}/root/.claude/settings.json" "${HOME}/.claude/settings.json"
  link_with_backup "${DOTFILES_DIR}/root/.claude/hooks" "${HOME}/.claude/hooks"
  link_with_backup "${DOTFILES_DIR}/root/.claude/statusline-command.sh" "${HOME}/.claude/statusline-command.sh"
  # Link the whole rules dir (not the file inside it): ~/.codex/rules is a
  # directory symlink into the repo, so linking the file through it would resolve
  # dest back onto src and clobber the repo file. Codex owns bundled skills under
  # ~/.codex/skills/.system but does not scaffold into rules/, so a dir symlink is
  # safe here (unlike skills, which are linked individually below).
  link_with_backup "${DOTFILES_DIR}/root/.codex/rules" "${HOME}/.codex/rules"
  # Agent skills: root/.agents/skills is the single source of truth for the skills
  # this repo OWNS. Link each skill INDIVIDUALLY into every consumer dir — never
  # the whole dir as one symlink. A directory symlink makes tools that auto-install
  # skills (e.g. Cloudflare's installer writing into ~/.agents or ~/.claude) create
  # real dirs straight into this repo through the link, polluting it with untracked
  # skills. With per-skill links the consumer dirs stay real directories: our
  # symlinks sit beside any tool-installed skills, which then land outside the repo.
  #   ~/.agents/skills : emerging cross-tool standard (newer Codex, Cursor, Gemini, Copilot)
  #   ~/.claude/skills : Claude Code
  #   ~/.codex/skills  : Codex (also scaffolds bundled skills under .system)
  # OpenCode reads both .agents and .claude, so it may list each skill twice.
  # Trade-off vs. the old dir symlink: a newly added skill needs a `relink` to
  # appear in the consumer dirs (update-all runs relink, so it self-heals).
  for skill_dir in "${DOTFILES_DIR}"/root/.agents/skills/*/; do
    skill_name="$(basename "${skill_dir}")"
    link_with_backup "${skill_dir%/}" "${HOME}/.agents/skills/${skill_name}"
    link_with_backup "${skill_dir%/}" "${HOME}/.claude/skills/${skill_name}"
    link_with_backup "${skill_dir%/}" "${HOME}/.codex/skills/${skill_name}"
  done
  link_with_backup "${DOTFILES_DIR}/root/opencode" "${HOME}/.config/opencode"

  # Supply-chain cooldown: refuse npm package versions younger than 3 days.
  # Keeps yarn/pnpm in lockstep with npm's min-release-age=3 (.npmrc). yarn Berry
  # reads ~/.yarnrc.yml; pnpm's global config path is platform-specific (macOS
  # keeps it under ~/Library/Preferences, Linux/WSL under ~/.config).
  link_with_backup "${DOTFILES_DIR}/root/.yarnrc.yml" "${HOME}/.yarnrc.yml"
  if [ "$(uname)" = "Darwin" ]; then
    link_with_backup "${DOTFILES_DIR}/root/pnpm-config.yaml" "${HOME}/Library/Preferences/pnpm/config.yaml"
  else
    link_with_backup "${DOTFILES_DIR}/root/pnpm-config.yaml" "${HOME}/.config/pnpm/config.yaml"
  fi

  # others
  link_with_backup "${DOTFILES_DIR}/.rgignore" "${HOME}/.rgignore"
  link_with_backup "${DOTFILES_DIR}/.sqliterc" "${HOME}/.sqliterc"
  link_with_backup "${DOTFILES_DIR}/.tigrc" "${HOME}/.tigrc"

  # scripts
  link_with_backup "${DOTFILES_DIR}/tmux-restore-tabs" "${HOME}/.local/bin/tmux-restore-tabs"
  link_with_backup "${DOTFILES_DIR}/tmux-pane-titles" "${HOME}/.local/bin/tmux-pane-titles"
  link_with_backup "${DOTFILES_DIR}/tmux-track-session" "${HOME}/.local/bin/tmux-track-session"
  link_with_backup "${DOTFILES_DIR}/bin/fzf-files" "${HOME}/.local/bin/fzf-files"
  link_with_backup "${DOTFILES_DIR}/bin/git-generated" "${HOME}/.local/bin/git-generated"
  link_with_backup "${DOTFILES_DIR}/bin/relink" "${HOME}/.local/bin/relink"
}
