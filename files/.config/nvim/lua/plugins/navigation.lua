return {
  {
    'stevearc/oil.nvim',
    opts = { view_options = { show_hidden = true } },
    keys = { { '<leader>o', '<cmd>Oil<cr>', desc = 'Oil File Browser' } },
  },
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      picker = { enabled = true },
      explorer = { enabled = true, replace_netrw = true },
      notifier = { enabled = true },
      input = { enabled = true },
    },
    keys = {
      { '<leader>e', function() Snacks.explorer() end, desc = 'File Explorer' },
      { '<leader>f', function() Snacks.picker.files() end, desc = 'Find Files' },
      { '<leader>s', function() Snacks.picker.grep() end,  desc = 'Search Text' },
      { '<leader>b', function() Snacks.picker.buffers() end, desc = 'Buffers' },
      { 'gd', function() Snacks.picker.lsp_definitions() end, desc = 'Goto Definition' },
    },
  },
}
