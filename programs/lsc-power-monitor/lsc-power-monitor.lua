local component = require("component")
local event = require("event")
local shell = require("shell")
local term = require("term")
local unicode = require("unicode")

local usage = "Usage: lua lsc-power-monitor.lua [--mirror] [LSC address]"
local args, options = shell.parse(...)
local address = args[1]
if options.help then
  print(usage)
  print("--mirror also draws on every connected 3 x 2 screen wall.")
  return
end
if #args > 1 then
  io.stderr:write(usage .. "\n")
  return
end

local function findBanks()
  local banks = {}
  for candidate, kind in component.list() do
    if kind == "gt_machine" or kind:lower() == "lsc" then
      local ok, name = pcall(component.invoke, candidate, "getName")
      if ok and name == "multimachine.supercapacitor" then
        banks[#banks + 1] = candidate
      end
    end
  end
  table.sort(banks)
  return banks
end

local function readBank(bank)
  local ok, stored, capacity, info = pcall(function()
    return component.invoke(bank, "getStoredEUString"),
      component.invoke(bank, "getEUCapacityString"),
      component.invoke(bank, "getSensorInformation")
  end)
  if not ok then
    return nil, "Cannot read the LSC. Check the Adapter."
  end

  local readings = {}
  for _, line in ipairs(type(info) == "table" and info or {}) do
    -- Scanner arguments are separated by two literal backslashes.
    local key, value = line:match("^kekztech%.infodata%.lapotronic_super_capacitor%.([^\\]+)\\\\([^\\]+)")
    if key then
      readings[key] = value
    end
  end
  -- Older packs can expose the same EU callbacks with overflowed values.
  if not readings.eu_stored then
    return nil, "Expected the GTNH 2.9.0 LSC scanner format."
  end
  if type(stored) ~= "string" or not stored:match("^%d+$")
      or type(capacity) ~= "string" or not capacity:match("^%d+$") then
    return nil, "The LSC returned invalid energy readings."
  end
  readings.stored = stored
  readings.capacity = capacity
  return readings
end

local function energyText(digits, availableWidth)
  local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  if #grouped <= availableWidth then
    return grouped
  elseif #digits <= availableWidth then
    return digits
  end
  return string.format("%.3e", tonumber(digits))
end

local function rateText(value)
  return value and (value .. " EU/t") or "--"
end

local function draw(gpu, width, height, dx, dy, bank, reading, message, footer)
  local function row(y, content)
    local columns = unicode.wlen(content)
    -- OpenComputers' wtrunc expects a string that exceeds the target width.
    if columns > width then
      content = unicode.wtrunc(content, width + 1)
      columns = unicode.wlen(content)
    end
    gpu.set(dx + 1, dy + y, content .. string.rep(" ", width - columns))
  end

  local rows = { "LSC POWER MONITOR", [12] = footer or "Ctrl+C to exit" }
  if width < 42 or height < 12 then
    row(1, rows[1])
    if height >= 2 then
      row(2, "Needs a 42 x 12 display")
    end
    return
  end

  if reading then
    local capacity = tonumber(reading.capacity)
    local fraction = capacity > 0 and tonumber(reading.stored) / capacity or 0
    local charge = capacity > 0 and string.format("%.2f%%", fraction * 100) or "unavailable"
    local barWidth = math.min(width - 2, 48)
    local filled = math.floor(math.min(fraction, 1) * barWidth)

    rows[2] = "Bank " .. bank:sub(1, 8)
    rows[3] = "Charge    " .. charge
    rows[4] = "[" .. string.rep("#", filled) .. string.rep("-", barWidth - filled) .. "]"
    rows[6] = "Stored    " .. energyText(reading.stored, width - 13) .. " EU"
    rows[7] = "Capacity  " .. energyText(reading.capacity, width - 13) .. " EU"
    rows[9] = "Input  (5s)  " .. rateText(reading["avg_eu_in.sec"])
    rows[10] = "Output (5s)  " .. rateText(reading["avg_eu_out.sec"])
    rows[11] = "Passive loss " .. rateText(reading.passive_loss)
  else
    rows[3] = message
  end

  for y = 1, 12 do
    row(y, rows[y] or "")
  end
end

if not term.isAvailable() then
  io.stderr:write("Connect a screen and graphics card to the OpenOS terminal.\n")
  return
end

local gpu = term.gpu()
local consoleScreen = options.mirror and gpu.getScreen()
local mirrors = {}

local function restoreConsole()
  if consoleScreen and gpu.getScreen() ~= consoleScreen then
    assert(gpu.bind(consoleScreen, false))
  end
end

local function drawMirror(screen, clear, bank, reading, message, footer)
  assert(gpu.bind(screen, false))
  local width, height = gpu.getViewport()
  if clear then
    gpu.fill(1, 1, width, height, " ")
  end
  draw(gpu, width, height, 0, 0, bank, reading, message, footer)
end

local function refreshMirrors(bank, reading, message)
  local updated = {}
  local count = 0
  for screen in component.list("screen", true) do
    local ok, width, height = pcall(component.invoke, screen, "getAspectRatio")
    if ok and width == 3 and height == 2 then
      if screen == consoleScreen then
        count = count + 1
      elseif pcall(drawMirror, screen, not mirrors[screen], bank, reading, message) then
        updated[screen] = true
        count = count + 1
      end
    end
  end
  mirrors = updated
  restoreConsole()
  return string.format("3x2 walls: %d | Ctrl+C to exit", count)
end

local function monitor()
  repeat
    if not address then
      local banks = findBanks()
      if #banks > 1 then
        return "Multiple LSCs found. " .. usage .. "\n" .. table.concat(banks, "\n")
      end
      address = banks[1]
    end

    local reading, message
    if address then
      reading, message = readBank(address)
    else
      message = "Waiting for an LSC. Check the Adapter."
    end
    local footer
    if consoleScreen then
      footer = refreshMirrors(address, reading, message)
    end
    local width, height, dx, dy = term.getViewport()
    draw(gpu, width, height, dx, dy, address, reading, message, footer)
  until event.pull(1, "^interrupted$") == "interrupted"
end

term.clear()
local ok, message = pcall(monitor)
for screen in pairs(mirrors) do
  pcall(drawMirror, screen, false, nil, nil, "Monitor stopped.", "")
end
local restored, restoreError = pcall(restoreConsole)
if restored and term.isAvailable() then
  term.clear()
end
if not ok or message then
  io.stderr:write(tostring(message) .. "\n")
end
if not restored then
  io.stderr:write("Could not restore the terminal screen. " .. tostring(restoreError) .. "\n")
end
