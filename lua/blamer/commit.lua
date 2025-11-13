-- Commit viewing functionality
local git = require("blamer.git")
local api = vim.api

local M = {}

---Parse commit information from git show output
---@param lines string[]
---@return table commit_info
local function parse_commit_info(lines)
  local info = {
    oid = "",
    author = "",
    author_email = "",
    author_date = "",
    committer = "",
    committer_email = "",
    committer_date = "",
    message = {},
  }

  local in_message = false
  for _, line in ipairs(lines) do
    if line:match("^commit ") then
      info.oid = line:match("^commit (%x+)")
    elseif line:match("^Author:") then
      local author, email = line:match("^Author:%s+(.-)%s+<(.-)>")
      info.author = author or ""
      info.author_email = email or ""
    elseif line:match("^AuthorDate:") then
      info.author_date = line:match("^AuthorDate:%s+(.+)") or ""
    elseif line:match("^Commit:") then
      local committer, email = line:match("^Commit:%s+(.-)%s+<(.-)>")
      info.committer = committer or ""
      info.committer_email = email or ""
    elseif line:match("^CommitDate:") then
      info.committer_date = line:match("^CommitDate:%s+(.+)") or ""
    elseif line == "" and not in_message then
      in_message = true
    elseif in_message and not line:match("^diff ") and not line:match("^index ") then
      table.insert(info.message, line)
    end
  end

  return info
end

---Create commit view buffer in a new tab
---@param commit string
---@return number|nil buf, number|nil win, string|nil oid
function M.create_commit_view(commit)
  local result = git.git_exec({ "show", "--format=fuller", commit })

  if result.code ~= 0 then
    vim.notify("Failed to show commit", vim.log.levels.ERROR, { title = "Blamer" })
    return nil, nil
  end

  -- Create buffer
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "git"

  -- Use the full output from git show which includes both commit info and diff
  local lines = result.stdout

  -- Parse commit info to get the full OID
  local commit_info = parse_commit_info(result.stdout)

  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Open in a new tab
  vim.cmd("tabnew")
  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)

  -- Set buffer name
  local commit_short = git.abbreviate_commit(commit_info.oid)
  pcall(api.nvim_buf_set_name, buf, string.format("commit:%s", commit_short))

  -- Set up keymaps
  vim.keymap.set("n", "q", function()
    vim.cmd("tabclose")
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "<Esc>", function()
    vim.cmd("tabclose")
  end, { buffer = buf, silent = true })

  return buf, win, commit_info.oid
end

return M
