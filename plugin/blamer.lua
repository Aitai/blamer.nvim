-- Blamer plugin entry point
if vim.g.loaded_blamer then
  return
end
vim.g.loaded_blamer = 1

-- Auto-setup on load
require("blamer").setup()
