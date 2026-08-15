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
    -- Bridges Snacks Picker/Explorer to PKief's actual Material Icon Theme.
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
    opts = { view_options = { show_hidden = true } },
    keys = { { '<leader>o', '<cmd>Oil<cr>', desc = 'Oil File Browser' } },
  },
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    opts = {
      picker = {
        enabled = true,
        sources = {
          explorer = {
            -- Keep the explorer focused while the selected text file renders in
            -- the main editor window to its right.
            -- Keep the sidebar visually quiet. `/` focuses the hidden search
            -- field whenever filtering is needed.
            layout = { preset = 'sidebar', preview = 'main', auto_hide = { 'input' } },
            actions = {
              skim_open = function(picker, item)
                if not item or not item.file or item.dir then
                  vim.notify('Select a file in the explorer first', vim.log.levels.WARN)
                  return
                end
                vim.fn.jobstart({ 'open', '-a', 'Skim', item.file }, { detach = true })
              end,
            },
            win = {
              list = {
                keys = {
                  -- Bring the selected file forward in Skim. Skim determines
                  -- whether it is a supported PDF.
                  ['S'] = 'skim_open',
                },
              },
            },
          },
        },
      },
      explorer = { enabled = true, replace_netrw = true },
      notifier = { enabled = true },
      input = { enabled = true },
    },
    keys = {
      { '<leader>e', function() Snacks.explorer() end, desc = 'File Explorer' },
      { '<leader>E', function() Snacks.explorer.reveal() end, desc = 'Reveal Current File' },
      { '<leader>f', function() Snacks.picker.files() end, desc = 'Find Files' },
      { '<leader>s', function() Snacks.picker.grep() end,  desc = 'Search Text' },
      { '<leader>b', function() Snacks.picker.buffers() end, desc = 'Buffers' },
      { 'gd', function() Snacks.picker.lsp_definitions() end, desc = 'Goto Definition' },
    },
  },
}
