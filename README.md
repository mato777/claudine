# Neovim + Claude Code

Layout: `[ file tree ] [ file above / Claude ] [ sessions ]`. Run `nvim` in a project folder with no file arguments.
Claude always runs with `--dangerously-skip-permissions`.

## Keys (they work while typing in Claude; Warp needs "Left Option key is Meta")

| Keys | Effect |
|---|---|
| `Option+1` / `Option+2` | Go to the file tree / sessions list; press again to hide it and go back to Claude |
| `Option+h/j/k/l` | Move between windows |
| `Option+s` / `Option+g` | Find a session by title or prompts / search inside every session |
| `Option+o` | Files, images, folders and URLs Claude mentioned; Enter opens one |
| `Option+t` | Shell in the project folder; press again to hide it |
| `Option+←/→/↑/↓`, `Option+=` | Resize the current window / make windows equal |
| `Space ff` / `fg` / `fb` / `fr` | Telescope: files / grep / buffers / recent |
| `Space cs` (visual) / `Space cb` | Send the selection / the current file to Claude |
| `Space ca` / `Space cd` | Accept / reject a diff Claude proposed |
| `:ClaudeSound` | Turn the "session needs you" sound off or on |

In the sessions list: Enter switches (running) or resumes (history), `n` new, `x` stop, `/` search, `?` help.
`!` marks a session that rang because it's waiting for you.

## On a server over SSH

Step-by-step for an agent (or you): [instructions.md](instructions.md).

```sh
git clone https://github.com/mato777/claudine.git ~/.config/nvim
sh ~/.config/nvim/bin/remote-setup.sh   # Neovim 0.12.4, ripgrep, tmux, Claude Code; Linux x86_64/arm64
claude                                  # log in once
```

Then every time: `ssh host -t 'tmux new -A -s work'`, `cd <project> && nvim`.

Over SSH: the "needs you" sound is a terminal bell (Warp plays it on your Mac), copies go to your Mac's clipboard, and URLs/images from `Option+o` are copied instead of opened.
