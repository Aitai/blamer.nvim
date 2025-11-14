# Blamer

A focused Neovim plugin for git blame functionality with split view and interactive commit navigation.

## Features

- **Split view blame**: Side-by-side blame information and file content
- **Multi-line commit messages**: Long commit messages wrap across multiple lines for better readability
- **Resizable split**: Dynamically resize the blame panel to see more commit details
- **Color-coded commits**: Visual distinction between different commits
- **Interactive navigation**:
  - Navigate through commit history
  - Jump to parent commits
  - Browse historical file versions
- **Synchronized scrolling**: Blame panel and file view stay in sync
- **History navigation**: Back/forward through your blame exploration
- **Uncommitted changes support**: Blame works with unsaved buffer modifications
- **Smart caching**: Instant reopening and navigation with intelligent LRU cache
- **Automatic cache invalidation**: Detects external file changes (git operations, external edits) and refreshes blame automatically

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

#### Automatic Cache Invalidation

Blamer automatically detects when files are modified outside of Neovim and invalidates stale cache entries:

- **File modification tracking**: Uses file modification time (mtime) to detect changes
- **Git operation detection**: Automatically refreshes after `git checkout`, `git pull`, `git rebase`, etc.
- **External editor changes**: Detects modifications made by other editors or tools
- **Smart validation**: Only checks current file (HEAD), historical commits remain cached
- **Seamless experience**: No manual cache clearing needed, works transparently

When you switch branches, pull changes, or modify files externally, Blamer automatically detects the changes and fetches fresh blame data on the next access. This ensures you always see accurate, up-to-date blame information without manual intervention.
