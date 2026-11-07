-- Run from the repository root: nvim --headless -u NONE -l tests/nvim_navigation_test.lua
-- Uses real installed plugins and temporary Git repositories, without network access.
local root = vim.fn.getcwd()
-- Neovim owns and removes this temporary fixture directory on exit.
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, 'p')
fixture = assert(vim.uv.fs_realpath(fixture))

local function run()
  vim.opt.rtp:prepend(root .. '/home/.config/nvim')
  require('vim_config')
  -- -u NONE disables plugin loading; Lazy requires it even with explicit specs.
  vim.opt.loadplugins = true
  vim.opt.rtp:prepend(vim.fn.stdpath('data') .. '/lazy/lazy.nvim')
  local specs = dofile(root .. '/home/.config/nvim/lua/plugins/navigation.lua')
  -- Check the unchanged Gitsigns declaration without starting its repository
  -- watchers: they are unrelated to Oil and leak during macOS headless shutdown.
  -- This test never claimed coverage of Gitsigns' rendered line indicators.
  local gitsigns
  for _, plugin in ipairs(dofile(root .. '/home/.config/nvim/lua/plugins/git.lua')) do
    if plugin[1] == 'lewis6991/gitsigns.nvim' then
      gitsigns = plugin
    else
      table.insert(specs, plugin)
    end
  end
  vim.list_extend(specs, dofile(root .. '/home/.config/nvim/lua/plugins/colorscheme.lua'))
  require('lazy').setup(specs, {
    lockfile = fixture .. '/lazy-lock.json',
    install = { missing = false },
    checker = { enabled = false },
    change_detection = { enabled = false },
  })

  local repo = fixture .. '/repo'
  vim.fn.mkdir(repo .. '/nested', 'p')
  local function git(...)
    local result = vim.system({ 'git', '-c', 'core.hooksPath=/dev/null', '-C', repo, ... },
      { text = true }):wait(5000)
    assert(result.code == 0, result.stderr)
  end
  git('init', '--quiet')
  for _, file in ipairs({ 'clean.txt', 'modified.txt', 'staged.txt', 'nested/file.txt', '.gitignore' }) do
    vim.fn.writefile({ file == '.gitignore' and 'ignored.txt' or 'original' }, repo .. '/' .. file)
  end
  git('add', '.')
  git('-c', 'user.name=Navigation Test', '-c', 'user.email=test@example.invalid',
    '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'fixture')
  vim.fn.writefile({ 'changed' }, repo .. '/modified.txt')
  vim.fn.writefile({ 'changed' }, repo .. '/staged.txt')
  vim.fn.writefile({ 'changed' }, repo .. '/nested/file.txt')
  git('add', 'staged.txt')
  vim.fn.writefile({ 'new' }, repo .. '/untracked.txt')
  vim.fn.writefile({ 'ignored' }, repo .. '/ignored.txt')

  vim.cmd.edit(repo .. '/clean.txt')
  vim.api.nvim_feedkeys(' e', 'xt', false)
  assert(vim.wait(5000, function() return vim.bo.filetype == 'oil' end),
    '<leader>e must open Oil, not a sidebar explorer')
  assert(#vim.api.nvim_list_wins() == 1, 'Oil should use the editor, not create a sidebar')
  assert(not Snacks.config.explorer.enabled, 'Snacks Explorer must be disabled')
  assert(Snacks.config.picker.enabled, 'Snacks file/search pickers must stay enabled')
  assert(vim.fn.maparg(' E', 'n') == '', 'Remove the obsolete reveal-in-explorer shortcut')
  assert(vim.fn.maparg(' f', 'n') ~= '' and vim.fn.maparg(' s', 'n') ~= '',
    'Keep file and text search shortcuts')
  assert(vim.fn.maparg(' g', 'n') ~= '', 'Keep Neogit for commits and diffs')
  assert(gitsigns, 'Keep Gitsigns declared for line changes')

  local oil = require('oil')
  local namespace = vim.api.nvim_get_namespaces()['oil-git-status']
  assert(namespace, 'Oil Git status integration must load before opening a directory')
  local function statuses()
    local found = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
      local entry = oil.get_entry_on_line(0, mark[2] + 1)
      if entry then
        found[entry.name] = found[entry.name] or {}
        found[entry.name][mark[4].sign_hl_group] = vim.trim(mark[4].sign_text)
      end
    end
    return found
  end
  assert(vim.wait(5000, function()
    local found = statuses()
    return found['modified.txt'] and found['modified.txt'].OilGitStatusWorkingTreeModified == 'M'
  end), 'Unstaged changes must render a colored Git status sign')
  local found = statuses()
  assert(found['staged.txt'].OilGitStatusIndexModified == 'M', 'Show staged changes separately')
  assert(found['untracked.txt'].OilGitStatusWorkingTreeUntracked == '?', 'Show untracked files')
  assert(found['ignored.txt'].OilGitStatusWorkingTreeIgnored == '!', 'Show ignored files')
  assert(found['nested'].OilGitStatusWorkingTreeModified == 'M', 'Show changes inside directories')
  assert(found['clean.txt'].OilGitStatusWorkingTreeUnmodified == '', 'Clean files have no status symbol')
  assert(vim.wo.signcolumn == 'yes:2', 'Reserve space for both index and working-tree status')
  for _, group in ipairs({ 'OilGitStatusIndexModified', 'OilGitStatusWorkingTreeModified' }) do
    assert(vim.api.nvim_get_hl(0, { name = group, link = false }).fg, group .. ' must have a color')
  end

  vim.cmd.edit(repo .. '/clean.txt')
  vim.api.nvim_feedkeys(' o', 'xt', false)
  assert(vim.wait(5000, function() return vim.bo.filetype == 'oil' end), 'Keep <leader>o as an Oil shortcut')

  local empty = fixture .. '/empty'
  vim.fn.mkdir(empty, 'p')
  vim.cmd.edit(empty)
  assert(vim.wait(5000, function()
    return vim.bo.filetype == 'oil' and oil.get_current_dir() == empty .. '/'
  end), 'Opening a directory directly must use Oil, including empty non-Git directories')
  assert(vim.wait(5000, function()
    return vim.b.oil_git_status_started and oil.get_entry_on_line(0, 1) ~= nil
  end), 'Non-Git directories must finish loading')
  -- Oil queries Git asynchronously, including when the directory is not a repo.
  -- Let those processes finish before asserting the result or exiting Neovim.
  assert(vim.wait(5000, function()
    local running = false
    vim.uv.walk(function(handle)
      if handle:get_type() == 'process' and not handle:is_closing() then
        running = true
      end
    end)
    return not running
  end), 'Background Git queries must finish')
  assert(#vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) == 0,
    'Non-Git directories must not show false Git status signs')
  print('PASS: Oil navigation, Git colors, shortcuts, and non-Git directories')
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd('cquit 1')
end
vim.cmd('qa!')
