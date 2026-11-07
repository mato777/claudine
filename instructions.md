# Install claudine on a Linux machine (agent instructions)

claudine is a Neovim config: a three-column workspace (file tree, Claude Code, sessions list).
Follow these steps in order on the target Linux machine. Each step says how to check it worked.
Stop and report to the user if a check fails; do not improvise around it.

## Rules

- **Do not overwrite an existing Neovim config.** If `~/.config/nvim` exists, move it aside (step 2), never delete it.
- **Do not log in to Claude for the user.** `claude` login is interactive and needs the user (step 5).
- **Do not run `nvim` without `--headless` for checks.** With a screen and no file arguments it opens the workspace and starts Claude with `--dangerously-skip-permissions`. Headless runs never start Claude.
- Install without sudo where possible. Only tmux may need sudo; ask the user before using it if you are not allowed to.

## Requirements

- Linux on x86_64 or arm64 (`uname -sm`).
- `curl`, `tar` and `git` on the PATH.
- Internet access to github.com and claude.ai.

## 1. Check the machine

```sh
uname -sm
for t in curl tar git; do command -v "$t" || echo "MISSING: $t"; done
```

Expected: `Linux x86_64` or `Linux aarch64`, and no `MISSING` lines. If a tool is missing, install it with the system package manager (ask the user if that needs sudo).

## 2. Back up an existing config

```sh
if [ -e ~/.config/nvim ]; then mv ~/.config/nvim ~/.config/nvim.backup.$(date +%Y%m%d%H%M%S); fi
ls -d ~/.config/nvim.backup.* 2>/dev/null
```

Tell the user the backup's path if one was made.

## 3. Clone

```sh
git clone https://github.com/mato777/claudine.git ~/.config/nvim
```

Check: `ls ~/.config/nvim/init.lua ~/.config/nvim/bin/remote-setup.sh` lists both files.

## 4. Run the setup script

```sh
sh ~/.config/nvim/bin/remote-setup.sh
```

It installs into `~/.local` (no sudo): Neovim 0.12.4, ripgrep 15.2.0 (if `rg` is missing) and Claude Code (official installer, if `claude` is missing).
It installs tmux with the system package manager (sudo) if missing, writes `~/.tmux.conf` only if none exists, and installs the Neovim plugins.

If it prints "Add ~/.local/bin to your PATH", do that for the user's shell and open a new shell (or `export PATH="$HOME/.local/bin:$PATH"`):

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc   # or ~/.zshrc for zsh
```

If `~/.tmux.conf` already existed, the script prints one line to add: `source-file ~/.config/nvim/tmux.conf`.
Ask the user before editing their file. With their yes, append it and reload tmux:

```sh
echo 'source-file ~/.config/nvim/tmux.conf' >> ~/.tmux.conf
tmux source-file ~/.tmux.conf 2>/dev/null || true   # only if tmux is running
```

It sets only `set-clipboard on`, `bell-action any` and `escape-time 10`; it does not change the user's other tmux settings (e.g. `mouse`).

## 5. Verify

Run each command. All must succeed.

```sh
nvim --version | head -n 1            # NVIM v0.12.4 (or newer 0.12+)
rg --version | head -n 1              # ripgrep ...
claude --version                      # ... (Claude Code)
tmux -V                               # tmux ...

# Config loads with no errors, theme and plugins present (headless: does not start Claude)
nvim --headless -c 'lua print("theme=" .. tostring(vim.g.colors_name))' \
  -c 'lua for _, m in ipairs({"telescope", "claudecode", "nvim-tree", "snacks"}) do print(m .. "=" .. tostring(pcall(require, m))) end' \
  -c 'qa' 2>&1
```

Expected from the last command: `theme=tokyonight-night` and `telescope=true`, `claudecode=true`, `nvim-tree=true`, `snacks=true`, and no lines starting with `E` followed by a number (errors).
If a plugin is `false`, run `nvim --headless -c 'qa'` once more (first launch downloads plugins) and re-check.

## 6. Hand over to the user

Tell the user to do these themselves:

1. Log in to Claude once: `claude` (follow the prompts, then exit).
2. From their Mac, connect with tmux so sessions survive disconnects:
   `ssh <host> -t 'tmux new -A -s work'`
3. Open a project: `cd <project> && nvim`.
4. In Warp on the Mac: Settings → Features → Keys → enable **Left Option key is Meta** (the Option shortcuts need it).

## Updating an existing install

```sh
git -C ~/.config/nvim pull
nvim --headless -c "lua vim.pack.update(nil, { target = 'lockfile', force = true })" -c 'qa'   # plugins to the lockfile's versions
grep -qF 'source-file ~/.config/nvim/tmux.conf' ~/.tmux.conf || echo "ask the user to add: source-file ~/.config/nvim/tmux.conf"
tmux source-file ~/.tmux.conf 2>/dev/null || true
```

## Notes

- Claude in this workspace always runs with `--dangerously-skip-permissions`: it runs commands without asking. Make sure the user knows.
- The "session needs you" sound is a terminal bell over SSH; Warp on the Mac plays it.
- Key reference: `README.md`.
