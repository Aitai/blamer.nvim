-- Main blamer module
local git = require("blamer.git")
local ui = require("blamer.ui")
local commit = require("blamer.commit")
local diff = require("blamer.diff")
local cache = require("blamer.cache")

local api = vim.api

---@class Blamer
---@field file_path string
---@field blame_entries BlameEntry[]
---@field commit_colors table<string, number>
---@field next_color_index number
---@field blame_buf number
---@field view_buf number
---@field blame_win number
---@field view_win number
---@field width number
---@field highlight_ns number
---@field last_highlighted_commit string|nil
---@field history_stack table[]
---@field history_index number
---@field original_modified boolean
---@field temp_buf number|nil
---@field syncing boolean
local Blamer = {}
Blamer.__index = Blamer

local current_instance = nil

---Create new blamer instance
---@param file_path string|nil
---@return Blamer|nil
function Blamer.new(file_path)
  file_path = file_path or vim.fn.expand("%:p")
  
  local git_root = git.get_git_root()
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.ERROR, { title = "Blamer" })
    return nil
  end

  if file_path:find(git_root, 1, true) == 1 then
    file_path = file_path:sub(#git_root + 2)
  end

  local current_buf = vim.fn.bufnr("%")
  local has_modifications = api.nvim_buf_is_valid(current_buf) and vim.bo[current_buf].modified

  -- Don't load blame yet - we'll load viewport on demand
  local self = setmetatable({
    file_path = file_path,
    blame_entries = {},  -- Will be loaded on-demand
    blame_cache = {},     -- Cache blame entries by line number
    commit_colors = {},
    next_color_index = 1,
    width = 60,
    highlight_ns = api.nvim_create_namespace("blamer_hunk"),
    last_highlighted_commit = nil,
    history_stack = {},
    history_index = 0,
    view_buf = current_buf,
    original_modified = has_modifications,
    syncing = false,
    current_commit = nil,  -- Track which commit we're viewing
  }, Blamer)

  return self
end

---Load blame for a line range (viewport optimization)
---@param start_line number Starting line (1-indexed)
---@param end_line number Ending line
function Blamer:load_blame_range(start_line, end_line)
  local blame_entries, err
  
  if self.original_modified and api.nvim_buf_is_valid(self.view_buf) then
    -- For modified buffers, always load full blame
    local content = api.nvim_buf_get_lines(self.view_buf, 0, -1, false)
    blame_entries, err = git.blame_buffer(self.file_path, content)
  else
    -- Use viewport optimization for unchanged files
    blame_entries, err = git.blame_file(self.file_path, self.current_commit, start_line, end_line)
  end
  
  if not blame_entries then
    return false, err
  end
  
  -- Cache the loaded entries
  for _, entry in ipairs(blame_entries) do
    -- The entry line_start is the original line, but we need the final line number
    -- For viewport blaming, entries are returned in order starting from start_line
    local idx = #self.blame_entries + 1
    self.blame_entries[idx] = entry
    self.blame_cache[start_line + idx - 1] = entry
  end
  
  return true
end

---Ensure blame is loaded for the entire file
function Blamer:ensure_full_blame()
  if #self.blame_entries > 0 then
    return true  -- Already loaded
  end
  
  local blame_entries, err
  
  if self.original_modified and api.nvim_buf_is_valid(self.view_buf) then
    local content = api.nvim_buf_get_lines(self.view_buf, 0, -1, false)
    blame_entries, err = git.blame_buffer(self.file_path, content)
  else
    blame_entries, err = git.blame_file(self.file_path, self.current_commit)
  end
  
  if not blame_entries then
    vim.notify("Git blame failed: " .. (err or "Unknown error"), vim.log.levels.ERROR, { title = "Blamer" })
    return false
  end
  
  self.blame_entries = blame_entries
  for i, entry in ipairs(blame_entries) do
    self.blame_cache[i] = entry
  end
  
  return true
end

---Render blame lines
---@return string[] lines
---@return table[] highlights {line: number, hl_group: string, col_start: number, col_end: number}
function Blamer:render_blame_lines()
  local lines = {}
  local highlights = {}
  local hunks = ui.get_hunks(self.blame_entries)

  for _, hunk in ipairs(hunks) do
    local color_idx
    color_idx, self.next_color_index = ui.get_commit_color_index(
      self.commit_colors, self.next_color_index, hunk.commit
    )
    self.commit_colors[hunk.commit] = color_idx

    local commit_short = git.abbreviate_commit(hunk.commit)
    local date = git.format_date(hunk.author_time)
    local author = hunk.author
    local summary = hunk.summary
    local color = ui.get_commit_color(self.commit_colors, hunk.commit, false)

    if hunk.line_count == 1 then
      local prefix = string.format("- %s %s ", commit_short, author)
      local prefix_width = vim.fn.strdisplaywidth(prefix)
      local date_width = vim.fn.strdisplaywidth(date)
      local available = self.width - prefix_width - date_width - 1
      summary = ui.truncate(summary, available)
      local padding = math.max(1, self.width - vim.fn.strdisplaywidth(prefix .. summary) - date_width)

      local line = prefix .. summary .. string.rep(" ", padding) .. date
      table.insert(lines, line)

      local line_idx = #lines - 1
      local date_start = #prefix + #summary + padding
      -- "- " is 2 bytes, then commit_short
      local commit_hl_end = #"- " + #commit_short
      table.insert(highlights, { line = line_idx, hl_group = color, col_start = 0, col_end = commit_hl_end })
      table.insert(highlights, { line = line_idx, hl_group = "BlamerMessage", col_start = #prefix, col_end = #prefix + #summary })
      table.insert(highlights, { line = line_idx, hl_group = "BlamerDate", col_start = date_start, col_end = date_start + #date })
    else
      for i = 1, hunk.line_count do
        if i == 1 then
          local prefix = string.format("┍ %s %s", commit_short, author)
          local prefix_width = vim.fn.strdisplaywidth(prefix)
          local date_width = vim.fn.strdisplaywidth(date)
          local available = self.width - date_width - 2
          if prefix_width > available then
            author = ui.truncate(author, available - 2 - #commit_short)
            prefix = string.format("┍ %s %s", commit_short, author)
            prefix_width = vim.fn.strdisplaywidth(prefix)
          end
          local padding = math.max(1, self.width - prefix_width - date_width)
          local line = prefix .. string.rep(" ", padding) .. date
          table.insert(lines, line)

          local line_idx = #lines - 1
          local date_start = #prefix + padding
          -- "┍ " is 4 bytes (3 for ┍, 1 for space), then commit_short, then space
          local commit_hl_end = #"┍ " + #commit_short
          table.insert(highlights, { line = line_idx, hl_group = color, col_start = 0, col_end = commit_hl_end })
          table.insert(highlights, { line = line_idx, hl_group = "BlamerDate", col_start = date_start, col_end = date_start + #date })
        elseif i == 2 then
          local symbol = (i == hunk.line_count) and "┕ " or "│ "
          local available = self.width - vim.fn.strdisplaywidth(symbol)
          summary = ui.truncate(summary, available)
          local padding = math.max(0, self.width - vim.fn.strdisplaywidth(symbol .. summary))
          local line = symbol .. summary .. string.rep(" ", padding)
          table.insert(lines, line)

          local line_idx = #lines - 1
          table.insert(highlights, { line = line_idx, hl_group = color, col_start = 0, col_end = #symbol })
          table.insert(highlights, { line = line_idx, hl_group = "BlamerMessage", col_start = #symbol, col_end = #symbol + #summary })
        else
          local symbol = (i == hunk.line_count) and "┕" or "│"
          -- Calculate proper padding accounting for display width of symbol
          local symbol_width = vim.fn.strdisplaywidth(symbol)
          local line = symbol .. string.rep(" ", math.max(0, self.width - symbol_width))
          table.insert(lines, line)

          local line_idx = #lines - 1
          table.insert(highlights, { line = line_idx, hl_group = color, col_start = 0, col_end = #symbol })
        end
      end
    end
  end

  return lines, highlights
end

---Apply highlights to buffer
---@param highlights table[]
function Blamer:apply_highlights(highlights)
  api.nvim_buf_clear_namespace(self.blame_buf, self.highlight_ns, 0, -1)
  
  for _, hl in ipairs(highlights) do
    local col_start = hl.col_start
    local col_end = hl.col_end
    
    -- Handle negative indices by converting to positive
    if col_start < 0 or col_end < 0 then
      local line_text = api.nvim_buf_get_lines(self.blame_buf, hl.line, hl.line + 1, false)[1] or ""
      local line_len = #line_text
      
      if col_start < 0 then
        col_start = line_len + col_start + 1
      end
      if col_end < 0 then
        col_end = line_len + col_end + 1
      end
    end
    
    -- Ensure valid range
    col_start = math.max(0, col_start)
    col_end = math.max(col_start, col_end)
    
    pcall(api.nvim_buf_add_highlight,
      self.blame_buf,
      self.highlight_ns,
      hl.hl_group,
      hl.line,
      col_start,
      col_end
    )
  end
end

---Update hunk highlighting for current cursor position
function Blamer:update_hunk_highlight()
  if not api.nvim_buf_is_valid(self.blame_buf) then
    return
  end

  local line = api.nvim_win_get_cursor(self.blame_win)[1]
  local entry = self.blame_entries[line]

  if not entry or (self.last_highlighted_commit and self.last_highlighted_commit == entry.commit) then
    return
  end

  -- Clear ALL highlights in the namespace first, then reapply base + bold
  api.nvim_buf_clear_namespace(self.blame_buf, self.highlight_ns, 0, -1)
  
  self.last_highlighted_commit = entry.commit
  
  -- First, reapply base highlights for all lines
  local lines, highlights = self:render_blame_lines()
  for _, hl in ipairs(highlights) do
    local col_start = hl.col_start
    local col_end = hl.col_end
    
    if col_start < 0 or col_end < 0 then
      local line_text = api.nvim_buf_get_lines(self.blame_buf, hl.line, hl.line + 1, false)[1] or ""
      local line_len = #line_text
      
      if col_start < 0 then
        col_start = line_len + col_start + 1
      end
      if col_end < 0 then
        col_end = line_len + col_end + 1
      end
    end
    
    col_start = math.max(0, col_start)
    col_end = math.max(col_start, col_end)
    
    pcall(api.nvim_buf_add_highlight,
      self.blame_buf,
      self.highlight_ns,
      hl.hl_group,
      hl.line,
      col_start,
      col_end
    )
  end
  
  -- Now apply bold highlights on top for the selected commit
  local hunks = ui.get_hunks(self.blame_entries)
  local line_nr = 1

  for _, hunk in ipairs(hunks) do
    if hunk.commit == entry.commit then
      local bold_color = ui.get_commit_color(self.commit_colors, hunk.commit, true)
      local commit_short = git.abbreviate_commit(hunk.commit)
      
      for i = 1, hunk.line_count do
        local buf_line = line_nr + i - 2
        
        if hunk.line_count == 1 then
          -- "- " is 2 bytes, then commit_short, then space, then author
          local commit_hl_end = #"- " + #commit_short
          api.nvim_buf_add_highlight(self.blame_buf, self.highlight_ns, bold_color, buf_line, 0, commit_hl_end)
          
          -- Bold the author name in the same color
          local author_start = #"- " + #commit_short + #" "
          local author_end = author_start + #hunk.author
          api.nvim_buf_add_highlight(self.blame_buf, self.highlight_ns, bold_color, buf_line, author_start, author_end)
          
          -- Bold the message part
          local prefix = string.format("- %s %s ", commit_short, hunk.author)
          local msg_start = #prefix
          api.nvim_buf_add_highlight(self.blame_buf, self.highlight_ns, "BlamerMessageBold", buf_line, msg_start, msg_start + #hunk.summary)
        elseif i == 1 then
          -- "┍ " is 4 bytes, then commit_short, then space, then author
          local commit_hl_end = #"┍ " + #commit_short
          api.nvim_buf_add_highlight(self.blame_buf, self.highlight_ns, bold_color, buf_line, 0, commit_hl_end)
          
          -- Bold the author name in the same color
          local author_start = #"┍ " + #commit_short + #" "
          local author_end = author_start + #hunk.author
          api.nvim_buf_add_highlight(self.blame_buf, self.highlight_ns, bold_color, buf_line, author_start, author_end)
        elseif i == 2 then
          local symbol = (i == hunk.line_count) and "┕ " or "│ "
          api.nvim_buf_add_highlight(self.blame_buf, self.highlight_ns, bold_color, buf_line, 0, #symbol)
          api.nvim_buf_add_highlight(self.blame_buf, self.highlight_ns, "BlamerMessageBold", buf_line, #symbol, #symbol + #hunk.summary)
        else
          local symbol = (i == hunk.line_count) and "┕" or "│"
          api.nvim_buf_add_highlight(self.blame_buf, self.highlight_ns, bold_color, buf_line, 0, #symbol)
        end
      end
    end
    line_nr = line_nr + hunk.line_count
  end
end

---Setup scroll synchronization
function Blamer:setup_scroll_sync()
  -- Store autocmd IDs for cleanup
  self.autocmds = self.autocmds or {}
  
  local function sync_cursor(from_win, to_win)
    if self.syncing or not api.nvim_win_is_valid(to_win) then
      return
    end
    self.syncing = true
    local line = api.nvim_win_get_cursor(from_win)[1]
    pcall(api.nvim_win_set_cursor, to_win, { line, 0 })
    self.syncing = false
  end

  local augroup = api.nvim_create_augroup("Blamer_" .. self.blame_buf, { clear = true })

  api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = self.blame_buf,
    callback = function()
      if not api.nvim_buf_is_valid(self.blame_buf) then
        return
      end
      sync_cursor(self.blame_win, self.view_win)
      self:update_hunk_highlight()
      -- Lazy load blame for newly visible lines
      vim.defer_fn(function()
        if not api.nvim_buf_is_valid(self.blame_buf) then
          return
        end
        if self:load_visible_blame() then
          local lines, highlights = self:render_blame_lines()
          vim.bo[self.blame_buf].modifiable = true
          api.nvim_buf_set_lines(self.blame_buf, 0, -1, false, lines)
          vim.bo[self.blame_buf].modifiable = false
          self:apply_highlights(highlights)
        end
      end, 50)
    end,
  })

  api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    buffer = self.view_buf,
    callback = function()
      sync_cursor(self.view_win, self.blame_win)
    end,
  })

  api.nvim_create_autocmd("WinScrolled", {
    group = augroup,
    callback = function(args)
      if self.syncing then
        return
      end
      
      local scrolled_win = tonumber(args.match)
      if not scrolled_win or not api.nvim_win_is_valid(scrolled_win) then
        return
      end

      self.syncing = true
      local target_win
      if scrolled_win == self.blame_win then
        target_win = self.view_win
      elseif scrolled_win == self.view_win then
        target_win = self.blame_win
      end

      if target_win and api.nvim_win_is_valid(target_win) then
        local view = api.nvim_win_call(scrolled_win, function()
          return vim.fn.winsaveview()
        end)
        api.nvim_win_call(target_win, function()
          vim.fn.winrestview(view)
        end)
        
        -- Lazy load blame for newly visible lines
        vim.defer_fn(function()
          if not api.nvim_buf_is_valid(self.blame_buf) then
            return
          end
          if self:load_visible_blame() then
            local lines, highlights = self:render_blame_lines()
            vim.bo[self.blame_buf].modifiable = true
            api.nvim_buf_set_lines(self.blame_buf, 0, -1, false, lines)
            vim.bo[self.blame_buf].modifiable = false
            self:apply_highlights(highlights)
          end
        end, 50)
      end
      self.syncing = false
    end,
  })
  
  self.augroup = augroup
end

---Re-blame at a specific commit
---@param commit string|nil
---@param line number
---@return boolean success
function Blamer:reblame(commit, line)
  if commit and commit:match("^0+$") then
    commit = nil
  end

  local new_entries, err
  if commit then
    new_entries, err = git.blame_file(self.file_path, commit)
  else
    -- Use buffer content only if buffer was originally modified
    if self.original_modified and api.nvim_buf_is_valid(self.view_buf) then
      local content = api.nvim_buf_get_lines(self.view_buf, 0, -1, false)
      new_entries, err = git.blame_buffer(self.file_path, content)
    else
      new_entries, err = git.blame_file(self.file_path)
    end
  end

  if not new_entries then
    vim.notify("Reblame failed: " .. (err or "Unknown error"), vim.log.levels.WARN, { title = "Blamer" })
    return false
  end

  self.blame_entries = new_entries
  self.blame_cache = {}
  for i, entry in ipairs(new_entries) do
    self.blame_cache[i] = entry
  end
  self.current_commit = commit
  self.commit_colors = {}
  self.next_color_index = 1
  self.last_highlighted_commit = nil

  self:update_view_buffer(commit)

  local lines, highlights = self:render_blame_lines()
  vim.bo[self.blame_buf].modifiable = true
  api.nvim_buf_set_lines(self.blame_buf, 0, -1, false, lines)
  vim.bo[self.blame_buf].modifiable = false
  self:apply_highlights(highlights)

  vim.defer_fn(function()
    if api.nvim_win_is_valid(self.blame_win) then
      pcall(api.nvim_win_set_cursor, self.blame_win, { math.min(line, #lines), 0 })
      self:update_hunk_highlight()
    end
  end, 10)

  -- Only add to history if it's different from the current entry
  local current_entry = self.history_stack[self.history_index]
  if not current_entry or current_entry.commit ~= commit then
    -- Trim history if we're not at the end
    if self.history_index < #self.history_stack then
      for i = #self.history_stack, self.history_index + 1, -1 do
        table.remove(self.history_stack, i)
      end
    end
    
    table.insert(self.history_stack, { commit = commit, line = line })
    self.history_index = #self.history_stack
  end

  return true
end

---Update view buffer content
---@param commit string|nil
function Blamer:update_view_buffer(commit)
  if not commit then
    if self.temp_buf and api.nvim_win_is_valid(self.view_win) then
      api.nvim_win_set_buf(self.view_win, self.view_buf)
    end
    return
  end

  if not self.temp_buf or not api.nvim_buf_is_valid(self.temp_buf) then
    self.temp_buf = api.nvim_create_buf(false, true)
    vim.bo[self.temp_buf].bufhidden = "wipe"
  end

  if api.nvim_win_is_valid(self.view_win) then
    api.nvim_win_set_buf(self.view_win, self.temp_buf)
  end

  local content, err = git.show_file(self.file_path, commit)
  if not content then
    content = { "Error: " .. (err or "Could not load file") }
  end

  vim.bo[self.temp_buf].modifiable = true
  api.nvim_buf_set_lines(self.temp_buf, 0, -1, false, content)
  vim.bo[self.temp_buf].modifiable = false
  vim.bo[self.temp_buf].filetype = vim.bo[self.view_buf].filetype
  
  -- Set buffer name to show commit and file path (use full commit SHA)
  local buf_name = string.format("%s:%s", commit, self.file_path)
  pcall(api.nvim_buf_set_name, self.temp_buf, buf_name)
end

---Navigate to parent commit
---@param line number
function Blamer:goto_parent(line)
  local entry = self.blame_entries[line]
  if not entry then
    return
  end

  if entry.commit:match("^0+$") then
    vim.notify("Cannot navigate to parent of uncommitted changes", vim.log.levels.INFO, { title = "Blamer" })
    return
  end

  local parent_commit = entry.commit .. "^"
  self:reblame(parent_commit, line)
end

---Go back in history
function Blamer:go_back()
  if self.history_index <= 1 then
    vim.notify("Already at beginning of history", vim.log.levels.INFO, { title = "Blamer" })
    return
  end

  self.history_index = self.history_index - 1
  local entry = self.history_stack[self.history_index]
  
  local new_entries, err
  if entry.commit then
    new_entries, err = git.blame_file(self.file_path, entry.commit)
  else
    -- Use buffer content only if buffer was originally modified
    if self.original_modified and api.nvim_buf_is_valid(self.view_buf) then
      local content = api.nvim_buf_get_lines(self.view_buf, 0, -1, false)
      new_entries, err = git.blame_buffer(self.file_path, content)
    else
      new_entries, err = git.blame_file(self.file_path)
    end
  end

  if new_entries then
    self.blame_entries = new_entries
    self.commit_colors = {}
    self.next_color_index = 1
    self:update_view_buffer(entry.commit)
    
    local lines, highlights = self:render_blame_lines()
    vim.bo[self.blame_buf].modifiable = true
    api.nvim_buf_set_lines(self.blame_buf, 0, -1, false, lines)
    vim.bo[self.blame_buf].modifiable = false
    self:apply_highlights(highlights)
    
    pcall(api.nvim_win_set_cursor, self.blame_win, { entry.line, 0 })
  end
end

---Go forward in history
function Blamer:go_forward()
  if self.history_index >= #self.history_stack then
    vim.notify("Already at end of history", vim.log.levels.INFO, { title = "Blamer" })
    return
  end

  self.history_index = self.history_index + 1
  local entry = self.history_stack[self.history_index]
  
  local new_entries, err
  if entry.commit then
    new_entries, err = git.blame_file(self.file_path, entry.commit)
  else
    -- Use buffer content only if buffer was originally modified
    if self.original_modified and api.nvim_buf_is_valid(self.view_buf) then
      local content = api.nvim_buf_get_lines(self.view_buf, 0, -1, false)
      new_entries, err = git.blame_buffer(self.file_path, content)
    else
      new_entries, err = git.blame_file(self.file_path)
    end
  end

  if new_entries then
    self.blame_entries = new_entries
    self.commit_colors = {}
    self.next_color_index = 1
    self:update_view_buffer(entry.commit)
    
    local lines, highlights = self:render_blame_lines()
    vim.bo[self.blame_buf].modifiable = true
    api.nvim_buf_set_lines(self.blame_buf, 0, -1, false, lines)
    vim.bo[self.blame_buf].modifiable = false
    self:apply_highlights(highlights)
    
    pcall(api.nvim_win_set_cursor, self.blame_win, { entry.line, 0 })
  end
end

---Get the visible line range in the view window
---@return number start_line, number end_line
function Blamer:get_visible_range()
  if not api.nvim_win_is_valid(self.view_win) then
    return 1, 100
  end
  
  local view_info = vim.fn.winsaveview()
  local height = api.nvim_win_get_height(self.view_win)
  local topline = view_info.topline
  local botline = topline + height
  
  -- Add some padding for smooth scrolling
  local padding = math.floor(height * 0.5)
  local start_line = math.max(1, topline - padding)
  local total_lines = api.nvim_buf_line_count(self.view_buf)
  local end_line = math.min(total_lines, botline + padding)
  
  return start_line, end_line
end

---Load blame for visible viewport with lazy expansion
---@return boolean success
function Blamer:load_visible_blame()
  local start_line, end_line = self:get_visible_range()
  
  -- Check if we need to load more
  local need_load = false
  for i = start_line, end_line do
    if not self.blame_cache[i] then
      need_load = true
      break
    end
  end
  
  if not need_load then
    return true  -- Already have everything we need
  end
  
  -- Find the actual range we need to load (expand to cover gaps)
  local load_start = start_line
  local load_end = end_line
  
  while load_start > 1 and not self.blame_cache[load_start] do
    load_start = load_start - 1
  end
  while load_end < api.nvim_buf_line_count(self.view_buf) and not self.blame_cache[load_end] do
    load_end = load_end + 1
  end
  
  local blame_entries, err
  
  if self.original_modified and api.nvim_buf_is_valid(self.view_buf) then
    -- For modified buffers, always load full blame once
    local content = api.nvim_buf_get_lines(self.view_buf, 0, -1, false)
    blame_entries, err = git.blame_buffer(self.file_path, content)
    if blame_entries then
      self.blame_entries = blame_entries
      for i, entry in ipairs(blame_entries) do
        self.blame_cache[i] = entry
      end
    end
  else
    -- Load just the visible range
    blame_entries, err = git.blame_file(self.file_path, self.current_commit, load_start, load_end)
    if blame_entries then
      -- Merge with existing entries
      for i, entry in ipairs(blame_entries) do
        local line_num = load_start + i - 1
        self.blame_cache[line_num] = entry
      end
      -- Rebuild full entries array from cache
      self.blame_entries = {}
      for i = 1, api.nvim_buf_line_count(self.view_buf) do
        if self.blame_cache[i] then
          self.blame_entries[i] = self.blame_cache[i]
        end
      end
    end
  end
  
  if not blame_entries then
    vim.notify("Git blame failed: " .. (err or "Unknown error"), vim.log.levels.ERROR, { title = "Blamer" })
    return false
  end
  
  return true
end

---Open the blame split
function Blamer:open()
  current_instance = self

  self.view_win = api.nvim_get_current_win()
  local initial_line = api.nvim_win_get_cursor(self.view_win)[1]

  -- Load only visible blame initially (fast!)
  if not self:load_visible_blame() then
    return
  end

  vim.cmd("vsplit")
  vim.cmd("wincmd H")
  
  self.blame_buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(0, self.blame_buf)
  self.blame_win = api.nvim_get_current_win()

  vim.bo[self.blame_buf].buftype = "nofile"
  vim.bo[self.blame_buf].bufhidden = "wipe"
  vim.bo[self.blame_buf].swapfile = false
  vim.bo[self.blame_buf].filetype = "blamer"
  
  -- Set buffer name with unique identifier
  local buf_name = string.format("Blamer:%s", self.file_path)
  pcall(api.nvim_buf_set_name, self.blame_buf, buf_name)

  api.nvim_win_set_width(self.blame_win, self.width)
  vim.wo[self.blame_win].number = false
  vim.wo[self.blame_win].relativenumber = false
  vim.wo[self.blame_win].wrap = false
  vim.wo[self.blame_win].list = false  -- Don't show trailing spaces
  vim.wo[self.view_win].wrap = false

  local lines, highlights = self:render_blame_lines()
  api.nvim_buf_set_lines(self.blame_buf, 0, -1, false, lines)
  vim.bo[self.blame_buf].modifiable = false
  self:apply_highlights(highlights)

  self:setup_keymaps()
  self:setup_scroll_sync()

  table.insert(self.history_stack, { commit = nil, line = initial_line })
  self.history_index = 1

  vim.defer_fn(function()
    if api.nvim_win_is_valid(self.blame_win) then
      pcall(api.nvim_win_set_cursor, self.blame_win, { initial_line, 0 })
      self:update_hunk_highlight()
    end
  end, 10)
end

---Setup keymaps
function Blamer:setup_keymaps()
  local opts = { buffer = self.blame_buf, silent = true }

  vim.keymap.set("n", "q", function() self:close() end, opts)
  vim.keymap.set("n", "<Esc>", function() self:close() end, opts)
  
  vim.keymap.set("n", "r", function()
    local line = api.nvim_win_get_cursor(self.blame_win)[1]
    local entry = self.blame_entries[line]
    if entry and not entry.commit:match("^0+$") then
      self:reblame(entry.commit, line)
    end
  end, opts)

  vim.keymap.set("n", "p", function()
    local line = api.nvim_win_get_cursor(self.blame_win)[1]
    self:goto_parent(line)
  end, opts)

  vim.keymap.set("n", "[", function() self:go_back() end, opts)
  vim.keymap.set("n", "]", function() self:go_forward() end, opts)
  vim.keymap.set("n", "<C-o>", function() self:go_back() end, opts)
  vim.keymap.set("n", "<C-i>", function() self:go_forward() end, opts)
  
  -- Show commit details
  vim.keymap.set("n", "s", function()
    local line = api.nvim_win_get_cursor(self.blame_win)[1]
    local entry = self.blame_entries[line]
    if entry and not entry.commit:match("^0+$") then
      local buf, win, full_commit = commit.create_commit_view(entry.commit)
      if buf and win then
        -- Add diff keymap to commit view
        vim.keymap.set("n", "d", function()
          if api.nvim_win_is_valid(win) then
            api.nvim_win_close(win, true)
          end
          diff.open_diff(full_commit, self.file_path)
        end, { buffer = buf, silent = true })
      end
    else
      vim.notify("Cannot show commit for uncommitted changes", vim.log.levels.INFO, { title = "Blamer" })
    end
  end, opts)
  
  -- Show diff
  vim.keymap.set("n", "d", function()
    local line = api.nvim_win_get_cursor(self.blame_win)[1]
    local entry = self.blame_entries[line]
    if entry and not entry.commit:match("^0+$") then
      diff.open_diff(entry.commit, self.file_path)
    else
      vim.notify("Cannot show diff for uncommitted changes", vim.log.levels.INFO, { title = "Blamer" })
    end
  end, opts)
end

---Close the blame split
function Blamer:close()
  -- Clean up autocmds
  if self.augroup then
    pcall(api.nvim_del_augroup_by_id, self.augroup)
    self.augroup = nil
  end
  
  -- First, restore the original buffer in the view window if we're viewing a temp buffer
  if api.nvim_win_is_valid(self.view_win) then
    local current_buf = api.nvim_win_get_buf(self.view_win)
    if current_buf ~= self.view_buf and api.nvim_buf_is_valid(self.view_buf) then
      api.nvim_win_set_buf(self.view_win, self.view_buf)
    end
    
    -- Switch to the view window before closing the blame window
    api.nvim_set_current_win(self.view_win)
  end

  -- Clean up temp buffer
  if self.temp_buf and api.nvim_buf_is_valid(self.temp_buf) then
    pcall(api.nvim_buf_delete, self.temp_buf, { force = true })
  end

  -- Close the blame window (use pcall in case it's the last window or already closed)
  if api.nvim_win_is_valid(self.blame_win) then
    pcall(api.nvim_win_close, self.blame_win, true)
  end

  current_instance = nil
end

---Check if blamer is open
---@return boolean
local function is_open()
  return current_instance ~= nil
end

---Toggle blamer
local function toggle()
  if is_open() then
    current_instance:close()
  else
    local blamer = Blamer.new()
    if blamer then
      blamer:open()
    end
  end
end

---Show cache statistics
local function cache_stats()
  local stats = cache.stats()
  vim.notify(
    string.format(
      "Blame Cache: %d/%d entries\nFile Cache: %d/%d entries",
      stats.blame_entries,
      stats.blame_max,
      stats.file_entries,
      stats.file_max
    ),
    vim.log.levels.INFO,
    { title = "Blamer Cache" }
  )
end

---Clear cache
local function cache_clear()
  cache.clear()
  vim.notify("Cache cleared", vim.log.levels.INFO, { title = "Blamer" })
end

---Setup the plugin
local function setup()
  ui.setup_highlights()
  
  -- Clear cache for file when it's written
  vim.api.nvim_create_autocmd("BufWritePost", {
    callback = function(args)
      local git_root = git.get_git_root()
      if not git_root then
        return
      end
      
      local file_path = vim.fn.expand("%:p")
      if file_path:find(git_root, 1, true) == 1 then
        file_path = file_path:sub(#git_root + 2)
        cache.clear_file(file_path)
      end
    end,
  })
  
  vim.api.nvim_create_user_command("Blamer", toggle, {})
  vim.api.nvim_create_user_command("BlamerToggle", toggle, {})
  vim.api.nvim_create_user_command("BlamerCacheStats", cache_stats, {})
  vim.api.nvim_create_user_command("BlamerCacheClear", cache_clear, {})
end

return {
  setup = setup,
  toggle = toggle,
  is_open = is_open,
  cache_stats = cache_stats,
  cache_clear = cache_clear,
}
