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

---Parse diff stats from git show --stat output
---@param lines string[]
---@return table[] files
local function parse_diff_stats(lines)
  local files = {}
  local in_stats = false
  
  for _, line in ipairs(lines) do
    if line:match("^ .+%s+|") then
      in_stats = true
      local path, changes = line:match("^ (.-)%s+|%s+(.+)")
      if path and changes then
        local additions = changes:match("%+*")
        local deletions = changes:match("%-*")
        table.insert(files, {
          path = vim.trim(path),
          changes = vim.trim(changes),
          additions = additions and #additions or 0,
          deletions = deletions and #deletions or 0,
        })
      end
    elseif in_stats and line:match("^%s*%d+ file") then
      break
    end
  end
  
  return files
end

---Create commit view buffer
---@param commit string
---@return number buf, number win
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
  
  -- Add instruction at the end
  table.insert(lines, "")
  table.insert(lines, "Press q to close, d to view diff in separate view")
  
  -- Parse commit info to get the full OID for the window title
  local commit_info = parse_commit_info(result.stdout)
  
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  
  -- Create floating window - make it larger to accommodate the diff
  local width = math.min(120, vim.o.columns - 4)
  local height = math.min(vim.o.lines - 4, #lines + 2)
  
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Commit " .. git.abbreviate_commit(commit_info.oid) .. " ",
    title_pos = "center",
  })
  
  -- Set up keymaps
  vim.keymap.set("n", "q", function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })
  
  vim.keymap.set("n", "<Esc>", function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })
  
  return buf, win, commit_info.oid
end

return M
