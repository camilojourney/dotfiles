# Neovim navigation

Oil is the only directory browser. `<leader>e` and `<leader>o` open the current
file's directory; opening a directory directly also uses Oil. The leader is
Space. Inside Oil, use `-` for the parent directory, Enter to open an entry, and
`Ctrl-p` for a vertical preview. Hidden files are visible.

`oil-git-status.nvim` adds two colored Git status columns: the left is the index
(staged changes), and the right is the working tree (unstaged changes). Symbols
include `M` for modified, `A` for added, `?` for untracked, and `!` for ignored.
Changed files inside a directory also give that directory a status indicator.
These show current changes, not commit history.

Snacks Explorer and its former `<leader>E` reveal shortcut are disabled. Snacks
still supplies file search (`<leader>f`), text search (`<leader>s`), buffers
(`<leader>b`), and definitions (`gd`). Gitsigns still marks changed lines in the
editor; Neogit (`<leader>g`) still provides staging, commit history, and diffs.

Restart Neovim to load configuration changes. Lazy installs missing plugins on
startup; on a fresh machine this requires network access.

## Regression check

With the declared plugins already installed, run from the repository root:

```sh
nvim --headless -u NONE -l tests/nvim_navigation_test.lua
```

The check uses real plugins and temporary Git fixtures, does not access the
network, and leaves the managed plugin lockfile unchanged.
