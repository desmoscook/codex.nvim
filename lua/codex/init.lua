local vim = vim
local installer = require 'codex.installer'
local state = require 'codex.state'

local M = {}

local config = {
  keymaps = {
    toggle = nil,
    sidebar = nil,
    float = nil,
    quit = '<C-q>', -- Default: Ctrl+q to quit
  },
  border = 'single',
  width = 0.8,
  height = 0.8,
  cmd = 'codex',
  model = nil, -- Default to the latest model
  autoinstall = true,
  panel = false,       -- if true, open Codex in a side-panel instead of floating window
  use_buffer = false,  -- if true, capture Codex stdout into a normal buffer instead of a terminal
}

local function resolve_open_opts(opts)
  local open_opts = {}

  if type(opts) == 'boolean' then
    open_opts.panel = opts
  elseif type(opts) == 'table' then
    open_opts = vim.deepcopy(opts)
  end

  if open_opts.panel == nil then
    open_opts.panel = config.panel
  end

  if open_opts.width == nil then
    open_opts.width = config.width
  end

  if open_opts.height == nil then
    open_opts.height = config.height
  end

  if open_opts.border == nil then
    open_opts.border = config.border
  end

  return open_opts
end

function M.setup(user_config)
  config = vim.tbl_deep_extend('force', config, user_config or {})

  vim.api.nvim_create_user_command('Codex', function()
    M.toggle()
  end, { desc = 'Toggle Codex popup' })

  vim.api.nvim_create_user_command('CodexToggle', function()
    M.toggle()
  end, { desc = 'Toggle Codex popup (alias)' })

  vim.api.nvim_create_user_command('CodexSidebar', function()
    M.open { panel = true }
  end, { desc = 'Open Codex side-panel' })

  vim.api.nvim_create_user_command('CodexFloat', function()
    M.open { panel = false }
  end, { desc = 'Open Codex floating popup' })

  if config.keymaps.toggle then
    vim.api.nvim_set_keymap('n', config.keymaps.toggle, '<cmd>CodexToggle<CR>', { noremap = true, silent = true })
  end

  if config.keymaps.sidebar then
    vim.api.nvim_set_keymap('n', config.keymaps.sidebar, '<cmd>CodexSidebar<CR>', { noremap = true, silent = true })
  end

  if config.keymaps.float then
    vim.api.nvim_set_keymap('n', config.keymaps.float, '<cmd>CodexFloat<CR>', { noremap = true, silent = true })
  end
end

local function open_window(open_opts)
  local width = math.floor(vim.o.columns * open_opts.width)
  local height = math.floor(vim.o.lines * open_opts.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local styles = {
    single = {
      { '┌', 'FloatBorder' },
      { '─', 'FloatBorder' },
      { '┐', 'FloatBorder' },
      { '│', 'FloatBorder' },
      { '┘', 'FloatBorder' },
      { '─', 'FloatBorder' },
      { '└', 'FloatBorder' },
      { '│', 'FloatBorder' },
    },
    double = {
      { '╔', 'FloatBorder' },
      { '═', 'FloatBorder' },
      { '╗', 'FloatBorder' },
      { '║', 'FloatBorder' },
      { '╝', 'FloatBorder' },
      { '═', 'FloatBorder' },
      { '╚', 'FloatBorder' },
      { '║', 'FloatBorder' },
    },
    rounded = {
      { '╭', 'FloatBorder' },
      { '─', 'FloatBorder' },
      { '╮', 'FloatBorder' },
      { '│', 'FloatBorder' },
      { '╯', 'FloatBorder' },
      { '─', 'FloatBorder' },
      { '╰', 'FloatBorder' },
      { '│', 'FloatBorder' },
    },
    none = nil,
  }

  local border = type(open_opts.border) == 'string' and styles[open_opts.border] or open_opts.border

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = border,
  })
end

--- Open Codex in a side-panel (vertical split) instead of floating window
local function open_panel(open_opts)
  -- Create a vertical split on the right and show the buffer
  vim.cmd('vertical rightbelow vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, state.buf)
  -- Adjust width according to config (percentage of total columns)
  local width = math.floor(vim.o.columns * open_opts.width)
  vim.api.nvim_win_set_width(win, width)
  state.win = win
end

function M.open(opts)
  local open_opts = resolve_open_opts(opts)
  local target_panel = open_opts.panel

  local function create_clean_buf()
    local buf = vim.api.nvim_create_buf(false, false)

    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'codex')

    -- Apply configured quit keybinding

    if config.keymaps.quit then
      local quit_cmd = [[<cmd>lua require('codex').close()<CR>]]
      vim.api.nvim_buf_set_keymap(buf, 't', config.keymaps.quit, [[<C-\><C-n>]] .. quit_cmd, { noremap = true, silent = true })
      vim.api.nvim_buf_set_keymap(buf, 'n', config.keymaps.quit, quit_cmd, { noremap = true, silent = true })
    end

    return buf
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    if state.layout == target_panel then
      vim.api.nvim_set_current_win(state.win)
      return
    end

    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end

  local check_cmd = type(config.cmd) == 'string' and not config.cmd:find '%s' and config.cmd or (type(config.cmd) == 'table' and config.cmd[1]) or nil

  if check_cmd and vim.fn.executable(check_cmd) == 0 then
    if config.autoinstall then
      installer.prompt_autoinstall(function(success)
        if success then
          M.open(open_opts) -- Try again after installing
        else
          -- Show failure message *after* buffer is created
          if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
            state.buf = create_clean_buf()
          end
          vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
            'Autoinstall cancelled or failed.',
            '',
            'You can install manually with:',
            '  npm install -g @openai/codex',
          })
          if target_panel then open_panel(open_opts) else open_window(open_opts) end
          state.layout = target_panel
        end
      end)
      return
    else
      -- Show fallback message
      if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        state.buf = vim.api.nvim_create_buf(false, false)
      end
      vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
        'Codex CLI not found, autoinstall disabled.',
        '',
        'Install with:',
        '  npm install -g @openai/codex',
        '',
        'Or enable autoinstall in setup: require("codex").setup{ autoinstall = true }',
      })
      if target_panel then open_panel(open_opts) else open_window(open_opts) end
      state.layout = target_panel
      return
    end
  end

  local function is_buf_reusable(buf)
    return type(buf) == 'number' and vim.api.nvim_buf_is_valid(buf)
  end

  if not is_buf_reusable(state.buf) then
    state.buf = create_clean_buf()
  end

  if target_panel then open_panel(open_opts) else open_window(open_opts) end
  state.layout = target_panel

  if not state.job then
    -- assemble command
    local cmd_args = type(config.cmd) == 'string' and { config.cmd } or vim.deepcopy(config.cmd)
    if config.model then
      table.insert(cmd_args, '-m')
      table.insert(cmd_args, config.model)
    end

    if config.use_buffer then
      -- capture stdout/stderr into normal buffer
      state.job = vim.fn.jobstart(cmd_args, {
        cwd = vim.loop.cwd(),
        stdout_buffered = true,
        on_stdout = function(_, data)
          if not data then return end
          for _, line in ipairs(data) do
            if line ~= '' then
              vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, { line })
            end
          end
        end,
        on_stderr = function(_, data)
          if not data then return end
          for _, line in ipairs(data) do
            if line ~= '' then
              vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, { '[ERR] ' .. line })
            end
          end
        end,
        on_exit = function(_, code)
          state.job = nil
          vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, {
            ('[Codex exit: %d]'):format(code),
          })
        end,
      })
    else
      -- use a terminal buffer
      state.job = vim.fn.termopen(cmd_args, {
        cwd = vim.loop.cwd(),
        on_exit = function()
          state.job = nil
        end,
      })
    end
  end
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.layout = nil
end

function M.toggle(opts)
  local open_opts = resolve_open_opts(opts)
  local target_panel = open_opts.panel

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    if state.layout == target_panel then
      M.close()
    else
      M.open(open_opts)
    end
  else
    M.open(open_opts)
  end
end

function M.statusline()
  if state.job and not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    return '[Codex]'
  end
  return ''
end

function M.status()
  return {
    function()
      return M.statusline()
    end,
    cond = function()
      return M.statusline() ~= ''
    end,
    icon = '',
    color = { fg = '#51afef' },
  }
end

return setmetatable(M, {
  __call = function(_, opts)
    M.setup(opts)
    return M
  end,
})
