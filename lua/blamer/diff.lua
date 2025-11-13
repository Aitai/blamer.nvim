-- Diff viewing functionality with diffview integration and fallback
local git = require("blamer.git")
local api = vim.api

local M = {}

---Check if diffview is installed
---@return boolean
function M.has_diffview()
  return pcall(require, "diffview")
end

---Open diff using diffview.nvim
---@param commit string
---@param file_path string|nil
function M.open_with_diffview(commit, file_path)
  local diffview_lib = require("diffview.lib")
  local utils = require("diffview.utils")

  local args = utils.tbl_pack(commit .. "^!")

  if file_path then
    table.insert(args, "--selected-file=" .. file_path)
  end

  local view = diffview_lib.diffview_open(args)
  if view then
    view:open()
  end
end

---Open diff using native Neovim diff
---@param commit string
---@param file_path string|nil
function M.open_with_native_diff(commit, file_path)
  -- Get the commit diff
  local args = { "show", commit }
  if file_path then
    table.insert(args, "--")
    table.insert(args, file_path)
  end

  local result = git.git_exec(args)

  if result.code ~= 0 then
    vim.notify("Failed to get diff", vim.log.levels.ERROR, { title = "Blamer" })
    return
  end

  -- Create a scratch buffer with the diff
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "git"

  api.nvim_buf_set_lines(buf, 0, -1, false, result.stdout)
  vim.bo[buf].modifiable = false

  -- Open in a new tab
  vim.cmd("tabnew")
  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)

  -- Set up keymaps
  vim.keymap.set("n", "q", function()
    vim.cmd("tabclose")
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "<Esc>", function()
    vim.cmd("tabclose")
  end, { buffer = buf, silent = true })

  -- Set buffer name
  local commit_short = git.abbreviate_commit(commit)
  local name = file_path and
    string.format("diff:%s:%s", commit_short, file_path) or
    string.format("diff:%s", commit_short)
  pcall(api.nvim_buf_set_name, buf, name)
end

---Open diff view for a commit
---@param commit string
---@param file_path string|nil Optional file path to filter diff
function M.open_diff(commit, file_path)
  if M.has_diffview() then
    M.open_with_diffview(commit, file_path)
  else
    M.open_with_native_diff(commit, file_path)
  end
end

---Open a side-by-side diff for a specific file at a commit
---@param commit string
---@param file_path string
function M.open_file_diff(commit, file_path)
  -- Get file content at parent commit
  local parent_result = git.git_exec({ "show", commit .. "^:" .. file_path })
  local current_result = git.git_exec({ "show", commit .. ":" .. file_path })

  if parent_result.code ~= 0 or current_result.code ~= 0 then
    vim.notify("Failed to get file versions", vim.log.levels.ERROR, { title = "Blamer" })
    return
  end

  -- Create two buffers
  local parent_buf = api.nvim_create_buf(false, true)
  local current_buf = api.nvim_create_buf(false, true)

  -- Set up parent buffer
  vim.bo[parent_buf].buftype = "nofile"
  vim.bo[parent_buf].bufhidden = "wipe"
  vim.bo[parent_buf].swapfile = false
  api.nvim_buf_set_lines(parent_buf, 0, -1, false, parent_result.stdout)
  vim.bo[parent_buf].modifiable = false

  -- Set up current buffer
  vim.bo[current_buf].buftype = "nofile"
  vim.bo[current_buf].bufhidden = "wipe"
  vim.bo[current_buf].swapfile = false
  api.nvim_buf_set_lines(current_buf, 0, -1, false, current_result.stdout)
  vim.bo[current_buf].modifiable = false

  -- Detect filetype from filename
  local ft = vim.filetype.match({ filename = file_path }) or "text"
  vim.bo[parent_buf].filetype = ft
  vim.bo[current_buf].filetype = ft

  -- Open in new tab with vertical split
  vim.cmd("tabnew")
  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, parent_buf)

  vim.cmd("vsplit")
  local win2 = api.nvim_get_current_win()
  api.nvim_win_set_buf(win2, current_buf)

  -- Enable diff mode
  vim.cmd("windo diffthis")

  -- Set buffer names
  local commit_short = git.abbreviate_commit(commit)
  pcall(api.nvim_buf_set_name, parent_buf, string.format("%s^:%s", commit_short, file_path))
  pcall(api.nvim_buf_set_name, current_buf, string.format("%s:%s", commit_short, file_path))

  -- Set up keymaps for both buffers
  for _, buf in ipairs({ parent_buf, current_buf }) do
    vim.keymap.set("n", "q", function()
      vim.cmd("tabclose")
    end, { buffer = buf, silent = true })

    vim.keymap.set("n", "<Esc>", function()
      vim.cmd("tabclose")
    end, { buffer = buf, silent = true })
  end
end

return M
