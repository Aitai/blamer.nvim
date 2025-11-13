# Blamer

A focused Neovim plugin for git blame functionality with split view and interactive commit navigation.

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
- **Smart caching**: Instant reopening and navigation with intelligent LRU cache

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
"Aitai/blamer.nvim"
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use 'Aitai/blamer.nvim'
```

## Usage

### Commands

- `:Blamer` - Toggle the blame split view
- `:BlamerToggle` - Toggle the blame split view
- `:BlamerCacheStats` - Show cache statistics
- `:BlamerCacheClear` - Clear all cached data

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

### Caching

Blamer implements an intelligent LRU (Least Recently Used) cache that stores:
- Git blame results for files at different commits
- File contents at specific commits

This makes:
- **Reopening blame views instant** - No need to re-run git blame
- **History navigation (C-o/C-i) instant** - Previously visited states load instantly
- **Re-blaming at commits instant** - Once loaded, commit views are cached

The cache automatically manages memory by evicting least recently used entries (default: 50 blame results, 100 file contents).
