return {
  -- render-markdown.nvim needs treesitter parsers to know what to decorate
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter').install({ 'markdown', 'markdown_inline', 'yaml' })
      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'markdown', 'yaml' },
        callback = function() vim.treesitter.start() end,
      })
    end,
  },

  -- Live rendering for headings, checkboxes, bullets, code blocks, and callouts.
  -- Table rendering is delegated to markdown-table-wrap.nvim below because
  -- render-markdown.nvim cannot wrap long cells without breaking the row.
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    init = function()
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'markdown',
        callback = function()
          vim.opt_local.wrap = true
          vim.opt_local.linebreak = true
          vim.opt_local.breakindent = true
        end,
      })
    end,
    opts = {
      pipe_table = { enabled = false },
    },
    keys = {
      { '<leader>mv', '<cmd>RenderMarkdown toggle<cr>', desc = 'Toggle Rendered View' },
    },
  },

  -- Browser preview for Mermaid flowcharts and full-note HTML.
  -- This is a Neovim plugin (not an Obsidian community plugin). It starts a
  -- local preview server and opens the current note in a browser, where
  -- mermaid.js draws ```mermaid fences. WezTerm + Herdr cannot reliably show
  -- inline images, so diagrams stay in the browser instead of the buffer.
  {
    'iamcco/markdown-preview.nvim',
    ft = { 'markdown' },
    cmd = { 'MarkdownPreview', 'MarkdownPreviewStop', 'MarkdownPreviewToggle' },
    build = 'cd app && npm install',
    init = function()
      vim.g.mkdp_auto_start = 0
      vim.g.mkdp_auto_close = 0
      vim.g.mkdp_echo_preview_url = 1
      vim.g.mkdp_page_title = '${name}'
      vim.g.mkdp_theme = 'dark'
      vim.g.mkdp_filetypes = { 'markdown' }
      -- Replaces the plugin default stylesheet. Keep github-like rules and
      -- wrap table cells so wide vault tables stay readable.
      vim.g.mkdp_markdown_css = vim.fn.expand('~/.config/nvim/markdown-preview.css')
      vim.g.mkdp_preview_options = {
        mkit = { html = true, linkify = true, breaks = false },
        hide_yaml_meta = 1,
      }
    end,
    keys = {
      { '<leader>mp', '<cmd>MarkdownPreviewToggle<cr>', desc = 'Preview Markdown + Mermaid' },
    },
  },

  -- Wrapped pipe tables. Reader mode renders tables into a protected view,
  -- while keeping the Markdown source intact and editable with `e`.
  {
    'ice345/markdown-table-wrap.nvim',
    ft = { 'markdown' },
    opts = {
      max_width_ratio = 0.92,
      min_col_width = 10,
      max_col_width = 50,
      fit_to_window = true,
      preview_mode = 'reader',
      auto_preview = true,
      render_all = true,
      reader = {
        auto_open = 'has_table',
        wrap = true,
        linebreak = true,
        breakindent = true,
      },
    },
    keys = {
      { '<leader>mw', '<cmd>MarkdownTableTogglePreview<cr>', desc = 'Toggle Wrapped Table Preview' },
      { '<leader>mW', '<cmd>MarkdownTableReader<cr>', desc = 'Open Wrapped Table Reader' },
      { '<leader>mE', '<cmd>MarkdownTableEditSource<cr>', desc = 'Edit Table Source' },
    },
  },

  -- vault-aware navigation: wikilinks, backlinks, tags, note creation/rename
  {
    'obsidian-nvim/obsidian.nvim',
    ft = { 'markdown' },
    dependencies = { 'nvim-lua/plenary.nvim', 'folke/snacks.nvim' },
    opts = {
      workspaces = {
        {
          name = 'vault',
          path = vim.fn.expand('~/github/vault'),
        },
      },
      -- Pin the Snacks adapter. Auto-detect can require a missing
      -- obsidian.picker._snacks module depending on plugin/cache version.
      picker = { name = 'snacks.picker' },
      -- render-markdown.nvim already owns the visuals; don't let obsidian.nvim
      -- fight it over conceal/extmarks
      ui = { enable = false },
      legacy_commands = false,
    },
    keys = {
      { '<leader>mb', '<cmd>Obsidian backlinks<cr>', desc = 'Backlinks' },
      { '<leader>mq', '<cmd>Obsidian quick_switch<cr>', desc = 'Quick Switch Note' },
      { '<leader>mn', '<cmd>Obsidian new<cr>', desc = 'New Note' },
      { '<leader>mr', '<cmd>Obsidian rename<cr>', desc = 'Rename Note (fixes backlinks)' },
      { '<leader>mt', '<cmd>Obsidian tags<cr>', desc = 'Browse Tags' },
      { '<leader>ms', '<cmd>Obsidian search<cr>', desc = 'Search Vault' },
    },
    config = function(_, opts)
      require('obsidian').setup(opts)

      -- gf follows [[wikilinks]] on markdown buffers only; falls back to
      -- normal "go to file" everywhere else, so it never fights other filetypes
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'markdown',
        callback = function(args)
          vim.keymap.set('n', 'gf', function()
            return require('obsidian').util.cursor_on_markdown_link()
              and '<cmd>Obsidian follow_link<cr>'
              or 'gf'
          end, { buffer = args.buf, expr = true, desc = 'Follow Link (Obsidian-aware)' })
        end,
      })
    end,
  },
}
