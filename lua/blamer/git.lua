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

---Execute git command
---@param args string[]
---@param input string|nil
---@return table result {stdout: string[], stderr: string[], code: number}
local function git_exec(args, input)
  local stdout_data = {}
  local stderr_data = {}
  
  local cmd = vim.list_extend({ "git" }, args)
  local job_opts = {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(stdout_data, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(stderr_data, data)
      end
    end,
  }
  
  if input then
    job_opts.input = input
  end
  
  local job_id = vim.fn.jobstart(cmd, job_opts)
  local exit_code = vim.fn.jobwait({ job_id }, 30000)[1]
  
  return {
    stdout = stdout_data,
    stderr = stderr_data,
    code = exit_code,
  }
end

---Parse git blame porcelain output
---@param output string[] Lines from git blame --porcelain
---@return BlameEntry[]
function M.parse_blame_porcelain(output)
  local entries = {}
  local commit_info = {}
  local i = 1

  while i <= #output do
    local line = output[i]
    local commit, orig_line, final_line = line:match("^([a-f0-9]+) (%d+) (%d+)")
    
    if commit then
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

      local entry = {
        commit = commit,
        line_start = tonumber(orig_line),
        content = "",
        author = commit_info[commit].author,
        author_time = commit_info[commit].author_time,
        author_tz = commit_info[commit].author_tz,
        summary = commit_info[commit].summary,
        filename = commit_info[commit].filename,
        previous = commit_info[commit].previous,
      }

      local j = i + 1
      while j <= #output and not output[j]:match("^[a-f0-9]+ %d+ %d+") and not output[j]:match("^\t") do
        local metadata_line = output[j]

        local author = metadata_line:match("^author (.+)")
        if author then
          commit_info[commit].author = author
          entry.author = author
        end

        local author_time = metadata_line:match("^author%-time (%d+)")
        if author_time then
          commit_info[commit].author_time = tonumber(author_time)
          entry.author_time = tonumber(author_time)
        end

        local author_tz = metadata_line:match("^author%-tz (.+)")
        if author_tz then
          commit_info[commit].author_tz = author_tz
          entry.author_tz = author_tz
        end

        local summary = metadata_line:match("^summary (.+)")
        if summary then
          commit_info[commit].summary = summary
          entry.summary = summary
        end

        local previous = metadata_line:match("^previous ([a-f0-9]+)")
        if previous then
          commit_info[commit].previous = previous
          entry.previous = previous
        end

        local filename = metadata_line:match("^filename (.+)")
        if filename then
          commit_info[commit].filename = filename
          entry.filename = filename
        end

        j = j + 1
      end

      while j <= #output and not output[j]:match("^\t") do
        j = j + 1
      end

      if j <= #output and output[j]:match("^\t") then
        entry.content = output[j]:sub(2)
        j = j + 1
      end

      table.insert(entries, entry)
      i = j
    else
      i = i + 1
    end
  end

  return entries
end

---Get blame information for a file
---@param file string Path to file
---@param commit string|nil Commit to blame from (defaults to working tree)
---@return BlameEntry[]|nil, string|nil err
function M.blame_file(file, commit)
  -- Check cache first
  local cached = cache.get_blame(file, commit)
  if cached then
    return cached
  end

  local args = { "blame", "--porcelain" }
  if commit then
    table.insert(args, commit)
  end
  table.insert(args, "--")
  table.insert(args, file)

  local result = git_exec(args)

  if result.code ~= 0 then
    local err_msg = "Git blame failed"
    if result.stderr and #result.stderr > 0 and result.stderr[1] ~= "" then
      err_msg = err_msg .. ":\n" .. table.concat(result.stderr, "\n")
    end
    return nil, err_msg
  end

  local entries = M.parse_blame_porcelain(result.stdout)
  
  -- Cache the result
  cache.set_blame(file, commit, entries)
  
  return entries
end

---Get blame information for buffer content
---@param file string Path to file (for history lookup)
---@param content string[] Buffer content
---@return BlameEntry[]|nil, string|nil err
function M.blame_buffer(file, content)
  local args = { "blame", "--porcelain", "--contents", "-", "--", file }
  local input = table.concat(content, "\n") .. "\n"
  
  local result = git_exec(args, input)

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
  -- Check cache first
  local cached = cache.get_file(file, commit)
  if cached then
    return cached
  end

  local args = { "show", commit .. ":" .. file }
  local result = git_exec(args)

  if result.code ~= 0 then
    local err_msg = "Failed to get file content"
    if result.stderr and #result.stderr > 0 then
      err_msg = err_msg .. ":\n" .. table.concat(result.stderr, "\n")
    end
    return nil, err_msg
  end

  local content = result.stdout
  
  -- Cache the result
  cache.set_file(file, commit, content)
  
  return content
end

---Format a timestamp as a date string
---@param timestamp number Unix timestamp
---@return string Formatted date (YYYY-MM-DD)
function M.format_date(timestamp)
  return os.date("%Y-%m-%d", timestamp)
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

---Get git root directory
---@return string|nil
function M.get_git_root()
  local result = git_exec({ "rev-parse", "--show-toplevel" })
  if result.code == 0 and result.stdout[1] then
    return result.stdout[1]
  end
  return nil
end

-- Expose git_exec for use by other modules
M.git_exec = git_exec

return M
