local component = require("component")
local computer = require("computer")

local function findDrive(prefix)
  local match
  prefix = prefix:lower()
  for address in component.list("filesystem", true) do
    if address == prefix then
      return component.proxy(address)
    end
    if address:sub(1, #prefix) == prefix then
      if match then
        error("Ambiguous address " .. prefix .. ". Use a longer prefix.", 0)
      end
      match = address
    end
  end
  if not match then
    error("No filesystem matches " .. prefix .. ". Run mount to check the drive addresses.", 0)
  end
  return component.proxy(match)
end

local sourcePrefix, destinationPrefix = ...
if select("#", ...) ~= 2 or sourcePrefix == "" or destinationPrefix == "" then
  print("Usage: lua hdd-copy.lua SOURCE_ADDRESS DESTINATION_ADDRESS")
  print("Run mount to find the addresses. Unique address prefixes work too.")
  return
end

local source = findDrive(sourcePrefix)
local destination = findDrive(destinationPrefix)
if source.address == destination.address then
  error("Choose two different drives.", 0)
end
if destination.address == computer.tmpAddress() or destination.isReadOnly() then
  error("Choose a writable, persistent destination drive.", 0)
end
local destinationEntries = assert(destination.list("/"), "Could not list the destination drive.")
if destinationEntries[1] then
  error("The destination drive must be empty.", 0)
end
if source.spaceUsed() > destination.spaceTotal() then
  error("The source contents are too large for the destination drive.", 0)
end

-- Stage one file at a time so an interrupted write cannot leave a truncated file at its final path.
local temporary = "/.hdd-copy-part"
while source.exists(temporary) do
  temporary = temporary .. "-"
end

local input, output, pending
local currentPath = "/"
local copied = 0

local function copyFile(path)
  input = assert(source.open(path, "rb"))
  assert(not destination.exists(temporary), "Temporary path already exists.")
  output = assert(destination.open(temporary, "wb"))
  pending = true
  while true do
    local data, reason = source.read(input, 4096)
    assert(not reason, reason)
    if not data then
      break
    end
    assert(destination.write(output, data))
  end
  local _, reason = destination.close(output)
  assert(not reason, reason)
  output = nil
  _, reason = source.close(input)
  assert(not reason, reason)
  input = nil

  assert(not destination.exists(path), "Destination path already exists.")
  assert(destination.rename(temporary, path))
  pending = false
  copied = copied + 1
end

local function copyDirectory(directory)
  currentPath = directory
  for _, entry in ipairs(assert(source.list(directory))) do
    local path = directory .. entry:gsub("/$", "")
    currentPath = path
    if entry:sub(-1) == "/" then
      assert(destination.makeDirectory(path))
      copyDirectory(path .. "/")
    else
      copyFile(path)
    end
    os.sleep(0)
  end
end

print("Copying " .. source.address .. " to " .. destination.address)
local ok, reason = pcall(copyDirectory, "/")
if not ok then
  if input then pcall(source.close, input) end
  if output then pcall(destination.close, output) end
  if pending then pcall(destination.remove, temporary) end
  error(string.format("Copy stopped at %s after %d file(s): %s", currentPath, copied, tostring(reason)), 0)
end

local cleanupPath = "/programs/hdd-copy.lua"
if destination.exists(cleanupPath) and not destination.isDirectory(cleanupPath) then
  local removed, removeReason = destination.remove(cleanupPath)
  if not removed then
    error("The copy finished, but removing " .. cleanupPath .. " from the destination failed. " ..
      (removeReason or "The filesystem rejected the removal."), 0)
  end
  print("Removed " .. cleanupPath .. " from the destination HDD.")
end
print(string.format("Copy complete. %d file(s) copied.", copied))
