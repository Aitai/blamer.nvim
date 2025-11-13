# Blamer

A focused Neovim plugin for git blame functionality, extracted from Neogit's blame split feature.

## Features

- **Split view blame**: Side-by-side blame information and file content
- **Color-coded commits**: Visual distinction between different commits
- **Interactive navigation**:
  - Navigate through commit history
  - Jump to parent commits
  - Browse historical file versions
- **Synchronized scrolling**: Blame panel and file view stay in sync
- **History navigation**: Back/forward through your blame exploration
- **Uncommitted changes support**: Blame works with unsaved buffer modifications

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "blamer",
  dev = true,
  config = function()
    require("blamer").setup()
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  '/path/to/blamer',
  config = function()
    require("blamer").setup()
  end
}
```

## Usage

### Commands

- `:Blamer` or `:BlamerToggle` - Toggle the blame split view

### Default Keymaps (in blame buffer)

- `q` or `<Esc>` - Close blame view
- `r` - Re-blame at the commit under cursor (view that commit's state)
- `p` - Navigate to parent commit
- `s` - Show commit details in a popup
- `d` - View diff for the commit (uses diffview if installed, otherwise native diff)
- `[` or `<C-o>` - Go back in navigation history
- `]` or `<C-i>` - Go forward in navigation history

## How it Works

Blamer uses `git blame --porcelain` to retrieve detailed blame information for each line of a file. It then:

1. Groups consecutive lines with the same commit into "hunks"
2. Displays commit hash, author, date, and message for each hunk
3. Color-codes different commits for easy visual scanning
4. Highlights the hunk under the cursor in bold
5. Synchronizes scrolling between blame panel and file view

## Comparison with Neogit

This plugin extracts only the blame functionality from Neogit, making it:

- **Lighter**: No dependencies on Neogit's infrastructure
- **Focused**: Only git blame, no status, commit, or other git operations
- **Standalone**: Works independently without requiring Neogit
- **Simpler**: Easier to understand and modify for your needs

## Credits

Based on the excellent blame implementation in [Neogit](https://github.com/NeogitOrg/neogit).
