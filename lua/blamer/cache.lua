-- Cache module for git blame and file content
local M = {}

local blame_cache = {}
local file_cache = {}

local MAX_BLAME_CACHE = 50
local MAX_FILE_CACHE = 100

-- LRU tracking with lookup table for O(1) removal
local blame_access_order = {}
local blame_lru_lookup = {}
local file_access_order = {}
local file_lru_lookup = {}

---Update LRU access order
---@param access_order table
---@param lookup table
---@param key string
local function touch_lru(access_order, lookup, key)
  local idx = lookup[key]
  if idx then
    table.remove(access_order, idx)
    -- Update indices for all elements after the removed one
    for i = idx, #access_order do
      lookup[access_order[i]] = i
    end
  end
  table.insert(access_order, key)
  lookup[key] = #access_order
end

---Evict oldest entry if cache is full
---@param cache table
---@param access_order table
---@param lookup table
---@param max_size number
local function evict_if_needed(cache, access_order, lookup, max_size)
  while #access_order > max_size do
    local oldest = table.remove(access_order, 1)
    cache[oldest] = nil
    lookup[oldest] = nil
    -- Update indices after removal
    for i = 1, #access_order do
      lookup[access_order[i]] = i
    end
  end
end

---Get cached blame entries
---@param file_path string
---@param commit string|nil
---@return BlameEntry[]|nil
function M.get_blame(file_path, commit)
  local key = file_path .. ":" .. (commit or "HEAD")
  local entries = blame_cache[key]
  if entries then
    touch_lru(blame_access_order, blame_lru_lookup, key)
    return entries
  end
  return nil
end

---Cache blame entries
---@param file_path string
---@param commit string|nil
---@param entries BlameEntry[]
function M.set_blame(file_path, commit, entries)
  local key = file_path .. ":" .. (commit or "HEAD")
  blame_cache[key] = entries
  touch_lru(blame_access_order, blame_lru_lookup, key)
  evict_if_needed(blame_cache, blame_access_order, blame_lru_lookup, MAX_BLAME_CACHE)
end

---Get cached file content
---@param file_path string
---@param commit string
---@return string[]|nil
function M.get_file(file_path, commit)
  local key = file_path .. ":" .. commit
  local content = file_cache[key]
  if content then
    touch_lru(file_access_order, file_lru_lookup, key)
    return content
  end
  return nil
end

---Cache file content
---@param file_path string
---@param commit string
---@param content string[]
function M.set_file(file_path, commit, content)
  local key = file_path .. ":" .. commit
  file_cache[key] = content
  touch_lru(file_access_order, file_lru_lookup, key)
  evict_if_needed(file_cache, file_access_order, file_lru_lookup, MAX_FILE_CACHE)
end

---Clear all caches
function M.clear()
  blame_cache = {}
  file_cache = {}
  blame_access_order = {}
  blame_lru_lookup = {}
  file_access_order = {}
  file_lru_lookup = {}
end

---Clear cache for specific file
---@param file_path string
function M.clear_file(file_path)
  local pattern = "^" .. vim.pesc(file_path) .. ":"
  
  -- Single pass: clear caches and rebuild access orders
  local new_blame_order = {}
  for _, k in ipairs(blame_access_order) do
    if k:match(pattern) then
      blame_cache[k] = nil
      blame_lru_lookup[k] = nil
    else
      table.insert(new_blame_order, k)
      blame_lru_lookup[k] = #new_blame_order
    end
  end
  blame_access_order = new_blame_order
  
  local new_file_order = {}
  for _, k in ipairs(file_access_order) do
    if k:match(pattern) then
      file_cache[k] = nil
      file_lru_lookup[k] = nil
    else
      table.insert(new_file_order, k)
      file_lru_lookup[k] = #new_file_order
    end
  end
  file_access_order = new_file_order
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
