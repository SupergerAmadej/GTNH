local filesystem = require("filesystem")
local shell = require("shell")

local ref, extra = ...
ref = ref or "main"
if extra or not ref:match("^[%w][%w._%-]*$") then
  io.stderr:write("Usage: lua install.lua [git-ref]\n")
  return
end

local base = "https://raw.githubusercontent.com/SupergerAmadej/GTNH/" .. ref .. "/programs/factory-control/"
local files = {"factory-control.lua", "config.example.lua"}
local wget = assert(loadfile("/bin/wget.lua"))
for _, name in ipairs(files) do
  assert(not filesystem.exists(shell.resolve(name)), name .. " already exists. Install in a new directory.")
  assert(not filesystem.exists(shell.resolve(name .. ".download")), name .. ".download already exists.")
end

local installed = {}
local ok, reason = pcall(function()
  for _, name in ipairs(files) do
    local target = shell.resolve(name .. ".download")
    assert(wget(base .. name, target), "Could not download " .. name)
    assert(filesystem.size(target) > 0, name .. " is empty")
    assert(loadfile(target))
  end
  for _, name in ipairs(files) do
    assert(filesystem.rename(shell.resolve(name .. ".download"), shell.resolve(name)))
    installed[#installed + 1] = name
  end
end)
if not ok then
  for _, name in ipairs(files) do filesystem.remove(shell.resolve(name .. ".download")) end
  for _, name in ipairs(installed) do filesystem.remove(shell.resolve(name)) end
  io.stderr:write(tostring(reason) .. "\n")
  return
end
print("Installed from " .. ref .. ". Copy config.example.lua to config.lua and edit your role's settings.")
