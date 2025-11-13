-- Example configuration for blamer plugin

-- Basic setup
require("blamer").setup()

-- Optional: Add a keybinding to toggle blame
vim.keymap.set("n", "<leader>gb", "<cmd>Blamer<cr>", { 
  desc = "Toggle git blame", 
  silent = true 
})

-- Or use the function directly
vim.keymap.set("n", "<leader>gB", function()
  require("blamer").toggle()
end, { 
  desc = "Toggle git blame (function)", 
  silent = true 
})

-- Using lazy.nvim plugin manager
-- Add this to your lazy.nvim configuration:
--[[
{
  dir = "/path/to/blamer",  -- or use dev = true if in your dev directory
  name = "blamer",
  config = function()
    require("blamer").setup()
    vim.keymap.set("n", "<leader>gb", "<cmd>Blamer<cr>", { desc = "Toggle git blame" })
  end,
  -- Optional: lazy load on command
  cmd = { "Blamer", "BlamerToggle" },
}
]]
