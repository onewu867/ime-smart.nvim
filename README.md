# ime-smart.nvim

Smart IME switching for Neovim. Automatically toggles between English and Chinese input methods depending on context and restores English when leaving insert mode.

## Features
- Detects comments/strings with Tree-sitter and syntax fallbacks
- Keeps normal mode English; optional remember-last-insert behavior
- Optional debug command `:ImeSmartDebug`
- Works with Windows/WSL/macOS via `im-select`

## Installation

### Lazy.nvim
```lua
{
  "onewu867/ime-smart.nvim",
  opts = {
    english_id = "1033",
    comment_id = "2052",
    insert_leave_delay_ms = 30,
  },
}
```

### packer.nvim
```lua
use {
  "onewu867/ime-smart.nvim",
  config = function()
    require("ime_smart").setup {
      english_id = "1033",
      comment_id = "2052",
    }
  end,
}
```

### vim-plug
```vim
Plug 'onewu867/ime-smart.nvim'
let g:ime_smart_setup_opts = #{ english_id: '1033', comment_id: '2052' }
```

> Replace `your-name` with your repository path.

## Configuration
Set before plugins load:
```lua
vim.g.ime_smart_setup_opts = {
  english_id = "1033",
  comment_id = "2052",
  default_insert_id = "1033",
  remember_last_insert = false,
  contextual_switch = true,
  insert_leave_delay_ms = 30,
}
```

## Requirements
- Neovim >= 0.8
- [im-select](https://github.com/daipeihust/im-select)

## License
MIT. See [LICENSE](./LICENSE).
