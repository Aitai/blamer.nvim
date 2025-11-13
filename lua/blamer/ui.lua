-- UI rendering helpers
local M = {}

local COMMIT_COLORS = {
  "BlamerCommit1",
  "BlamerCommit2",
  "BlamerCommit3",
  "BlamerCommit4",
  "BlamerCommit5",
  "BlamerCommit6",
  "BlamerCommit7",
  "BlamerCommit8",
  "BlamerCommit9",
  "BlamerCommit10",
  "BlamerCommit11",
  "BlamerCommit12",
  "BlamerCommit13",
  "BlamerCommit14",
  "BlamerCommit15",
  "BlamerCommit16",
}

local COMMIT_COLORS_BOLD = {
  "BlamerCommit1Bold",
  "BlamerCommit2Bold",
  "BlamerCommit3Bold",
  "BlamerCommit4Bold",
  "BlamerCommit5Bold",
  "BlamerCommit6Bold",
  "BlamerCommit7Bold",
  "BlamerCommit8Bold",
  "BlamerCommit9Bold",
  "BlamerCommit10Bold",
  "BlamerCommit11Bold",
  "BlamerCommit12Bold",
  "BlamerCommit13Bold",
  "BlamerCommit14Bold",
  "BlamerCommit15Bold",
  "BlamerCommit16Bold",
}

---Setup highlight groups
function M.setup_highlights()
  -- Base colors - using a bright color scheme
  local colors = {
    { name = "BlamerCommit1", fg = "#7aa2f7" },  -- blue
    { name = "BlamerCommit2", fg = "#bb9af7" },  -- purple
    { name = "BlamerCommit3", fg = "#9ece6a" },  -- green
    { name = "BlamerCommit4", fg = "#f7768e" },  -- red
    { name = "BlamerCommit5", fg = "#e0af68" },  -- yellow
    { name = "BlamerCommit6", fg = "#7dcfff" },  -- cyan
    { name = "BlamerCommit7", fg = "#ff9e64" },  -- orange
    { name = "BlamerCommit8", fg = "#1abc9c" },  -- teal
    { name = "BlamerCommit9", fg = "#ff007c" },  -- magenta
    { name = "BlamerCommit10", fg = "#73daca" }, -- lime
    { name = "BlamerCommit11", fg = "#db4b4b" }, -- coral
    { name = "BlamerCommit12", fg = "#89ddff" }, -- azure
    { name = "BlamerCommit13", fg = "#fca7ea" }, -- rose
    { name = "BlamerCommit14", fg = "#0db9d7" }, -- mint
    { name = "BlamerCommit15", fg = "#ffc777" }, -- amber
    { name = "BlamerCommit16", fg = "#c0caf5" }, -- light blue
  }

  for _, color in ipairs(colors) do
    vim.api.nvim_set_hl(0, color.name, { fg = color.fg })
    vim.api.nvim_set_hl(0, color.name .. "Bold", { fg = color.fg, bold = true })
  end

  vim.api.nvim_set_hl(0, "BlamerDate", { fg = "#9999ff" })
  vim.api.nvim_set_hl(0, "BlamerMessage", { fg = "#555555", italic = true })
  vim.api.nvim_set_hl(0, "BlamerMessageBold", { fg = "#555555", italic = true, bold = true })
end

---Get color index for commit
---@param commit_colors table
---@param next_color_index number
---@param commit string
---@return number, number new_next_color_index
function M.get_commit_color_index(commit_colors, next_color_index, commit)
  if not commit_colors[commit] then
    local color_index = ((next_color_index - 1) % #COMMIT_COLORS) + 1
    commit_colors[commit] = color_index
    return color_index, next_color_index + 1
  end
  return commit_colors[commit], next_color_index
end

---Get color name for commit
---@param commit_colors table
---@param commit string
---@param bold boolean
---@return string
function M.get_commit_color(commit_colors, commit, bold)
  local colors = bold and COMMIT_COLORS_BOLD or COMMIT_COLORS
  return colors[commit_colors[commit]]
end

---Group blame entries into hunks
---@param entries BlameEntry[]
---@return table[] hunks
function M.get_hunks(entries)
  local hunks = {}
  if #entries == 0 then
    return hunks
  end

  local current_hunk = {
    commit = entries[1].commit,
    author = entries[1].author,
    author_time = entries[1].author_time,
    summary = entries[1].summary,
    line_count = 0,
  }

  for _, entry in ipairs(entries) do
    if entry.commit ~= current_hunk.commit or entry.author ~= current_hunk.author or entry.summary ~= current_hunk.summary then
      table.insert(hunks, current_hunk)
      current_hunk = {
        commit = entry.commit,
        author = entry.author,
        author_time = entry.author_time,
        summary = entry.summary,
        line_count = 1,
      }
    else
      current_hunk.line_count = current_hunk.line_count + 1
    end
  end
  table.insert(hunks, current_hunk)

  return hunks
end

---Truncate string to fit width
---@param str string
---@param max_width number
---@return string
function M.truncate(str, max_width)
  local width = vim.fn.strdisplaywidth(str)
  if width > max_width then
    return vim.fn.strcharpart(str, 0, math.max(0, max_width - 3)) .. "..."
  end
  return str
end

return M
