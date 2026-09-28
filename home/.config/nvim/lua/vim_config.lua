local o = vim.opt

local external_file_changes = vim.api.nvim_create_augroup('external_file_changes', { clear = true })
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
  group = external_file_changes,
  command = 'checktime',
  desc = 'Reload files changed outside Neovim',
})

vim.g.mapleader = ' '          -- space is the leader key
o.expandtab = true             -- spaces, not tabs
o.shiftwidth = 2               -- 2 spaces per indent level
o.number = true                -- absolute number on the cursor line, relative elsewhere
o.relativenumber = true        -- relative line numbers for fast jumps
o.ignorecase = true            -- search is case-insensitive by default
o.smartcase = true             -- case-sensitive only if i type a capital
o.clipboard = 'unnamedplus'    -- share the system clipboard
o.scrolloff = 16               -- keep cursor away from the screen edge
o.updatetime = 500             -- trigger idle checks after 500 ms for faster external-file refresh
o.undofile = true              -- persistent undo across sessions
o.autoread = true              -- reload unchanged buffers after checktime detects an external edit
o.mouse = ''                   -- no mouse in nvim; also lets Herdr keep host mouse capture off so Escape isn't swallowed

