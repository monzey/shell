-- Session profile loaded by openvide after the user's Neovim configuration.
if vim.g.openvide_profile_loaded then
  return
end
vim.g.openvide_profile_loaded = true

local profile_dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local saved_linespace

local function configure_codediff()
  -- Nix supplies these plugins with shell, independently of the user's config.
  for _, plugin in ipairs({ "nui.nvim", "codediff.nvim" }) do
    local path = profile_dir .. "/nvim-plugins/" .. plugin
    if vim.fn.isdirectory(path) == 1 then
      vim.opt.runtimepath:prepend(path)
    end
  end
  local ok, codediff = pcall(require, "codediff")
  if not ok then
    vim.notify("Openvide needs codediff.nvim and nui.nvim to open project diffs", vim.log.levels.WARN)
    return false
  end

  local compact = vim.env.OPENVIDE_NVIM_COMPACT == "1" or vim.o.columns < 120
  local opts = vim.deepcopy(require("codediff.config").options)
  opts.diff.layout = "inline"
  opts.explorer.view_mode = "tree"
  opts.explorer.position = compact and "bottom" or "left"
  opts.explorer.height = 8
  opts.explorer.width = 28
  opts.explorer.initial_focus = "modified"
  opts.explorer.focus_on_select = true
  opts.history.view_mode = "tree"
  opts.keymaps.view.next_file = "<Tab>"
  opts.keymaps.view.prev_file = "<S-Tab>"
  codediff.setup(opts)
  vim.cmd.runtime("plugin/codediff.lua")

  local lifecycle = require("codediff.ui.lifecycle")
  local welcome = require("codediff.ui.welcome")
  local gutter = {
    number = true,
    relativenumber = false,
    numberwidth = 4,
    signcolumn = "no",
    foldcolumn = "0",
    statuscolumn = "",
  }
  local function refresh_view()
    local session = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
    if session and compact and vim.g.neovide then
      if saved_linespace == nil then
        saved_linespace = vim.o.linespace
      end
      vim.o.linespace = 0
    elseif saved_linespace ~= nil then
      vim.o.linespace = saved_linespace
      saved_linespace = nil
    end
    if not session then
      return
    end
    session.window_profiles = session.window_profiles or {}
    for side, winid in pairs({ original = session.original_win, modified = session.modified_win }) do
      if winid and vim.api.nvim_win_is_valid(winid) then
        -- CodeDiff restores this snapshot on focus. Keep it aligned with the
        -- compact gutter instead of correcting a wider gutter after redraw.
        session.window_profiles[side] = vim.tbl_extend("force", session.window_profiles[side] or {}, gutter)
        if not welcome.is_welcome_buffer(vim.api.nvim_win_get_buf(winid)) then
          local options = vim.tbl_extend("force", gutter, {
            wrap = true, linebreak = true, breakindent = true, colorcolumn = "", list = false,
          })
          for name, value in pairs(options) do
            if vim.wo[winid][name] ~= value then
              vim.wo[winid][name] = value
            end
          end
        end
      end
    end
  end
  local group = vim.api.nvim_create_augroup("openvide_nvim_view", { clear = true })
  local refresh_later = vim.schedule_wrap(refresh_view)
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "CodeDiffClose", "CodeDiffFileSelect" },
    callback = refresh_later,
  })
  vim.api.nvim_create_autocmd("TabEnter", { group = group, callback = refresh_later })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffOpen",
    callback = function()
      -- Register after CodeDiff's per-session handlers, so focus finishes
      -- with the final layout before Neovim draws the next frame.
      local events = { "WinEnter", "BufEnter", "BufWinEnter", "FileType" }
      for _, event in ipairs(events) do
        vim.api.nvim_clear_autocmds({ group = group, event = event })
      end
      vim.api.nvim_create_autocmd(events, { group = group, callback = refresh_view })
      refresh_view()
    end,
  })
  -- CodeDiff resets wrap on focus and file changes. Restore it in the same
  -- event, before a frame can be drawn with a different text layout.
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "wrap",
    callback = function()
      local session = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
      local winid = vim.api.nvim_get_current_win()
      if session and (winid == session.original_win or winid == session.modified_win)
        and not vim.wo.wrap and not welcome.is_welcome_buffer(vim.api.nvim_get_current_buf()) then
        vim.cmd("noautocmd setlocal wrap")
      end
    end,
  })
  return true
end

local group = vim.api.nvim_create_augroup("openvide_nvim_startup", { clear = true })
local ready = not vim.g.lazy_did_setup
local scheduled, stdin = false, false

local function open_diff()
  if not ready or scheduled or vim.v.vim_did_enter == 0 or #vim.api.nvim_list_uis() == 0 then
    return
  end
  scheduled = true
  vim.schedule(function()
    vim.api.nvim_del_augroup_by_id(group)
    if stdin or vim.fn.argc(-1) > 0 or vim.bo.modified then
      return
    end
    if vim.api.nvim_buf_get_name(0) ~= "" and vim.bo.filetype ~= "snacks_dashboard" then
      return
    end
    if not vim.fs.root(vim.uv.cwd(), { ".git" }) then
      return
    end
    if configure_codediff() then
      vim.cmd("CodeDiff --inline")
    end
  end)
end

-- LazyVim's dashboard and Neovide's UI may become ready in either order.
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = "VeryLazy",
  once = true,
  callback = function()
    ready = true
    open_diff()
  end,
})
vim.api.nvim_create_autocmd({ "VimEnter", "UIEnter" }, { group = group, callback = open_diff })
vim.api.nvim_create_autocmd("StdinReadPre", {
  group = group,
  callback = function()
    stdin = true
  end,
})
open_diff()
