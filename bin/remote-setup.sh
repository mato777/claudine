#!/bin/sh
# One-time setup of this Neovim config on a Linux server (x86_64 or arm64).
# Run it on the server after cloning the config to ~/.config/nvim:
#   sh ~/.config/nvim/bin/remote-setup.sh
#
# Installs into ~/.local without sudo: Neovim 0.12.4, ripgrep 15.2.0, Claude Code.
# tmux comes from the system package manager (asks for sudo) if it's missing.
set -eu

NVIM_VERSION=v0.12.4
RG_VERSION=15.2.0
PREFIX="$HOME/.local"
BIN="$PREFIX/bin"

say() { printf '\n==> %s\n' "$*"; }

[ "$(uname -s)" = "Linux" ] || { echo "This script is for Linux servers."; exit 1; }
for tool in curl tar git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing $tool: install it first."; exit 1; }
done

case "$(uname -m)" in
  x86_64 | amd64) NVIM_ARCH=x86_64; RG_TRIPLE=x86_64-unknown-linux-musl ;;
  aarch64 | arm64) NVIM_ARCH=arm64; RG_TRIPLE=aarch64-unknown-linux-musl ;;
  *) echo "Unsupported CPU: $(uname -m)"; exit 1 ;;
esac

mkdir -p "$BIN" "$PREFIX/opt"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if "$BIN/nvim" --version 2>/dev/null | head -n 1 | grep -q "NVIM $NVIM_VERSION"; then
  say "Neovim $NVIM_VERSION already installed"
else
  say "Installing Neovim $NVIM_VERSION"
  curl -fsSL "https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-$NVIM_ARCH.tar.gz" -o "$tmp/nvim.tar.gz"
  rm -rf "$PREFIX/opt/nvim"
  mkdir -p "$PREFIX/opt/nvim"
  tar -xzf "$tmp/nvim.tar.gz" -C "$PREFIX/opt/nvim" --strip-components=1
  ln -sf "$PREFIX/opt/nvim/bin/nvim" "$BIN/nvim"
fi

if command -v rg >/dev/null 2>&1; then
  say "ripgrep already installed ($(command -v rg))"
else
  say "Installing ripgrep $RG_VERSION"
  curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/$RG_VERSION/ripgrep-$RG_VERSION-$RG_TRIPLE.tar.gz" -o "$tmp/rg.tar.gz"
  tar -xzf "$tmp/rg.tar.gz" -C "$tmp"
  cp "$tmp/ripgrep-$RG_VERSION-$RG_TRIPLE/rg" "$BIN/rg"
fi

if command -v tmux >/dev/null 2>&1; then
  say "tmux already installed"
else
  say "Installing tmux (needs sudo)"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq tmux
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y -q tmux
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y -q tmux
  else
    echo "No apt/dnf/yum found: install tmux yourself."
  fi
fi

if command -v claude >/dev/null 2>&1 || [ -x "$BIN/claude" ]; then
  say "Claude Code already installed"
else
  say "Installing Claude Code (official installer)"
  curl -fsSL https://claude.ai/install.sh | bash
fi

# tmux: load claudine's tmux settings (clipboard, bell, escape-time) from the repo,
# so they update with `git pull`.
TMUX_LINE="source-file ~/.config/nvim/tmux.conf"
if [ ! -e "$HOME/.tmux.conf" ]; then
  say "Writing ~/.tmux.conf"
  printf '%s\n' "$TMUX_LINE" "set -g mouse on" > "$HOME/.tmux.conf"
elif grep -qF "$TMUX_LINE" "$HOME/.tmux.conf"; then
  say "~/.tmux.conf already loads claudine's tmux settings"
else
  say "~/.tmux.conf exists, left as is. To get copy/bell through to your Mac, add this line:"
  echo "  $TMUX_LINE"
fi

say "Installing Neovim plugins"
"$BIN/nvim" --headless -c 'qa' >/dev/null 2>&1 || true

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) say "Add ~/.local/bin to your PATH, e.g.:"; echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc" ;;
esac

say "Done. Next:"
echo "  1. claude            # log in once"
echo "  2. tmux new -A -s work"
echo "  3. cd <project> && nvim"
