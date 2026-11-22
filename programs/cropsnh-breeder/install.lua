local filesystem = require("filesystem")
local shell = require("shell")

local ref, extra = ...
ref = ref or "main"
assert(not extra and ref:match("^[%w][%w._%-]*$"), "Usage: lua install.lua [git-ref]")

local base = "https://raw.githubusercontent.com/SupergerAmadej/GTNH/" .. ref .. "/programs/cropsnh-breeder/"
local files = {"cropsnh-breeder.lua", "field.lua", "config.example.lua"}
local wget = assert(loadfile("/bin/wget.lua"))
for _, name in ipairs(files) do
  assert(not filesystem.exists(shell.resolve(name)), name .. " already exists. Install in a new directory.")
  assert(not filesystem.exists(shell.resolve(name .. ".download")), name .. ".download already exists.")
end

local installed = {}
local ok, reason = pcall(function()
  for _, name in ipairs(files) do
    local temporary = shell.resolve(name .. ".download")
    assert(wget(base .. name, temporary), "Could not download " .. name)
    assert(filesystem.size(temporary) > 0, name .. " is empty")
    assert(loadfile(temporary))
  end
  for _, name in ipairs(files) do
    assert(filesystem.rename(shell.resolve(name .. ".download"), shell.resolve(name)))
    installed[#installed + 1] = name
  end
end)
if not ok then
  for _, name in ipairs(files) do filesystem.remove(shell.resolve(name .. ".download")) end
  for _, name in ipairs(installed) do filesystem.remove(shell.resolve(name)) end
  error(reason, 0)
end
print("Installed from " .. ref .. ". Copy config.example.lua to config.lua and set up your plots.")
