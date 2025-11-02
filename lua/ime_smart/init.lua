local M = {}

local config
local state = {
  augroup = nil,
  command = nil,
  last_set = nil,
  last_insert = nil,
  last_reason = nil,
  warned_missing = false,
  warned_job_failure = false,
}

local function joinpath(...)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end
  local sep = package.config:sub(1, 1)
  return table.concat({ ... }, sep)
end

local function normalize(path)
  if not path then
    return path
  end
  if vim.fs and vim.fs.normalize then
    return vim.fs.normalize(path)
  end
  return path
end

local function default_config()
  return {
    english_id = vim.g.ime_smart_english_id,
    default_insert_id = vim.g.ime_smart_default_insert_id or vim.g.ime_smart_default_id,
    comment_id = vim.g.ime_smart_comment_id,
    remember_last_insert = vim.g.ime_smart_remember_last_insert,
    contextual_switch = vim.g.ime_smart_contextual_switch,
    notify = vim.g.ime_smart_notify,
    command = vim.g.ime_smart_command,
    insert_leave_delay_ms = vim.g.ime_smart_insert_leave_delay_ms,
  }
end

local function to_boolean(value, default)
  if value == nil then
    return default
  end
  if type(value) == "number" then
    return value ~= 0
  end
  return value and true or false
end

local function notify(msg, level)
  if not config.notify then
    return
  end
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = "IME Smart" })
  end)
end

local function is_windows()
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

local function is_wsl()
  return vim.fn.has("wsl") == 1
end

local function normalize_id(id)
  if id == nil then
    return nil
  end
  return tostring(id)
end

local function is_executable(path)
  if not path or path == "" then
    return false
  end
  if path:find("[/\\]") then
    return vim.fn.filereadable(path) == 1
  end
  return vim.fn.executable(path) == 1
end

local function candidate_paths()
  local candidates = {}

  if config.command and config.command ~= "" then
    table.insert(candidates, config.command)
  end

  local data_dir = normalize(vim.fn.stdpath("data"))
  local win_candidate = normalize(joinpath(data_dir, "im-select", "im-select-win", "out", "x64", "im-select.exe"))
  local mac_candidate = normalize(joinpath(data_dir, "im-select", "im-select-mac", "out", "im-select"))
  local legacy_wsl = "../../nvim-data/im-select/im-select-win/out/x64/im-select.exe"

  if is_windows() then
    table.insert(candidates, win_candidate)
    table.insert(candidates, "im-select.exe")
  elseif is_wsl() then
    table.insert(candidates, legacy_wsl)
    table.insert(candidates, win_candidate)
    table.insert(candidates, "im-select.exe")
  else
    table.insert(candidates, mac_candidate)
    table.insert(candidates, "im-select")
  end

  return candidates
end

local function ensure_command()
  if state.command then
    return state.command
  end

  local candidates = candidate_paths()
  for _, cmd in ipairs(candidates) do
    if is_executable(cmd) then
      state.command = cmd
      return state.command
    end
  end

  if not state.warned_missing then
    state.warned_missing = true
    notify(
      ("im-select executable not found. Checked: %s. Install it from https://github.com/daipeihust/im-select and ensure it is on $PATH or set `vim.g.ime_smart_command`."):format(
        table.concat(candidates, ", ")
      ),
      vim.log.levels.WARN
    )
  end

  return nil
end

local function call_im_select(args)
  local cmd = ensure_command()
  if not cmd then
    return nil
  end
  local command = { cmd }
  vim.list_extend(command, args)
  return vim.fn.jobstart(command, { detach = true })
end

local function set_ime(id)
  id = normalize_id(id)
  if not id then
    return
  end

  if state.last_set == id then
    return
  end

  local job = call_im_select({ id })
  if not job or job <= 0 then
    if not state.warned_job_failure then
      state.warned_job_failure = true
      notify(("Failed to run im-select for id %s (job id: %s)"):format(id, tostring(job)), vim.log.levels.WARN)
    end
    return
  end

  state.last_set = id
  if config.remember_last_insert and id ~= config.english_id then
    state.last_insert = id
  end
end

local function get_current_ime()
  local cmd = ensure_command()
  if not cmd then
    return nil
  end

  local output = vim.fn.system({ cmd })
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local trimmed = vim.fn.trim(output or "")
  if trimmed == "" then
    return nil
  end
  return trimmed
end

local function ts_get_node(row, col)
  if not vim.treesitter or not vim.treesitter.get_parser then
    return nil
  end
  local ok, parser = pcall(vim.treesitter.get_parser, 0)
  if not ok or not parser then
    return nil
  end

  if vim.treesitter.get_node then
    local ok_get, node = pcall(vim.treesitter.get_node, { bufnr = 0, pos = { row, col }, parser = parser })
    if ok_get and node then
      return node
    end
  end

  if vim.treesitter.get_node_at_pos then
    local ok_get, node = pcall(vim.treesitter.get_node_at_pos, 0, row, col, {})
    if ok_get and node then
      return node
    end
  end

  local ok_utils, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
  if ok_utils and ts_utils and ts_utils.get_node_at_cursor then
    local ok_get, node = pcall(ts_utils.get_node_at_cursor)
    if ok_get and node then
      return node
    end
  end

  return nil
end

local function in_comment_or_string()
  if not config.contextual_switch then
    return false
  end

  local row, col = vim.api.nvim_win_get_cursor(0)[1] - 1, vim.api.nvim_win_get_cursor(0)[2]

  local function matches(n)
    if not n or not n:type() then
      return false
    end
    local function type_matches(t)
      if not t or t == "" then
        return false
      end
      local tl = string.lower(t)
      if tl:find("string", 1, true) or tl:find("template", 1, true) or tl:find("regex", 1, true) then
        return true
      end
      if tl:find("comment", 1, true) or tl:find("doc", 1, true) or tl:find("documentation", 1, true) or tl:find("annotation", 1, true) then
        return true
      end
      return false
    end
    if type_matches(n:type()) then
      return true
    end
    local parent = n:parent()
    while parent do
      if type_matches(parent:type()) then
        return true
      end
      parent = parent:parent()
    end
    return false
  end

  local node = ts_get_node(row, col)
  if matches(node) then
    return true
  end

  if vim.treesitter and vim.treesitter.get_captures_at_pos then
    local ok_caps, captures = pcall(vim.treesitter.get_captures_at_pos, 0, row, col)
    if ok_caps and type(captures) == "table" then
      for _, item in ipairs(captures) do
        local capture = item
        if type(item) == "table" then
          capture = item.capture or item[1]
        end
        if type(capture) == "string" then
          local cap = capture:lower()
          if cap:find("comment", 1, true) or cap:find("doc", 1, true) then
            return true
          end
          if cap:find("string", 1, true) or cap:find("regex", 1, true) then
            return true
          end
        end
      end
    end
  end

  local line = vim.api.nvim_get_current_line()

  local function match_commentstring()
    local cs = vim.bo.commentstring
    if not cs or cs == "" or cs == "%s" or not cs:find("%%s") then
      return false
    end
    local pre, post = cs:match("^(.*)%%s(.*)$")
    pre = pre and pre:gsub("%s+$", "") or ""
    post = post and post:gsub("^%s+", "") or ""
    local left = line:sub(1, col + 1)
    if pre ~= "" then
      local pattern = "^%s*" .. vim.pesc(pre)
      if left:match(pattern) then
        return true
      end
    end
    if post ~= "" then
      local from = line:sub(col + 1)
      if from:find(vim.pesc(post), 1, true) then
        return true
      end
    end
    return false
  end

  if match_commentstring() then
    return true
  end

  local ok_synstack, stack = pcall(vim.fn.synstack, vim.fn.line("."), vim.fn.col("."))
  if ok_synstack and type(stack) == "table" then
    for _, sid in ipairs(stack) do
      local name = vim.fn.synIDattr(sid, "name")
      name = string.lower(name or "")
      if name:find("comment", 1, true) or name:find("doc", 1, true) then
        return true
      end
      if name:find("string", 1, true) or name:find("regex", 1, true) then
        return true
      end
    end
  end

  local ok_syn, syn_id = pcall(vim.fn.synID, vim.fn.line("."), vim.fn.col("."), 1)
  if ok_syn then
    local name = vim.fn.synIDattr(syn_id, "name")
    name = string.lower(name or "")
    if name:find("comment", 1, true) or name:find("doc", 1, true) then
      return true
    end
    if name:find("string", 1, true) or name:find("regex", 1, true) then
      return true
    end
  end

  return false
end

local function update_insert_ime()
  if not ensure_command() then
    return
  end

  local target = config.default_insert_id
  local reason = "default"
  if config.remember_last_insert and state.last_insert then
    target = state.last_insert
    reason = "remember"
  end
  if in_comment_or_string() then
    target = config.comment_id
    reason = "comment"
  end
  set_ime(target)
  state.last_reason = reason
end

local function on_insert_leave()
  if not ensure_command() then
    return
  end

  if config.remember_last_insert then
    local current = get_current_ime()
    if current and current ~= config.english_id then
      state.last_insert = current
    end
  end

  set_ime(config.english_id)
  state.last_reason = "insert_leave"
end

local function on_buf_enter()
  set_ime(config.english_id)
  state.last_reason = "buf_enter"
end

local function on_cmdline_enter()
  set_ime(config.english_id)
  state.last_reason = "cmdline_enter"
end

local function build_debug_info()
  local info = {
    config = {
      english_id = config.english_id,
      default_insert_id = config.default_insert_id,
      comment_id = config.comment_id,
      remember_last_insert = config.remember_last_insert,
      contextual_switch = config.contextual_switch,
      notify = config.notify,
      insert_leave_delay_ms = config.insert_leave_delay_ms,
      command = state.command or ensure_command(),
    },
    state = {
      last_set = state.last_set,
      last_insert = state.last_insert,
      last_reason = state.last_reason,
    },
  }
  local ok, current = pcall(get_current_ime)
  info.state.current_ime = ok and current or nil
  local ok_ctx, is_ctx = pcall(in_comment_or_string)
  info.state.is_comment_or_string = ok_ctx and is_ctx or false
  return info
end

function M.debug_info()
  return build_debug_info()
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", default_config(), opts or {})

  config.english_id = normalize_id(config.english_id) or "1033"
  config.default_insert_id = normalize_id(config.default_insert_id) or config.english_id
  config.comment_id = normalize_id(config.comment_id) or "2052"
  config.remember_last_insert = to_boolean(config.remember_last_insert, false)
  config.contextual_switch = to_boolean(config.contextual_switch, true)
  config.notify = to_boolean(config.notify, true)
  config.insert_leave_delay_ms = tonumber(config.insert_leave_delay_ms) or 30

  state.command = nil
  state.last_set = nil
  state.last_insert = nil
  state.last_reason = nil
  state.warned_missing = false
  state.warned_job_failure = false

  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  end
  state.augroup = vim.api.nvim_create_augroup("ImeSmart", { clear = true })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = state.augroup,
    callback = update_insert_ime,
    desc = "IME smart: switch on InsertEnter",
  })

  if config.contextual_switch then
    vim.api.nvim_create_autocmd("CursorMovedI", {
      group = state.augroup,
      callback = update_insert_ime,
      desc = "IME smart: refresh on CursorMovedI",
    })
    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
      group = state.augroup,
      callback = function()
        vim.schedule(update_insert_ime)
      end,
      desc = "IME smart: refresh on text change in insert",
    })
  end

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = state.augroup,
    callback = function()
      if config.insert_leave_delay_ms > 0 then
        vim.defer_fn(on_insert_leave, config.insert_leave_delay_ms)
      else
        on_insert_leave()
      end
    end,
    desc = "IME smart: switch to English on InsertLeave",
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = state.augroup,
    pattern = { "i:*", "ic:*", "ix:*" },
    callback = function()
      if config.insert_leave_delay_ms > 0 then
        vim.defer_fn(on_insert_leave, config.insert_leave_delay_ms)
      else
        on_insert_leave()
      end
    end,
    desc = "IME smart: switch to English when leaving insert-like modes",
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = state.augroup,
    callback = on_buf_enter,
    desc = "IME smart: ensure English on BufEnter",
  })

  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = state.augroup,
    callback = on_cmdline_enter,
    desc = "IME smart: ensure English in command-line mode",
  })

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = state.augroup,
    callback = update_insert_ime,
    desc = "IME smart: restore after command-line",
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = state.augroup,
    callback = function()
      pcall(set_ime, config.english_id)
    end,
    desc = "IME smart: restore English on exit",
  })

  if ensure_command() then
    set_ime(config.english_id)
  end

  pcall(vim.api.nvim_del_user_command, "ImeSmartDebug")
  vim.api.nvim_create_user_command("ImeSmartDebug", function()
    local info = build_debug_info()
    vim.notify(vim.inspect(info), vim.log.levels.INFO, { title = "IME Smart Debug" })
  end, { desc = "Show IME Smart debug information" })

  return M
end

return M

