# GPG signing — tell gpg-agent which terminal to draw pinentry on.
#
# gpg-agent is started by systemd socket activation (`gpg-agent --supervised`),
# so it inherits no controlling terminal. gpg only passes the terminal to the
# agent via GPG_TTY, and without it pinentry-curses fails with
# "signing failed: Inappropriate ioctl for device" — even from a real terminal.
# Every `git commit` then fails, since commit.gpgsign is on.
#
# Use zsh's $TTY rather than $(tty): same value, no fork on every shell start.
if [[ -o interactive && -n "${TTY:-}" ]]; then
  export GPG_TTY="$TTY"
fi
