# Blamer Quick Start Guide

## Installation

Since the plugin is already in your lazy.nvim directory, you can use it immediately by adding it to your Neovim configuration.

### Option 1: Add to your lazy.nvim config

Add this to your `~/.config/nvim/lua/plugins/blamer.lua` (or wherever you define plugins):

```lua
return {
  {
    dir = vim.fn.stdpath("data") .. "/nvim/lazy/blamer",
    name = "blamer",
    config = function()
      require("blamer").setup()
      -- Optional: add a keybinding
      vim.keymap.set("n", "<leader>gb", "<cmd>Blamer<cr>", { desc = "Git blame" })
    end,
  }
}
```

### Option 2: Test without installation

```vim
:set rtp+=~/.local/share/nvim/lazy/blamer
:lua require("blamer").setup()
:Blamer
```

## Basic Usage

1. **Open a git-tracked file** in Neovim
2. **Run** `:Blamer` or press your keybinding (e.g., `<leader>gb`)
3. **Navigate** the blame view:
   - Cursor moves in both panels simultaneously
   - The current commit is highlighted in bold

## Interactive Navigation

Once in the blame view:

| Key | Action |
|-----|--------|
| `q` or `<Esc>` | Close blame view |
| `r` | Re-blame at the commit under cursor (time travel!) |
| `p` | Jump to parent commit of current line |
| `s` | Show commit details in a popup |
| `d` | View diff for the commit (diffview or native) |
| `[` or `<C-o>` | Go back in navigation history |
| `]` or `<C-i>` | Go forward in navigation history |

## Example Workflow

```
1. Open a file: nvim src/main.lua
2. Toggle blame: :Blamer
3. Navigate to an interesting commit (move cursor up/down)
4. Press 'r' to see the file as it was in that commit
5. Press 'p' to see the parent commit (what came before?)
6. Press '[' to go back to the previous view
7. Press 'q' to close
```

## Visual Guide

```
┌──────────────────────────────────┬─────────────────────────────┐
│ Blame Panel (60 chars wide)     │ File Content                │
├──────────────────────────────────┼─────────────────────────────┤
│ ┍ 1a2b3c4d Alice Add feature     │ function main()             │
│ │ Add new feature X         2024 │   local x = init()          │
│ ┕                                 │   return x                  │
│ - 5e6f7g8h Bob Fix bug       2024│ end                         │
│ ┍ 9i0j1k2l Charlie Refactor  2024│                             │
│ │ Improve performance             │ function init()             │
│ ┕                                 │   return {}                 │
└──────────────────────────────────┴─────────────────────────────┘
```

## Troubleshooting

### "Not in a git repository"
- Make sure you're in a directory that's tracked by git
- Run `git status` to verify

### "No blame information found"
- The file might be new and not committed yet
- Try committing the file first

### Colors don't look good
- The plugin uses a default color scheme
- Colors are defined in `lua/blamer/ui.lua` (you can customize them)

## Next Steps

- Read `:help blamer` for full documentation
- Check `FEATURES.md` for detailed feature comparison with Neogit
- Look at `examples/init.lua` for advanced configuration options
