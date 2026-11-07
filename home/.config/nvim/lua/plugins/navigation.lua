return {
  {
    -- Snacks reads MiniIcons directly, including its first-class directory
    -- mappings. It uses the Nerd Font Material Design icon collection.
    'nvim-mini/mini.icons',
    version = false,
    lazy = false,
    opts = { style = 'glyph' },
    config = function(_, opts)
      local icons = require('mini.icons')
      icons.setup(opts)
      icons.mock_nvim_web_devicons()
    end,
  },
  {
    -- Bridges Snacks Picker to PKief's actual Material Icon Theme.
    -- WezTerm uses mini.icons as a safe fallback; Ghostty and Kitty render the
    -- theme's original PNG/SVG assets through the Kitty Graphics Protocol.
    'Mirsmog/real-icons.nvim',
    lazy = false,
    build = ':RealIcons install',
    dependencies = { 'nvim-mini/mini.icons' },
    opts = {
      pack = 'material',
      backend = 'auto',
      fallback = { enabled = true, provider = 'mini' },
      integrations = { snacks_picker = true },
    },
  },
  {
    'stevearc/oil.nvim',
    lazy = false,
    opts = {
      default_file_explorer = true,
      view_options = { show_hidden = true },
      win_options = { signcolumn = 'yes:2' },
      keymaps = {
        ['y.'] = 'actions.copy_to_system_clipboard',
        ['<C-p>'] = { 'actions.preview', opts = { vertical = true, split = 'botright' } },
      },
    },
    keys = {
      { '<leader>e', '<cmd>Oil<cr>', desc = 'Oil File Browser' },
      { '<leader>o', '<cmd>Oil<cr>', desc = 'Oil File Browser' },
    },
  },
  {
    'refractalize/oil-git-status.nvim',
    lazy = false,
    dependencies = { 'stevearc/oil.nvim' },
    opts = {},
  },
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      picker = {
        enabled = true,
        ui_select = true,
      },
      explorer = { enabled = false },
      notifier = { enabled = true },
      input = { enabled = true },
    },
    keys = {
      { '<leader>f', function() Snacks.picker.files() end, desc = 'Find Files' },
      { '<leader>s', function() Snacks.picker.grep() end,  desc = 'Search Text' },
      { '<leader>b', function() Snacks.picker.buffers() end, desc = 'Buffers' },
      { 'gd', function() Snacks.picker.lsp_definitions() end, desc = 'Goto Definition' },
    },
  },
}
