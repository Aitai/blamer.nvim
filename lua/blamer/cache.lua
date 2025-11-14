-- Cache module for git blame and file content
local M = {}

local MAX_BLAME_CACHE = 50
local MAX_FILE_CACHE = 100

---Create an O(1) LRU cache using doubly-linked list
---@param max_size number
---@return table
local function create_lru_cache(max_size)
  local cache = {}
  local head = { next = nil, prev = nil }
  local tail = { next = nil, prev = head }
  head.next = tail
  local size = 0

  local lru = {}

  ---Remove a node from its current position (O(1))
  local function remove_node(node)
    node.prev.next = node.next
    node.next.prev = node.prev
  end

  ---Add a node to the front (most recent) (O(1))
  local function add_to_front(node)
    node.next = head.next
    node.prev = head
    head.next.prev = node
    head.next = node
  end

  function lru.get(key)
    local node = cache[key]
    if node then
      remove_node(node)
      add_to_front(node)
      return node.value
    end
    return nil
  end

  function lru.set(key, value)
    local node = cache[key]
    if node then
      node.value = value
      remove_node(node)
      add_to_front(node)
    else
      node = { key = key, value = value }
      cache[key] = node
      add_to_front(node)
      size = size + 1
    end

    if size > max_size then
      local oldest = tail.prev
      if oldest ~= head then
        remove_node(oldest)
        cache[oldest.key] = nil
        size = size - 1
      end
    end
  end

  function lru.clear()
    cache = {}
    head.next = tail
    tail.prev = head
    size = 0
  end

  function lru.clear_pattern(pattern)
    local node = head.next
    while node ~= tail do
      local next_node = node.next
      if node.key and node.key:match(pattern) then
        remove_node(node)
        cache[node.key] = nil
        size = size - 1
      end
      node = next_node
    end
  end

  function lru.count()
    return size
  end

  return lru
end

local blame_cache = create_lru_cache(MAX_BLAME_CACHE)
local file_cache = create_lru_cache(MAX_FILE_CACHE)

---Get cached blame entries
---@param file_path string
---@param commit string|nil
---@param mtime number|nil File modification time to validate cache freshness
---@return BlameEntry[]|nil
function M.get_blame(file_path, commit, mtime)
  local key = file_path .. ":" .. (commit or "HEAD")
  local cached = blame_cache.get(key)

  -- If we have mtime and this is for HEAD (current file), validate cache freshness
  if cached and mtime and (commit == nil or commit == "HEAD") then
    if not cached.mtime or cached.mtime < mtime then
      -- File was modified after cache was created, invalidate it
      blame_cache.set(key, nil)
      return nil
    end
  end

  return cached and cached.data or cached
end

---Cache blame entries
---@param file_path string
---@param commit string|nil
---@param entries BlameEntry[]
---@param mtime number|nil File modification time for cache validation
function M.set_blame(file_path, commit, entries, mtime)
  local key = file_path .. ":" .. (commit or "HEAD")
  -- Store with mtime for HEAD entries to enable cache invalidation
  if mtime and (commit == nil or commit == "HEAD") then
    blame_cache.set(key, { data = entries, mtime = mtime })
  else
    blame_cache.set(key, entries)
  end
end

---Get cached file content
---@param file_path string
---@param commit string
---@return string[]|nil
function M.get_file(file_path, commit)
  local key = file_path .. ":" .. commit
  return file_cache.get(key)
end

---Cache file content
---@param file_path string
---@param commit string
---@param content string[]
function M.set_file(file_path, commit, content)
  local key = file_path .. ":" .. commit
  file_cache.set(key, content)
end

---Clear all caches
function M.clear()
  blame_cache.clear()
  file_cache.clear()
end

---Clear cache for specific file
---@param file_path string
function M.clear_file(file_path)
  local pattern = "^" .. vim.pesc(file_path) .. ":"
  blame_cache.clear_pattern(pattern)
  file_cache.clear_pattern(pattern)
end

---Get cache statistics
---@return table stats
function M.stats()
  return {
    blame_entries = blame_cache.count(),
    file_entries = file_cache.count(),
    blame_max = MAX_BLAME_CACHE,
    file_max = MAX_FILE_CACHE,
  }
end

return M
