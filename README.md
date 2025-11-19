# blamer.nvim

A robust, feature-rich git blame plugin for Neovim inspired by the need for better code history exploration. It provides a side-by-side split view with intuitive navigation through commit history.

<img width="1987" height="1279" alt="image" src="https://github.com/user-attachments/assets/dd2db5dd-2755-47f9-a51e-1d05f600a423" />

## Features

### Blame Explorer
- **Split View Interface**: Opens a vertical split showing blame information aligned with your file.
- **Commit Info**: Displays author and date (YYYY-MM-DD) clearly.
- **Smart Wrapping**: Automatically wraps long commit messages across multiple lines so you don't miss context.
- **Active Hunk Highlighting**: Automatically bolds the commit information in the blame panel that corresponds to your current cursor position.

### Navigation & History
- **Time Travel**: Navigate backward and forward through the file's history using `[` / `]` or standard jump bindings `<C-o>` / `<C-i>`.
- **Reblame**: Press `r` to view the file state exactly as it was at the commit under your cursor.
- **Commit Drill-down**: Press `s` to view the full commit details in a separate tab.
- **Parent Navigation**: Press `p` to instantly blame the parent of the current commit (go back one step in time).
- **Diff Integration**: Press `d` to view the diff of a specific commit (integrates with `diffview.nvim` if installed, falls back to native diff).

### Performance & Caching
- **Asynchronous Loading**: Blame data is pre-loaded in the background to ensure instant opening.
- **Rename Tracking**: Intelligent git history traversal that follows files even after they have been renamed or moved.
- **LRU Caching**: Implements a Least Recently Used cache to keep memory usage low while ensuring instant access to previously viewed commits.
- **Smart Invalidation**: Automatically detects when you modify a file, switch branches, or perform git operations, keeping the blame view accurate.

### UX & Polish
- **Synced Scrolling**: The blame view and your code buffer scroll in perfect lock-step.
- **Auto-Resizing**: The blame window adjusts automatically to fit content.
- **Color Coding**: Commits are color-coded by hash, making it easy to visually distinguish changes.

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

| Command | Description |
|---------|-------------|
| `:BlamerToggle` | Open/Close the blame split view |
| `:BlamerCacheStats` | View current cache usage statistics |
| `:BlamerCacheClear` | Manually flush the internal cache |

### Keymaps (Inside Blamer Buffer)

| Key | Action |
|-----|--------|
| `q` / `<Esc>` | Close the blame view |
| `[` / `<C-o>` | **Go Back**: View file state at previous point in navigation history |
| `]` / `<C-i>` | **Go Forward**: View file state at next point in navigation history |
| `r` | **Reblame**: Reload blame at the specific commit under cursor |
| `p` | **Parent**: Blame the parent commit of the line under cursor |
| `s` | **Show**: Open full commit details in a new tab |
| `d` | **Diff**: Open diff for the commit under cursor |

## How it Works

Blamer uses `git blame --porcelain` to retrieve detailed blame information. It groups consecutive lines belonging to the same commit into "hunks" and caches the results to ensure instant reopening.

The plugin also employs an intelligent LRU (Least Recently Used) cache. This means history navigation and re-opening files is near-instant, but memory usage remains low. It automatically invalidates this cache if it detects file changes, branch switches, or external git operations.
