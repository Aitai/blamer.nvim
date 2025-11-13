-- Cache module for git blame and file content
local M = {}

-- Cache structure:
-- blame_cache = {
--   ["file_path:commit_or_nil"] = BlameEntry[]
-- }
-- file_cache = {
--   ["file_path:commit"] = string[]
-- }

local blame_cache = {}
local file_cache = {}

-- Maximum cache size (number of entries)
local MAX_BLAME_CACHE = 50
local MAX_FILE_CACHE = 100

-- LRU tracking
local blame_access_order = {}
local file_access_order = {}

---Generate cache key for blame
---@param file_path string
---@param commit string|nil
---@return string
local function blame_key(file_path, commit)
  return file_path .. ":" .. (commit or "HEAD")
end

---Generate cache key for file content
---@param file_path string
---@param commit string
---@return string
local function file_key(file_path, commit)
  return file_path .. ":" .. commit
end

---Update LRU access order
---@param access_order table
---@param key string
local function touch_lru(access_order, key)
  -- Remove key if it exists
  for i, k in ipairs(access_order) do
    if k == key then
      table.remove(access_order, i)
      break
    end
  end
  -- Add to end (most recently used)
  table.insert(access_order, key)
end

---Evict oldest entry if cache is full
---@param cache table
---@param access_order table
---@param max_size number
local function evict_if_needed(cache, access_order, max_size)
  while #access_order > max_size do
    local oldest = table.remove(access_order, 1)
    cache[oldest] = nil
  end
end

---Get cached blame entries
---@param file_path string
---@param commit string|nil
---@return BlameEntry[]|nil
function M.get_blame(file_path, commit)
  local key = blame_key(file_path, commit)
  local entries = blame_cache[key]
  if entries then
    touch_lru(blame_access_order, key)
    return entries
  end
  return nil
end

---Cache blame entries
---@param file_path string
---@param commit string|nil
---@param entries BlameEntry[]
function M.set_blame(file_path, commit, entries)
  local key = blame_key(file_path, commit)
  blame_cache[key] = entries
  touch_lru(blame_access_order, key)
  evict_if_needed(blame_cache, blame_access_order, MAX_BLAME_CACHE)
end

---Get cached file content
---@param file_path string
---@param commit string
---@return string[]|nil
function M.get_file(file_path, commit)
  local key = file_key(file_path, commit)
  local content = file_cache[key]
  if content then
    touch_lru(file_access_order, key)
    return content
  end
  return nil
end

---Cache file content
---@param file_path string
---@param commit string
---@param content string[]
function M.set_file(file_path, commit, content)
  local key = file_key(file_path, commit)
  file_cache[key] = content
  touch_lru(file_access_order, key)
  evict_if_needed(file_cache, file_access_order, MAX_FILE_CACHE)
end

---Clear all caches
function M.clear()
  blame_cache = {}
  file_cache = {}
  blame_access_order = {}
  file_access_order = {}
end

---Clear cache for specific file
---@param file_path string
function M.clear_file(file_path)
  -- Clear blame cache entries for this file
  for key, _ in pairs(blame_cache) do
    if key:match("^" .. vim.pesc(file_path) .. ":") then
      blame_cache[key] = nil
      for i, k in ipairs(blame_access_order) do
        if k == key then
          table.remove(blame_access_order, i)
          break
        end
      end
    end
  end
  
  -- Clear file cache entries for this file
  for key, _ in pairs(file_cache) do
    if key:match("^" .. vim.pesc(file_path) .. ":") then
      file_cache[key] = nil
      for i, k in ipairs(file_access_order) do
        if k == key then
          table.remove(file_access_order, i)
          break
        end
      end
    end
  end
end

---Get cache statistics
---@return table stats
function M.stats()
  return {
    blame_entries = vim.tbl_count(blame_cache),
    file_entries = vim.tbl_count(file_cache),
    blame_max = MAX_BLAME_CACHE,
    file_max = MAX_FILE_CACHE,
  }
end

return M
