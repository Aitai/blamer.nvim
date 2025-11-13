# Blamer - Extracted Features from Neogit

## What Was Extracted from NeogitBlameSplit

### Core Blame Functionality
- **Git blame parsing**: Full porcelain format parser for detailed blame information
- **Uncommitted changes support**: Ability to blame files with unsaved modifications
- **Historical blame**: Re-blame at any commit in the file's history

### UI Features
- **Split view layout**: Side-by-side blame panel and file content
- **Color-coded commits**: 8 rotating colors to distinguish different commits
- **Hunk grouping**: Consecutive lines from the same commit are grouped together
- **Visual styling**: 
  - Single-line hunks: `- commit author message    date`
  - Multi-line hunks with box-drawing characters (┍ │ ┕)
- **Dynamic highlighting**: Current hunk highlighted in bold

### Interactive Navigation
- **Commit history navigation**: Back/forward through your blame exploration path
- **Parent commit navigation**: Jump to the parent commit of any line
- **Re-blame at commit**: View the file state at any historical commit
- **Synchronized scrolling**: Blame and file views scroll together
- **Cursor synchronization**: Moving cursor in one view updates the other

### Key Mappings
- `q`, `<Esc>` - Close blame view
- `r` - Re-blame at commit under cursor
- `p` - Navigate to parent commit
- `s` - Show commit details
- `d` - View diff for commit
- `[`, `<C-o>` - Go back in history
- `]`, `<C-i>` - Go forward in history

## Simplified from Neogit

### Removed Dependencies
- ✗ Neogit's Buffer class → Simple native Neovim buffers
- ✗ Neogit's UI framework → Direct buffer manipulation
- ✗ Neogit's CLI wrapper → Direct git command execution via jobstart
- ✗ Neogit's process management → Simple synchronous git calls
- ✗ Integration with Neogit status/commit buffers

### Simplified Features
- No hard dependencies (diffview is optional)
- Direct vim.fn.jobstart for git commands
- Simplified buffer management
- Focused purely on blame functionality
- Commit viewing in floating window
- Diff viewing with diffview integration (fallback to native diff)

## Architecture

```
blamer/
├── lua/blamer/
│   ├── init.lua      # Main module with Blamer class
│   ├── git.lua       # Git command execution and parsing
│   └── ui.lua        # UI helpers (colors, hunks, rendering)
├── plugin/
│   └── blamer.lua    # Plugin entry point
├── doc/
│   └── blamer.txt    # Vim help documentation
└── examples/
    └── init.lua      # Configuration examples
```

## Line Count Comparison

- Original Neogit blame_split/init.lua: ~1069 lines
- Original Neogit lib/git/blame.lua: ~228 lines
- **Total Neogit blame code**: ~1297 lines

- Blamer init.lua: ~585 lines
- Blamer git.lua: ~255 lines
- Blamer ui.lua: ~138 lines
- **Total Blamer code**: ~978 lines

**~25% reduction in code** while maintaining core functionality!

## What's the Same

✓ Exact same blame parsing logic
✓ Same visual style and colors
✓ Same navigation patterns (history, parent commits)
✓ Same synchronized scrolling behavior
✓ Same hunk detection and grouping
✓ Same support for uncommitted changes

## Additional Features (Beyond Original Neogit)

✓ **Commit popup view**: Floating window showing commit details
✓ **Diff integration**: Optional diffview.nvim integration with native fallback
✓ **Standalone operation**: Works without any external plugins

## What You Can Add Later

If you want to extend the plugin, you could add:
- Custom color schemes
- Configurable width
- Virtual text inline blame (like gitsigns)
- Blame in statusline or virtual text
- Commit filtering by author/date
