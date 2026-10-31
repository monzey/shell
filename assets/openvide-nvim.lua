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
    for _, winid in ipairs({ session.original_win, session.modified_win }) do
      if winid and vim.api.nvim_win_is_valid(winid) then
        vim.wo[winid].wrap = true
        vim.wo[winid].linebreak = true
        vim.wo[winid].breakindent = true
        vim.wo[winid].number = true
        vim.wo[winid].relativenumber = false
        vim.wo[winid].signcolumn = "no"
        vim.wo[winid].foldcolumn = "0"
        vim.wo[winid].colorcolumn = ""
        vim.wo[winid].list = false
      end
    end
  end
  local group = vim.api.nvim_create_augroup("openvide_nvim_view", { clear = true })
  local refresh_later = vim.schedule_wrap(refresh_view)
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "CodeDiffOpen", "CodeDiffClose", "CodeDiffFileSelect" },
    callback = refresh_later,
  })
  vim.api.nvim_create_autocmd({ "TabEnter", "BufWinEnter" }, { group = group, callback = refresh_later })
  -- CodeDiff resets wrap when rendering a different file; keep narrow panes readable.
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "wrap",
    callback = function()
      if not vim.wo.wrap then
        refresh_later()
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
