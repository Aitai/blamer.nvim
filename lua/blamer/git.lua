-- Git blame functionality
local cache = require("blamer.cache")
local M = {}

---@class BlameEntry
---@field commit string Full commit hash
---@field author string Author name
---@field author_time number Unix timestamp
---@field author_tz string Timezone
---@field summary string Commit message summary
---@field previous string|nil Previous commit hash
---@field filename string Filename
---@field line_start number Starting line number in original file
---@field content string Line content

---Execute git command using vim.system (faster)
---@param args string[]
---@param opts table|nil Options: stdin (string), on_stdout (function)
---@return table result {stdout: string[], stderr: string[], code: number}
local function git_exec(args, opts)
  opts = opts or {}

  local cmd = { "git", "--no-pager" }
  vim.list_extend(cmd, args)

  local system_opts = { text = true }

  if opts.stdin then
    system_opts.stdin = opts.stdin
  end

  if opts.on_stdout then
    system_opts.stdout = opts.on_stdout
  end

  local obj = vim.system(cmd, system_opts):wait()

  local stdout_lines = {}
  if obj.stdout and obj.stdout ~= "" then
    stdout_lines = vim.split(obj.stdout, "\n")
    if stdout_lines[#stdout_lines] == "" then
      stdout_lines[#stdout_lines] = nil
    end
  end

  local stderr_lines = {}
  if obj.stderr and obj.stderr ~= "" then
    stderr_lines = vim.split(obj.stderr, "\n")
  end

  return {
    stdout = stdout_lines,
    stderr = stderr_lines,
    code = obj.code,
  }
end

---Parse git blame porcelain output (supports both regular and incremental modes)
---@param output string[] Lines from git blame --porcelain
---@return BlameEntry[]
function M.parse_blame_porcelain(output)
  local entries_map = {}  -- Store entries by final line number
  local commit_info = {}
  local i = 1

  while i <= #output do
    local line = output[i]
    local commit, orig_line, final_line, num_lines = line:match("^([a-f0-9]+) (%d+) (%d+) ?(%d*)")

    if commit then
      -- Initialize commit info if not seen before
      if not commit_info[commit] then
        commit_info[commit] = {
          commit = commit,
          author = "",
          author_time = 0,
          author_tz = "",
          summary = "",
          filename = "",
          previous = nil,
        }
      end

      local info = commit_info[commit]
      local orig_line_num = tonumber(orig_line)
      local final_line_num = tonumber(final_line)
      local line_count = tonumber(num_lines) or 1

      -- Parse metadata lines until we hit filename (which ends the header)
      i = i + 1
      local found_filename = false
      while i <= #output and not found_filename do
        local metadata_line = output[i]

        -- A new commit line starts
        if metadata_line:match("^[a-f0-9]+ %d+ %d+") then
          break
        end

        local author = metadata_line:match("^author (.+)")
        if author then
          info.author = author
          i = i + 1
          goto continue
        end

        local author_time = metadata_line:match("^author%-time (%d+)")
        if author_time then
          info.author_time = tonumber(author_time)
          i = i + 1
          goto continue
        end

        local author_tz = metadata_line:match("^author%-tz (.+)")
        if author_tz then
          info.author_tz = author_tz
          i = i + 1
          goto continue
        end

        local summary = metadata_line:match("^summary (.+)")
        if summary then
          info.summary = summary
          i = i + 1
          goto continue
        end

        local previous = metadata_line:match("^previous ([a-f0-9]+)")
        if previous then
          info.previous = previous
          i = i + 1
          goto continue
        end

        local filename = metadata_line:match("^filename (.+)")
        if filename then
          info.filename = filename
          found_filename = true
          i = i + 1
          break
        end

        -- Skip other metadata we don't care about (committer, boundary, etc.)
        i = i + 1
        ::continue::
      end

      -- Create entries for each line in this hunk
      -- Store by final line number to handle incremental mode's non-sequential output
      for j = 0, line_count - 1 do
        local entry = {
          commit = commit,
          line_start = orig_line_num + j,
          content = "",
          author = info.author,
          author_time = info.author_time,
          author_tz = info.author_tz,
          summary = info.summary,
          filename = info.filename,
          previous = info.previous,
        }

        entries_map[final_line_num + j] = entry
      end

      -- Skip the content line if present (starts with tab)
      -- In incremental mode, content lines are omitted
      if i <= #output and output[i]:match("^\t") then
        if entries_map[final_line_num] then
          entries_map[final_line_num].content = output[i]:sub(2)
        end
        i = i + 1
      end
    else
      i = i + 1
    end
  end

  -- Convert map to array sorted by line number
  -- Pre-allocate table for better performance
  local line_numbers = {}
  for line_num in pairs(entries_map) do
    table.insert(line_numbers, line_num)
  end
  table.sort(line_numbers)

  local entries = {}
  for _, line_num in ipairs(line_numbers) do
    table.insert(entries, entries_map[line_num])
  end

  return entries
end

---Get blame information for a file
---@param file string Path to file
---@param commit string|nil Commit to blame from (defaults to working tree)
---@return BlameEntry[]|nil, string|nil err
function M.blame_file(file, commit)
  -- Get file modification time and HEAD commit for cache validation (only for HEAD/current file)
  local mtime = nil
  local head_commit = nil
  if not commit or commit == "HEAD" then
    local git_root = M.get_git_root()
    if git_root then
      local full_path = git_root .. "/" .. file
      local stat = vim.loop.fs_stat(full_path)
      if stat then
        mtime = stat.mtime.sec
      end
    end

    -- Get current HEAD commit to detect when commits are made
    local head_result = git_exec({ "rev-parse", "HEAD" })
    if head_result.code == 0 and head_result.stdout[1] then
      head_commit = head_result.stdout[1]
    end
  end

  -- Check cache first
  local cached = cache.get_blame(file, commit, mtime, head_commit)
  if cached then
    return cached
  end

  -- Resolve path at commit if blaming a historical version
  local blame_path = file
  if commit then
    local resolved = M.resolve_path_at_commit(file, commit)
    if resolved then
      blame_path = resolved
    end
  end

  local args = { "blame", "--incremental", "--porcelain" }

  if commit then
    table.insert(args, commit)
  end
  table.insert(args, "--")
  table.insert(args, blame_path)

  local result = git_exec(args)

  if result.code ~= 0 then
    local err_msg = "Git blame failed"
    if result.stderr and #result.stderr > 0 and result.stderr[1] ~= "" then
      err_msg = err_msg .. ":\n" .. table.concat(result.stderr, "\n")
    end
    return nil, err_msg
  end

  local entries = M.parse_blame_porcelain(result.stdout)

  -- Cache the result with mtime and head_commit for validation
  cache.set_blame(file, commit, entries, mtime, head_commit)

  return entries
end

---Get blame information for buffer content
---@param file string Path to file (for history lookup)
---@param content string[] Buffer content
---@return BlameEntry[]|nil, string|nil err
function M.blame_buffer(file, content)
  local args = { "blame", "--incremental", "--porcelain", "--contents", "-", "--", file }
  local input = table.concat(content, "\n") .. "\n"

  local result = git_exec(args, { stdin = input })

  if result.code ~= 0 then
    local err_msg = "Git blame with buffer contents failed"
    if result.stderr and #result.stderr > 0 and result.stderr[1] ~= "" then
      err_msg = err_msg .. ":\n" .. table.concat(result.stderr, "\n")
    end
    return nil, err_msg
  end

  return M.parse_blame_porcelain(result.stdout)
end

---Get file content at a specific commit
---@param file string Path to file
---@param commit string Commit hash
---@return string[]|nil, string|nil err
function M.show_file(file, commit)
  local cached = cache.get_file(file, commit)
  if cached then
    return cached
  end

  -- Resolve path at commit (handles renames)
  local show_path = file
  local resolved = M.resolve_path_at_commit(file, commit)
  if resolved then
    show_path = resolved
  end

  local args = { "show", commit .. ":" .. show_path }
  local result = git_exec(args)

  if result.code ~= 0 then
    local err_msg = "Failed to get file content"
    if result.stderr and #result.stderr > 0 then
      err_msg = err_msg .. ":\n" .. table.concat(result.stderr, "\n")
    end
    return nil, err_msg
  end

  cache.set_file(file, commit, result.stdout)
  return result.stdout
end

---Format a timestamp as a date string
---@param timestamp number Unix timestamp
---@return string Formatted date (YYYY-MM-DD)
function M.format_date(timestamp)
  return os.date("%Y-%m-%d", timestamp) --[[@as string]]
end

---Get abbreviated commit hash
---@param commit string Full commit hash
---@return string Abbreviated hash
function M.abbreviate_commit(commit)
  if commit:match("^0+$") then
    return "Uncommitted"
  end
  return commit:sub(1, 8)
end

-- Cache for git root per buffer
local root_cache = {}

---Get git root directory with caching
---@param bufnr number|nil Buffer number for cache key
---@return string|nil
function M.get_git_root(bufnr)
  if bufnr and root_cache[bufnr] then
    return root_cache[bufnr]
  end

  local result = git_exec({ "rev-parse", "--show-toplevel" })
  if result.code == 0 and result.stdout[1] then
    local root = result.stdout[1]
    if bufnr then
      root_cache[bufnr] = root
    end
    return root
  end
  return nil
end

---Clear git root cache for a buffer
---@param bufnr number
function M.clear_git_root_cache(bufnr)
  root_cache[bufnr] = nil
end

---Resolve the file path at a specific commit (handles renames)
---@param file string Current file path
---@param commit string Commit hash to resolve path at
---@return string|nil path Path of the file at that commit
function M.resolve_path_at_commit(file, commit)
  -- Normalize commit to full hash for comparisons
  local full_commit_result = git_exec({ "rev-parse", commit })
  if full_commit_result.code ~= 0 or not full_commit_result.stdout[1] then
    return nil
  end
  local full_commit = full_commit_result.stdout[1]

  -- First check if the current path exists at this commit
  local result = git_exec({ "ls-tree", "--name-only", "-r", commit, "--", file })
  if result.code == 0 and result.stdout[1] then
    return file
  end

  -- Path doesn't exist, try to find it via rename tracking
  -- Get all renames in history with their commit hashes
  local log_result = git_exec({
    "log",
    "--follow",
    "--diff-filter=R",
    "--name-status",
    "--format=%H",
    "--",
    file
  })

  if log_result.code ~= 0 or #log_result.stdout == 0 then
    return nil
  end

  -- Parse the log output to build rename history
  -- Format: commit_hash\nR<score>\told_path\tnew_path\ncommit_hash\n...
  local renames = {}
  local current_commit_sha = nil

  for _, line in ipairs(log_result.stdout) do
    if line:match("^[a-f0-9]+$") then
      current_commit_sha = line
    elseif line:match("^R%d*\t") then
      local old_path, new_path = line:match("^R%d*\t(.+)\t(.+)$")
      if old_path and new_path and current_commit_sha then
        table.insert(renames, {
          commit = current_commit_sha,
          old_path = old_path,
          new_path = new_path,
        })
      end
    end
  end

  -- Trace back from current path through renames to find path at target commit
  -- We need to iterate multiple times to handle chains of renames
  local current_path = file
  local changed = true
  while changed do
    changed = false
    for _, rename in ipairs(renames) do
      if current_path == rename.new_path then
        -- Check if the target commit is strictly before this rename
        -- (not the rename commit itself, since at that commit the new path exists)
        if full_commit ~= rename.commit then
          local is_ancestor = git_exec({ "merge-base", "--is-ancestor", full_commit, rename.commit })
          if is_ancestor.code == 0 then
            -- Target commit is before the rename, use old path
            current_path = rename.old_path
            changed = true
            break
          end
        end
      end
    end
  end

  -- Verify the resolved path exists at the commit
  local verify_result = git_exec({ "ls-tree", "--name-only", "-r", commit, "--", current_path })
  if verify_result.code == 0 and verify_result.stdout[1] then
    return current_path
  end

  return nil
end

---Execute git command asynchronously
---@param args string[]
---@param callback function Callback with result {stdout: string[], stderr: string[], code: number}
function M.git_exec_async(args, callback)
  local cmd = { "git", "--no-pager" }
  vim.list_extend(cmd, args)

  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      local stdout_lines = {}
      if obj.stdout and obj.stdout ~= "" then
        stdout_lines = vim.split(obj.stdout, "\n")
        if stdout_lines[#stdout_lines] == "" then
          stdout_lines[#stdout_lines] = nil
        end
      end

      local stderr_lines = {}
      if obj.stderr and obj.stderr ~= "" then
        stderr_lines = vim.split(obj.stderr, "\n")
      end

      callback({
        stdout = stdout_lines,
        stderr = stderr_lines,
        code = obj.code,
      })
    end)
  end)
end

---Get blame information for a file asynchronously (for preloading)
---@param file string Path to file
---@param callback function|nil Callback with entries or nil on error
function M.blame_file_async(file, callback)
  local args = { "blame", "--incremental", "--porcelain", "--", file }

  M.git_exec_async(args, function(result)
    if result.code == 0 then
      local entries = M.parse_blame_porcelain(result.stdout)

      -- Get mtime and HEAD commit for caching
      local mtime = nil
      local head_commit = nil
      local git_root = M.get_git_root()
      if git_root then
        local full_path = git_root .. "/" .. file
        local stat = vim.loop.fs_stat(full_path)
        if stat then
          mtime = stat.mtime.sec
        end
      end

      local head_result = git_exec({ "rev-parse", "HEAD" })
      if head_result.code == 0 and head_result.stdout[1] then
        head_commit = head_result.stdout[1]
      end

      cache.set_blame(file, nil, entries, mtime, head_commit)

      if callback then
        callback(entries)
      end
    elseif callback then
      callback(nil)
    end
  end)
end

-- Expose git_exec for use by other modules
M.git_exec = git_exec

return M
