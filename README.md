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

## System Setup

### Windows
- Download [im-select for Windows](https://github.com/daipeihust/im-select/releases) and add `im-select.exe` to `PATH`, or place it under `~/AppData/Local/nvim-data/im-select/im-select-win/out/x64/im-select.exe`.
- Common layout IDs: `1033` (US English), `2052` (Simplified Chinese). Run `im-select.exe` to check current layout.
- To force a custom location:
  ```lua
  vim.g.ime_smart_setup_opts = {
    command = "/path/to/im-select/im-select-win/out/x64/im-select.exe",
  }
  ```

### WSL
- Install `im-select.exe` on Windows and call it from WSL, e.g. `/mnt//path/to/im-select/im-select-win/out/x64/im-select.exe`.
- Example configuration:
  ```lua
  vim.g.ime_smart_setup_opts = {
    command = "/mnt/path/to/im-select.exe",
    english_id = "1033",
    comment_id = "2052",
  }
  ```
- Ensure running the command inside WSL actually switches the Windows IME.

### macOS
- Install via Homebrew (`brew install ime-select`) or build from source.
- Typical IDs: `com.apple.keylayout.ABC` (English), `com.apple.inputmethod.SCIM.ITABC` (Simplified Chinese Pinyin).
  ```lua
  vim.g.ime_smart_setup_opts = {
    english_id = "com.apple.keylayout.ABC",
    comment_id = "com.apple.inputmethod.SCIM.ITABC",
  }
  ```

### Linux
- Official `im-select` lacks Linux support. Provide a compatible script (wrapping `fcitx5-remote`, `ibus engine`, etc.) and reference it via `command`.
  ```lua
  vim.g.ime_smart_setup_opts = {
    command = "/usr/local/bin/im-select", -- custom script
    english_id = "keyboard-us",
    comment_id = "pinyin",
  }
  ```
- If no automation is available, set `contextual_switch = false` so only `InsertLeave` enforces English.

## Requirements
- Neovim >= 0.8
- [im-select](https://github.com/daipeihust/im-select)

## License
MIT. See [LICENSE](./LICENSE).
