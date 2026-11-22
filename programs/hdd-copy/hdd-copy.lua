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

local sourcePrefix, destinationPrefix, program = ...
if not sourcePrefix or not destinationPrefix or select("#", ...) > 3
    or sourcePrefix == "" or destinationPrefix == "" then
  print("Usage: lua hdd-copy.lua SOURCE_ADDRESS DESTINATION_ADDRESS [PROGRAM]")
  print("Run mount to find the addresses. Unique address prefixes work too.")
  return
end

local launchArgs = ""
if program then
  if program == "factory-control:agent" then
    program, launchArgs = "factory-control", " agent"
  elseif program == "factory-control" then
    launchArgs = " central"
  end
  assert(program:match("^[a-z0-9][a-z0-9%-]*$"), "Use a GTNH repository program name.")
  assert(program ~= "hdd-copy", "HDD copy needs drive addresses and cannot be installed for startup.")
  assert(component.isAvailable("internet"), "Install an Internet Card to download a program.")
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

local function withFile(filesystem, path, mode, action)
  local file = assert(filesystem.open(path, mode))
  local ok, result = pcall(action, file)
  local _, closeReason = file:close()
  if not ok then error(result, 0) end
  assert(not closeReason, closeReason)
end

local function download(filesystem, url, path)
  local response = require("internet").request(url)
  local ok, reason = pcall(function()
    local chunk = assert(response(), "Empty download from " .. url)
    withFile(filesystem, path, "wb", function(file)
      repeat
        assert(file:write(chunk))
        chunk = response()
      until not chunk
    end)
  end)
  local missing = not ok and response.response() == 404
  response.close()
  if not ok and not missing then
    error("Could not download " .. url .. ": " .. tostring(reason), 0)
  end
  return ok
end

local function installProgram()
  local filesystem = require("filesystem")
  local shell = require("shell")
  local mountPath = "/tmp/hdd-copy-install"
  while filesystem.exists(mountPath) do
    mountPath = mountPath .. "-"
  end

  local directory = "/programs/" .. program
  local suffix = 2
  while destination.exists(directory) do
    directory = "/programs/" .. program .. "-" .. suffix
    suffix = suffix + 1
  end
  local entry = program .. ".lua"
  local ref = "main"
  local url = "https://raw.githubusercontent.com/SupergerAmadej/GTNH/" .. ref .. "/programs/" .. program .. "/"
  local shrc = "/home/.shrc"
  local staging = mountPath .. temporary
  local stagedShrc = temporary .. "/.hdd-copy-shrc"
  local cwd = shell.getWorkingDirectory()
  local staged, installed

  assert(filesystem.mount(destination, mountPath))
  local ok, reason = pcall(function()
    assert(not destination.exists(temporary), "Temporary path already exists.")
    assert(destination.makeDirectory(temporary))
    staged = true
    local installer = staging .. "/install.lua"
    if download(filesystem, url .. "install.lua", installer) then
      assert(shell.setWorkingDirectory(staging))
      assert(loadfile(installer))(ref)
      assert(shell.setWorkingDirectory(cwd))
      assert(destination.remove(temporary .. "/install.lua"))
    else
      assert(download(filesystem, url .. entry, staging .. "/" .. entry), "Program not found on GitHub: " .. program)
    end
    assert(loadfile(staging .. "/" .. entry))

    for _, parent in ipairs({"/programs", "/home"}) do
      if not destination.exists(parent) then
        assert(destination.makeDirectory(parent))
      end
      assert(destination.isDirectory(parent), parent .. " must be a directory.")
    end
    assert(not destination.isDirectory(shrc), shrc .. " must be a file.")
    assert(not destination.exists(stagedShrc), "Temporary startup file already exists.")
    local command = string.format("cd %s && %s/%s%s; cd /home\n", directory, directory, entry, launchArgs)
    withFile(filesystem, mountPath .. stagedShrc, "wb", function(outputFile)
      assert(outputFile:write(command))
      if destination.exists(shrc) then
        withFile(filesystem, mountPath .. shrc, "rb", function(inputFile)
          while true do
            local data, readReason = inputFile:read(4096)
            assert(not readReason, readReason)
            if not data then break end
            assert(outputFile:write(data))
          end
        end)
      end
    end)

    assert(not destination.exists(directory), "Install directory already exists.")
    assert(destination.rename(temporary, directory), "Could not move program into " .. directory)
    installed = true
    assert(destination.rename(directory .. "/.hdd-copy-shrc", shrc), "Could not update " .. shrc)
  end)
  shell.setWorkingDirectory(cwd)
  filesystem.umount(mountPath)
  if not ok then
    if staged then pcall(destination.remove, installed and directory or temporary) end
    error("HDD copied, but startup setup failed for " .. program .. ": " .. tostring(reason), 0)
  end
  print("Installed " .. program .. " in " .. directory .. " and added it to " .. shrc .. ".")
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
if program then installProgram() end
print(string.format("Copy complete. %d file(s) copied.", copied))
