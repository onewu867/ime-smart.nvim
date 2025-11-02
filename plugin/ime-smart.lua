if vim.g.ime_smart_disable == true then
  return
end

local ok, ime = pcall(require, "ime_smart")
if not ok then
  vim.schedule(function()
    vim.notify("[ime-smart] Failed to load module: " .. ime, vim.log.levels.ERROR)
  end)
  return
end

local opts = {}
if type(vim.g.ime_smart_setup_opts) == "table" then
  opts = vim.deepcopy(vim.g.ime_smart_setup_opts)
end

ime.setup(opts)

