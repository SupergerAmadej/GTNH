local component = require("component")
local computer = require("computer")
local event = require("event")
local filesystem = require("filesystem")
local shell = require("shell")

local protocol = "factory-control/1"
local sampleInterval = 3
local offlineAfter = 10
local commandTimeout = 6
local redrawInterval = 0.25
local pairingWindow = 60
local machineLimit = 99

local function isInteger(value)
  return type(value) == "number" and math.abs(value) < math.huge and value % 1 == 0
end

local function isInt32(value)
  return isInteger(value) and value >= -2147483648 and value <= 2147483647
end

local function parseCorner(value)
  if type(value) ~= "string" then return end
  local x, z = value:match("^%s*([+-]?%d+)%s*,%s*([+-]?%d+)%s*$")
  if x then
    x, z = tonumber(x), tonumber(z)
    if isInt32(x) and isInt32(z) then return x, z end
  else
    x = tonumber(value:match("^%s*([+-]?%d+)%s*$") or "")
    if isInt32(x) then return x end
  end
end

local function isAddress(value)
  return type(value) == "string" and #value == 36
    and value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x+$")
end

local function isLabel(value)
  return type(value) == "string" and value:match("^[ -~]+$")
end

local function readFile(path, format)
  local file = assert(io.open(path, "r"))
  local value = file:read(format)
  file:close()
  return value
end

local function writeFile(path, value)
  local directory = filesystem.path(path)
  if not filesystem.exists(directory) then assert(filesystem.makeDirectory(directory)) end
  -- Keep incomplete writes separate from the file the reader will use.
  local temporary = path .. ".tmp"
  local file = assert(io.open(temporary, "w"))
  local written, writeError = file:write(value)
  local flushed, flushError = file:flush()
  file:close()
  assert(written and flushed, writeError or flushError)
  assert(filesystem.rename(temporary, path))
end

local function savePair(path, value)
  if filesystem.exists(path) then
    assert(readFile(path, "*l") == value, "A different pairing is already saved")
  else
    writeFile(path, value .. "\n")
  end
end

local function pairedCentral(settings, statePath)
  local pinned = settings.centralModem
  if pinned == nil then pinned = settings.dashboardModem end
  local central = pinned
  if central == nil and filesystem.exists(statePath) then central = readFile(statePath, "*l") or "" end
  assert(central == nil or isAddress(central), "Invalid central modem address in config or pairing state")
  return central, pinned ~= nil
end

-- English names for common GTNH controllers with opaque registry IDs.
local controllerNames = {
  assemblyline = "Assembly Line",
  basiccompressor = "Large Electric Compressor",
  blastfurnace = "Electric Blast Furnace",
  brickedblastfurnace = "Bricked Blast Furnace",
  chemicalreactor = "Large Chemical Reactor",
  distillationtower = "Distillation Tower",
  fluidextractor = "Large Fluid Extractor",
  heatexchanger = "Large Heat Exchanger",
  implosioncompressor = "Implosion Compressor",
  largegasturbine = "Large Gas Turbine",
  largehpturbine = "Large HP Steam Turbine",
  largeplasmaturbine = "Large Plasma Turbine",
  largeturbine = "Large Steam Turbine",
  multifurnace = "Multi Smelter",
  oreprocessor = "Integrated Ore Factory",
  pyro = "Pyrolyse Oven",
  supercapacitor = "Lapotronic Supercapacitor",
  vacuumfreezer = "Vacuum Freezer",
}

local function controllerName(address)
  local ok, name = pcall(component.invoke, address, "getName")
  if ok and isLabel(name) then
    local id = name:gsub("^gt%.blockmachines%.", ""):gsub("^multimachine%.", "")
    local label = controllerNames[id:lower()]
    if label then return label end
    label = id:gsub("(%l)(%u)", "%1 %2"):gsub("[_.%-]+", " "):match("^%s*(.-)%s*$")
    if isLabel(label) then return (label:gsub("%f[%w]%l", string.upper)):sub(1, 64) end
  end
  return "Controller " .. address:sub(1, 8)
end

local function findCandidates()
  local found = {}
  for address in component.list() do
    local methods = component.methods(address)
    if methods and methods.getCoordinates ~= nil and methods.isMachineActive ~= nil
        and methods.isWorkAllowed ~= nil and methods.getWorkProgress ~= nil and methods.getWorkMaxProgress ~= nil
        and methods.getSensorInformation ~= nil then
      found[address] = true
    end
  end
  return found
end

local function readScanner(address)
  local ok, lines = pcall(component.invoke, address, "getSensorInformation")
  local problems, usage, multiblock
  if ok and type(lines) == "table" then
    for _, line in ipairs(lines) do
      if type(line) == "string" then
        local plain = line:gsub("§[0-9a-fk-orA-FK-OR]", "")
        problems = tonumber(plain:match("^Problems:%s*(%d+)%s*$")) or problems
        usage = plain:match("^Currently uses:%s*([%d.,eE+%-]+)%s*EU/t%s*$") or usage
        if plain:match("^GT5U%.multiblock%.scanner%.")
            or plain:match("^kekztech%.infodata%.lapotronic_super_capacitor%.") then
          multiblock = true
        end
      end
    end
  end
  return problems, usage, problems ~= nil or multiblock
end

local function readMachine(address, allowControl, requireMultiblock)
  local problems, usage, multiblock = readScanner(address)
  if requireMultiblock and not multiblock then return end
  local machine = component.proxy(address)
  local x, y, z = machine.getCoordinates()
  assert(isInteger(x) and isInteger(y) and isInteger(z), "Controller coordinates unavailable")
  local active, enabled = machine.isMachineActive(), machine.isWorkAllowed()
  local progress, maximum = machine.getWorkProgress(), machine.getWorkMaxProgress()
  assert(type(active) == "boolean" and type(enabled) == "boolean"
    and isInteger(progress) and isInteger(maximum), "Controller state unavailable")
  return table.concat({x, y, z, active and 1 or 0, enabled and 1 or 0, progress, maximum,
    problems or "", usage or "", allowControl and machine.setWorkAllowed and 1 or 0}, "\t")
end

local function decodeStatus(payload)
  if type(payload) ~= "string" or #payload > 256 then return end
  local fields = {}
  for field in (payload .. "\t"):gmatch("([^\t]*)\t") do
    fields[#fields + 1] = field
  end
  if #fields ~= 10 then return end
  for _, index in ipairs({1, 2, 3, 6, 7}) do
    local value = tonumber(fields[index])
    if not isInt32(value) then return end
    fields[index] = value
  end
  local problems = tonumber(fields[8])
  for _, index in ipairs({4, 5, 10}) do
    if fields[index] ~= "0" and fields[index] ~= "1" then return end
  end
  if fields[8] ~= "" and not (isInteger(problems) and problems >= 0) then return end
  if fields[9] ~= "" and not fields[9]:match("^[%d.,eE+%-]+$") then return end
  return {
    x = fields[1], y = fields[2], z = fields[3], active = fields[4] == "1", enabled = fields[5] == "1",
    progress = fields[6], maximum = fields[7], problems = problems,
    usage = fields[9] ~= "" and fields[9] or nil, control = fields[10] == "1",
  }
end

local function runAgent(settings, send, receive, statePath, requestControl, service)
  local legacy = settings.controller
  local configured = settings.controllers
  if legacy ~= nil then
    assert(isAddress(legacy), "Set agent.controller to the controller's full component address")
    assert(configured == nil, "Set either agent.controller or agent.controllers")
    configured = {[legacy] = controllerName(legacy)}
  elseif configured ~= nil then
    assert(type(configured) == "table" and next(configured), "Set agent.controllers to an address -> label table")
    for address, name in pairs(configured) do
      assert(isAddress(address) and isLabel(name) and #name <= 64,
        "Each agent.controllers entry needs a full component address and a label of up to 64 characters")
    end
  end
  local central, pinned = pairedCentral(settings, statePath)
  assert(not requestControl or central, "Pair this computer in agent mode before running agent-control")
  assert(not service or central == service.central, "Central pairing changed. Register agent-autostart again.")
  -- Require a local opt-in tied to an already known central modem.
  local allowControl = requestControl or (settings.allowControl == true and pinned)
  local token
  local label = settings.name
  assert(label == nil or (isLabel(label) and #label <= 64), "Set agent.name to a label of up to 64 characters")
  if not central then
    token = require("uuid").next()
    print("Open Add agent on central. Ctrl+C to exit.")
  else
    local mode = allowControl and "Machine control enabled" or "Monitoring only"
    local stopHint = service and "rc factory-control stop to exit." or "Ctrl+C to exit."
    print("Factory agent paired to " .. central .. ". " .. mode .. ". " .. stopHint)
  end
  local function sendResult(id, address, applied)
    if legacy then
      send(central, "result", id, applied)
    else
      send(central, "machine-result", id, address, applied)
    end
  end

  local controllers = {}
  local nextSample = 0
  local pending, lastError
  while true do
    local now = computer.uptime()
    if pending and now >= pending.checkAt then
      local ok, enabled = pcall(component.invoke, pending.controller, "isWorkAllowed")
      local applied = ok and enabled == pending.enabled
      if applied or now >= pending.deadline then
        sendResult(pending.id, pending.controller, applied)
        pending = nil
        nextSample = now
      else
        pending.checkAt = now + 0.25
      end
    end
    if now >= nextSample then
      local candidates = configured or findCandidates()
      local addresses = {}
      for address in pairs(candidates) do addresses[#addresses + 1] = address end
      table.sort(addresses)
      local found, count = {}, 0
      local firstError, preview, previewAddress
      for _, address in ipairs(addresses) do
        local ok, payload = pcall(readMachine, address, allowControl, not configured)
        if ok and payload then
          local name = configured and configured[address] or controllers[address] or controllerName(address)
          found[address], count = name, count + 1
          if not central then
            if not preview then preview, previewAddress = payload, address end
          elseif legacy then
            ok = send(central, "status", payload)
          else
            ok = send(central, "machine-status", address, name, payload)
          end
          if not ok then firstError = firstError or "Could not send status. Check the wireless card and power." end
        elseif not ok then
          local name = configured and configured[address] or controllers[address] or address
          firstError = firstError or (name .. ": " .. tostring(payload))
        end
      end
      controllers = found
      if not central and preview then
        local name = label or (count == 1 and controllers[previewAddress]) or ("Agent " .. previewAddress:sub(1, 8))
        if not send(nil, "hello", token, name, preview, count) then
          firstError = firstError or "Could not send pairing broadcast. Check the wireless card and power."
        end
      end
      if count == 0 and not firstError then
        firstError = "No multiblock controllers found. Check the Adapters and scanner information."
      end
      if firstError and firstError ~= lastError then print(firstError) end
      lastError = firstError
      nextSample = computer.uptime() + sampleInterval
    end

    local wakeAt = pending and math.min(nextSample, pending.checkAt) or nextSample
    local signal, sender, kind, id, target, enabled = receive(math.max(0, wakeAt - computer.uptime()))
    if signal == "interrupted" then return end
    if not central and kind == "pair" and id == token and isAddress(sender) then
      local saved, reason = pcall(savePair, statePath, sender)
      if saved then
        central, nextSample = sender, 0
        print("Paired with central " .. central .. ". Monitoring only.")
      else
        print("Could not save pairing: " .. tostring(reason))
      end
    elseif central and sender == central and type(id) == "string" and #id <= 64 then
      if legacy and kind == "set-work" then
        target, enabled = legacy, target
      elseif legacy or kind ~= "set-machine" or not isAddress(target) then
        target = nil
      end
      if target and type(enabled) == "boolean" and (not pending or id ~= pending.id) then
        if allowControl and controllers[target] and not pending
            and pcall(component.invoke, target, "setWorkAllowed", enabled) then
          now = computer.uptime()
          pending = {id = id, controller = target, enabled = enabled, checkAt = now + 0.25, deadline = now + 3}
        else
          sendResult(id, target, false)
        end
      end
    end
  end
end

local colors = {
  background = 0x101820, panel = 0x1C2935, grid = 0x344451, text = 0xFFFFFF, muted = 0xAAAAAA,
  selected = 0x344C60, button = 0x205496, ink = 0x000000,
}

local fault = {label = "Maintenance", short = "Maint", mark = "!", color = 0xAA0000, rank = 1}
local offline = {label = "Offline", short = "Offline", mark = "?", color = 0x555555, rank = 2}
local disabled = {label = "Disabled", short = "Disabled", mark = "D", color = 0xFFAA00, rank = 3, ink = colors.ink}
local operating = {label = "Running", short = "Run", mark = "R", color = 0x00AA00, rank = 4}
local standby = {label = "Standby", short = "Standby", mark = "S", color = 0x0000AA, rank = 5}
local states = {operating, standby, fault, offline, disabled}

local function machineState(machine)
  local status = machine.status
  if not machine.online then return offline end
  if status.problems and status.problems > 0 then return fault end
  if not status.enabled then return disabled end
  if status.active then return operating end
  return standby
end

local function contains(rect, x, y)
  return rect and x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h
end

local function touched(targets, x, y)
  for _, target in ipairs(targets) do
    if contains(target, x, y) then return target end
  end
end

local function fitHall(machines)
  local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
  for _, machine in ipairs(machines) do
    local status = machine.status
    if status then
      minX, maxX = math.min(minX, status.x), math.max(maxX, status.x)
      minZ, maxZ = math.min(minZ, status.z), math.max(maxZ, status.z)
    end
  end
  if minX == math.huge then return end
  local spanX, spanZ = math.max(8, maxX - minX + 4), math.max(8, maxZ - minZ + 4)
  return {originX = math.floor((minX + maxX - spanX) / 2), originZ = math.floor((minZ + maxZ - spanZ) / 2),
    spanX = spanX, spanZ = spanZ}
end

local function paint(gpu, x, y, text, background, foreground)
  gpu.setBackground(background or colors.panel)
  gpu.setForeground(foreground or colors.text)
  gpu.set(x, y, text)
end

local function button(gpu, x, y, label, background, foreground, height)
  local rect = {x = x, y = y, w = #label, h = height or 1}
  paint(gpu, x, y, label, background or colors.button, foreground)
  if height == 2 then gpu.fill(x, y + 1, rect.w, 1, " ") end
  return rect
end

local function panelText(gpu, panel, row, text, foreground)
  paint(gpu, panel.x + 1, panel.y + row, text:sub(1, panel.w - 2), colors.panel, foreground)
end

local function ageLabel(machine, now)
  local seconds = math.max(0, math.floor(now - machine.lastSeen))
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  return math.floor(seconds / 3600) .. "h"
end

local function tileLabel(name, width)
  if #name <= width then return name end
  local initials = {}
  for word in name:gmatch("%w+") do initials[#initials + 1] = word:sub(1, 1) end
  return #initials > 1 and table.concat(initials):sub(1, width) or name:sub(1, width)
end

local function hallPosition(hall, status)
  local x = (status.x - hall.originX) / hall.spanX
  local z = (status.z - hall.originZ) / hall.spanZ
  if x >= 0 and x <= 1 and z >= 0 and z <= 1 then return x, z end
end

-- Each pair is the signed hall axis that increases toward screen right and down.
local hallAxes = {[0] = {1, 2}, [90] = {-2, 1}, [180] = {-1, -2}, [270] = {2, -1}}

local function axisDirection(hall, axis, arrow)
  if math.abs(axis) == 1 then
    return "X " .. arrow .. (axis * hall.spanX > 0 and " East" or " West")
  end
  return "Z " .. arrow .. (axis * hall.spanZ > 0 and " South" or " North")
end

local function axisPosition(axis, x, z)
  local value = math.abs(axis) == 1 and x or z
  return axis < 0 and (1 - value) or value
end

local function drawMap(gpu, panel, hall, machines, selected, view, rotation)
  if not hall then
    panelText(gpu, panel, 0, "HALL MAP")
    panelText(gpu, panel, 2, "Waiting for machine status", colors.muted)
    return
  end

  local right, down = hallAxes[rotation][1], hallAxes[rotation][2]
  panelText(gpu, panel, 0, "HALL MAP   " .. axisDirection(hall, right, ">") .. "   " .. axisDirection(hall, down, "v"))
  local x0, y0, width, height = panel.x + 1, panel.y + 2, panel.w - 2, panel.h - 3
  gpu.setForeground(colors.grid)
  for line = 1, 3 do
    gpu.fill(x0 + math.floor(line * (width - 1) / 4), y0, 1, height, "|")
    gpu.fill(x0, y0 + math.floor(line * (height - 1) / 4), width, 1, "-")
  end

  -- Snap markers to non-overlapping cells. Machines in the same cell share one touch target.
  local tileWidth, tileHeight = width >= 85 and 8 or 6, 2
  local columns, rows = math.floor(width / tileWidth), math.floor(height / tileHeight)
  local cells = {}
  for _, machine in ipairs(machines) do
    local x, z = hallPosition(hall, machine.status)
    if x then
      local col = math.floor(axisPosition(right, x, z) * (columns - 1) + 0.5)
      local row = math.floor(axisPosition(down, x, z) * (rows - 1) + 0.5)
      local key = row * columns + col
      local cell = cells[key]
      local state = machineState(machine)
      if not cell then
        cell = {x = x0 + math.floor(col * (width - tileWidth) / (columns - 1)),
          y = y0 + math.floor(row * (height - tileHeight) / (rows - 1)),
          w = tileWidth, h = tileHeight, machines = {}, state = state}
        cells[key] = cell
        view.markers[#view.markers + 1] = cell
      end
      cell.machines[#cell.machines + 1] = machine
      if state.rank < cell.state.rank then cell.state = state end
      if selected == machine then cell.selected = true end
    end
  end

  for _, cell in ipairs(view.markers) do
    local state = cell.state
    local machine = cell.machines[1]
    local grouped = #cell.machines > 1
    local label = grouped and string.format("+%02d", #cell.machines)
      or string.format("%s%02d", state.mark, machine.number)
    label = cell.selected and ("[" .. label .. "]") or (" " .. label)
    local subtitle = grouped and "Group" or tileLabel(machine.name, tileWidth)
    local format = "%-" .. tileWidth .. "s"
    paint(gpu, cell.x, cell.y, string.format(format, label), state.color, state.ink)
    gpu.set(cell.x, cell.y + 1, string.format(format, subtitle))
  end
  if #view.markers == 0 then panelText(gpu, panel, 2, "No machines in map bounds", colors.muted) end
end

local function drawPager(gpu, panel, view, page, pages)
  if pages == 1 then return end
  local row, x = panel.y + panel.h - 1, panel.x + 1
  panelText(gpu, panel, panel.h - 1, string.format(" Page %d/%d", page, pages), colors.muted)
  if page > 1 then
    view.prev = button(gpu, x + 13, row, " < Prev ")
    view.prev.page = page - 1
  end
  if page < pages then
    view.next = button(gpu, x + 22, row, " Next > ")
    view.next.page = page + 1
  end
end

local function drawMachineList(gpu, panel, view, title, machines, selected, requestedPage, now)
  panelText(gpu, panel, 0, string.format("%s  (%d)", title, #machines))
  if #machines == 0 then panelText(gpu, panel, 2, "None to show", colors.muted) end
  local size = panel.h - 3
  local pages = math.max(1, math.ceil(#machines / size))
  local page = math.min(requestedPage, pages)
  local first = (page - 1) * size + 1
  local x, width = panel.x + 1, panel.w - 2
  for index = first, math.min(first + size - 1, #machines) do
    local machine = machines[index]
    local state = machineState(machine)
    local y = panel.y + 2 + index - first
    local suffix = state == offline and ("  " .. ageLabel(machine, now) .. " ago")
      or state == fault and ("  " .. machine.status.problems .. " issues") or ""
    if #suffix > width - 15 then suffix = "" end
    local nameWidth = width - 7 - #suffix
    local name = machine.name
    if #name > nameWidth then name = name:sub(1, nameWidth - 1) .. "~" end
    local prefix = string.format(" %s%02d ", state.mark, machine.number)
    paint(gpu, x, y, prefix, state.color, state.ink)
    local label = (machine == selected and "> " or "  ") .. string.format("%-" .. nameWidth .. "s", name) .. suffix
    paint(gpu, x + #prefix, y, label, machine == selected and colors.selected or colors.panel)
    view.rows[#view.rows + 1] = {x = x, y = y, w = width, h = 1, machine = machine}
  end
  drawPager(gpu, panel, view, page, pages)
end

local function drawPairing(gpu, panel, view, pairing, atLimit)
  panelText(gpu, panel, 0, "PAIR A NEW AGENT")
  if #pairing.offers == 0 then
    panelText(gpu, panel, 2, atLimit and "Central limit reached" or "Waiting for a new agent...")
  end
  local size = math.floor((panel.h - 4) / 2)
  local pages = math.max(1, math.ceil(#pairing.offers / size))
  local page = math.min(pairing.page, pages)
  local first = (page - 1) * size + 1
  local x, width = panel.x + 1, panel.w - 2
  for index = first, math.min(first + size - 1, #pairing.offers) do
    local offer = pairing.offers[index]
    local y = panel.y + 2 + 2 * (index - first)
    local prefix = offer.count > 1 and (" + [" .. offer.count .. "] ") or " + "
    local label = (prefix .. offer.name):sub(1, width)
    paint(gpu, x, y, label, colors.button)
    panelText(gpu, panel, y - panel.y + 1,
      string.format("   XYZ %d, %d, %d", offer.status.x, offer.status.y, offer.status.z), colors.muted)
    view.offers[#view.offers + 1] = {x = x, y = y, w = width, h = 2, offer = offer}
  end
  panelText(gpu, panel, panel.h - 2, pairing.message or "Touch an agent to pair", colors.muted)
  drawPager(gpu, panel, view, page, pages)
end

local function drawDetails(gpu, panel, view, selected, confirm, pending, now)
  if not selected then
    panelText(gpu, panel, 0, "MACHINE DETAILS")
    panelText(gpu, panel, 2, "Touch a machine to inspect it.", colors.muted)
    return
  end
  local status = selected.status
  local state = machineState(selected)
  local x, y, width = panel.x + 1, panel.y, panel.w - 2
  local title = string.format("%02d  %s", selected.number, selected.name)
  local cut = width
  if #title > width then
    local space = title:sub(1, width + 1):match("^.*() ")
    if space and #title - space <= width then cut = space end
    panelText(gpu, panel, 1, title:sub(cut + 1))
  end
  panelText(gpu, panel, 0, title:sub(1, cut))
  local stateLabel = " " .. state.mark .. " " .. state.label .. " "
  paint(gpu, x, y + 2, stateLabel, state.color, state.ink)
  local work = status.enabled and "Work enabled" or "Work disabled"
  local connection = state == offline and ("Last seen " .. ageLabel(selected, now) .. " ago") or work
  paint(gpu, x + #stateLabel + 1, y + 2, connection, nil, colors.muted)
  panelText(gpu, panel, 3, string.format("XYZ %d, %d, %d", status.x, status.y, status.z))
  panelText(gpu, panel, 4, "Agent: " .. selected.agent.name, colors.muted)
  local usage = status.usage and (status.usage .. " EU/t") or "--"
  panelText(gpu, panel, 5, (selected.online and "Usage: " or "Last usage: ") .. usage,
    not selected.online and colors.muted or nil)
  if status.maximum > 0 then
    local fraction = math.max(0, math.min(1, status.progress / status.maximum))
    local filled = math.floor(fraction * 12 + 0.5)
    panelText(gpu, panel, 6, string.format("Progress %3d%%  [%s%s]", math.floor(fraction * 100 + 0.5),
      string.rep("#", filled), string.rep("-", 12 - filled)))
  else
    panelText(gpu, panel, 6, "Progress --", colors.muted)
  end
  panelText(gpu, panel, 7, "Maintenance: " .. (status.problems and (status.problems .. " issues") or "unknown"))

  local commandRow = y + 8
  if pending and pending.machine == selected then
    panelText(gpu, panel, 8, "Awaiting agent confirmation...")
  elseif state == offline then
    panelText(gpu, panel, 8, "Offline - controls unavailable", colors.muted)
  elseif not status.control then
    panelText(gpu, panel, 8, "Agent is monitoring only", colors.muted)
  elseif pending then
    panelText(gpu, panel, 8, "Another command is pending", colors.muted)
  else
    local label = status.enabled and " Disable work " or " Enable work "
    if confirm then label = status.enabled and " Confirm disable " or " Confirm enable " end
    view.work = button(gpu, confirm and x + 17 or x, commandRow, label, confirm and disabled.color or nil,
      confirm and disabled.ink or nil, 2)
    view.work.machine, view.work.enabled, view.work.confirm = selected, not status.enabled, confirm
    if confirm then view.cancel = button(gpu, x, commandRow, " Cancel ", nil, nil, 2) end
  end
  if selected.message and not confirm then panelText(gpu, panel, 10, selected.message, colors.muted) end
end

local function drawRotationControls(gpu, view, ui)
  view.rotateLeft = button(gpu, 2, 3, " Rotate left ", nil, nil, 2)
  view.rotateRight = button(gpu, 16, 3, " Rotate right ", nil, nil, 2)
  view.resetRotation = button(gpu, 31, 3, " Reset ", nil, nil, 2)
  paint(gpu, 40, 3, string.format("Rotation: %d deg", ui.rotation), colors.background)
  if ui.rotationMessage then paint(gpu, 2, 5, ui.rotationMessage, colors.background, colors.muted) end
end

local function drawCentral(gpu, hall, machines, agentCount, ui, pending, pairing, now)
  local width, height = gpu.getViewport()
  local view = {markers = {}, offers = {}, rows = {}}
  gpu.setBackground(colors.background)
  gpu.setForeground(colors.text)
  gpu.fill(1, 1, width, height, " ")
  if width < 64 or height < 18 then
    gpu.set(1, 1, ("Factory Control needs a 64 x 18 viewport"):sub(1, width))
    return view
  end

  local counts, issues, online, inBounds = {}, {}, 0, 0
  for _, state in ipairs(states) do counts[state] = 0 end
  for _, machine in ipairs(machines) do
    local state = machineState(machine)
    counts[state] = counts[state] + 1
    if machine.online then online = online + 1 end
    if state == fault then issues[#issues + 1] = machine end
    if hall and hallPosition(hall, machine.status) then inBounds = inBounds + 1 end
  end
  for _, machine in ipairs(machines) do
    if not machine.online then issues[#issues + 1] = machine end
  end

  paint(gpu, 2, 1, "FACTORY CONTROL", colors.background)
  local summary = string.format("%d/%d online   %d agents", online, #machines, agentCount)
  paint(gpu, width - #summary, 1, summary, colors.background, colors.muted)
  local x = 2
  for _, state in ipairs(states) do
    local label = string.format(" %s%d %s ", state.mark, counts[state], state.short)
    paint(gpu, x, 2, label, state.color, state.ink)
    x = x + #label
  end

  local wide = width >= 100 and height >= 22
  local settingsOpen = ui.tab == "settings"
  local showDetail = ui.selected and ui.detail
  if settingsOpen then
    drawRotationControls(gpu, view, ui)
  else
    local issuesLabel = string.format("%-13s", " Issues (" .. #issues .. ") ")
    local buttons = {{"map", " Hall map "}, {"issues", issuesLabel}, {"machines", " Machines "},
      {"add", pairing and " Close pairing " or " Add agent "}}
    if not pairing and (ui.group or (not wide and showDetail)) then
      buttons[#buttons + 1] = {"back", " Back "}
    end
    x = 2
    for _, tab in ipairs(buttons) do
      local active = pairing and tab[1] == "add" or not pairing and tab[1] == ui.tab
      view[tab[1]] = button(gpu, x, 3, tab[2], active and colors.text or nil, active and colors.ink or nil, 2)
      x = x + #tab[2] + 1
    end
  end

  local main = {x = 2, y = 6, w = width - 2, h = height - 7}
  local side
  if wide and not pairing then
    local sideWidth = math.max(40, math.floor(width * 0.35))
    main.w = main.w - sideWidth - 1
    side = {x = main.x + main.w + 1, y = main.y, w = sideWidth, h = main.h}
  end
  gpu.setBackground(colors.panel)
  gpu.fill(main.x, main.y, main.w, main.h, " ")
  if side then gpu.fill(side.x, side.y, side.w, side.h, " ") end

  if pairing then
    drawPairing(gpu, main, view, pairing, agentCount >= machineLimit or #machines >= machineLimit)
  elseif settingsOpen then
    drawMap(gpu, main, hall, machines, ui.selected, view, ui.rotation)
    if side then
      panelText(gpu, side, 0, "HALL ORIENTATION")
      panelText(gpu, side, 2, "Rotate the map in 90-degree steps.", colors.muted)
    end
  else
    if side or (not ui.group and not showDetail) then
      if ui.tab == "map" then
        drawMap(gpu, main, hall, machines, ui.selected, view, ui.rotation)
      elseif ui.tab == "issues" then
        drawMachineList(gpu, main, view, "ISSUES", issues, ui.selected, ui.page, now)
      else
        drawMachineList(gpu, main, view, "MACHINES", machines, ui.selected, ui.page, now)
      end
    end
    if ui.group then
      drawMachineList(gpu, side or main, view, "MACHINES AT THIS TILE", ui.group.machines, ui.selected, ui.page, now)
    elseif side or showDetail then
      drawDetails(gpu, side or main, view, ui.selected, ui.confirm, pending, now)
    end
  end

  local footer = string.format("%d on map  |  %d outside bounds", inBounds, #machines - inBounds)
  paint(gpu, 2, height - 1, footer, colors.background, colors.muted)
  paint(gpu, 2, height, "Ctrl+C to exit", colors.background, colors.muted)
  view.settings = button(gpu, width - 10, height, settingsOpen and "    Done   " or " Settings  ")
  return view
end

local function canSetWork(machine, enabled, now)
  return machine.online and now - machine.lastSeen < offlineAfter
    and machine.status.control and machine.status.enabled ~= enabled
end

local function runCentral(settings, send, receive, statePath, gpu, screen, bounds)
  local hall, peers = bounds or settings.hall, settings.machines or {}
  assert(hall == nil or (type(hall) == "table" and isInteger(hall.originX) and isInteger(hall.originZ)
    and isInteger(hall.spanX) and hall.spanX ~= 0 and isInteger(hall.spanZ) and hall.spanZ ~= 0),
    "Set central.hall originX, originZ and nonzero spanX and spanZ")
  assert(type(peers) == "table", "Set central.machines to a modem address -> label table")
  local machines, agents, agentCount = {}, {}, 0
  local function addAgent(address, name)
    assert(agentCount < machineLimit, "Central agent limit reached")
    assert(isAddress(address) and isLabel(name),
      "Each central agent entry needs a full modem address and a plain-text label")
    agents[address] = {address = address, name = name, machines = {}}
    agentCount = agentCount + 1
  end
  for address, name in pairs(peers) do addAgent(address, name) end
  if filesystem.exists(statePath) then
    for address in filesystem.list(statePath) do
      if isAddress(address) and not agents[address] then
        addAgent(address, readFile(filesystem.concat(statePath, address), "*l"))
      end
    end
  end

  local rotationPath = filesystem.concat(statePath, "hall-rotation")
  local ui = {tab = "map", page = 1, rotation = 0}
  if filesystem.exists(rotationPath) then
    local ok, value = pcall(readFile, rotationPath, "*l")
    local rotation = ok and tonumber(value)
    if rotation and hallAxes[rotation] then
      ui.rotation = rotation
    else
      ui.rotationMessage = "Saved rotation unavailable. Using 0 deg."
    end
  end
  local pending, view, pairing
  local dirty, counter, redrawAt, ageAt = true, 0, 0, 0
  local function updateMachine(agent, controller, name, payload)
    local key = controller or ""
    local machine = agent.machines[key]
    if machine and machine.payload and machine.payload == payload and machine.name == name then
      if not machine.online then dirty = true end
      machine.online, machine.lastSeen = true, computer.uptime()
      return
    end
    local status = decodeStatus(payload)
    if not status then return end
    local single = controller == nil
    -- Replace the old records if a paired agent switches between legacy and multi-machine mode.
    if agent.single ~= nil and agent.single ~= single then
      if ui.selected and ui.selected.agent == agent then ui.selected, ui.confirm = nil, nil end
      if ui.group then ui.group, ui.page = nil, 1 end
      if pending and pending.machine.agent == agent then pending = nil end
      for index = #machines, 1, -1 do
        if machines[index].agent == agent then table.remove(machines, index) end
      end
      for index, machine in ipairs(machines) do machine.number = index end
      agent.machines = {}
      dirty = true
    end
    agent.single = single
    if not machine then
      if #machines >= machineLimit then return end
      machine = {agent = agent, controller = controller, number = #machines + 1}
      machines[#machines + 1] = machine
      agent.machines[key] = machine
    end
    machine.name, machine.status, machine.online, machine.lastSeen = name, status, true, computer.uptime()
    machine.payload = payload
    dirty = true
  end

  while true do
    local now = computer.uptime()
    if pairing and now >= pairing.deadline then
      pairing, dirty = nil, true
    elseif pairing then
      for index = #pairing.offers, 1, -1 do
        if now - pairing.offers[index].lastSeen >= offlineAfter then
          table.remove(pairing.offers, index)
          dirty = true
        end
      end
    end
    local hasOffline = false
    for _, machine in ipairs(machines) do
      if machine.online and now - machine.lastSeen >= offlineAfter then
        machine.online = false
        dirty = true
      end
      if not machine.online then hasOffline = true end
    end
    if ui.confirm and (now >= ui.confirm.deadline or not canSetWork(ui.confirm.machine, ui.confirm.enabled, now)) then
      ui.confirm, dirty = nil, true
    end
    if pending and now >= pending.deadline then
      pending.machine.message = "Command timed out"
      pending, dirty = nil, true
    end
    local showingAges = hasOffline and not pairing and ui.tab ~= "settings"
      and (ui.tab ~= "map" or ui.group or (ui.selected and not ui.selected.online))
    if showingAges and now >= ageAt then dirty = true end
    if dirty and now >= redrawAt then
      view = drawCentral(gpu, hall or fitHall(machines), machines, agentCount, ui, pending, pairing, now)
      dirty = false
      redrawAt = computer.uptime() + redrawInterval
      ageAt = now + 5
    end

    local timeout = dirty and math.max(0, math.min(0.5, redrawAt - computer.uptime())) or 0.5
    local signal, sender, kind, data, extra, payload, count = receive(timeout)
    local agent = agents[sender]
    if signal == "interrupted" then return end
    if signal == "touch" and sender == screen and extra == 0 then
      local x, y = kind, data
      redrawAt = 0
      local tab = contains(view.map, x, y) and "map" or contains(view.issues, x, y) and "issues"
        or contains(view.machines, x, y) and "machines"
      if contains(view.settings, x, y) then
        pairing = nil
        ui.tab = ui.tab == "settings" and "map" or "settings"
        ui.page, ui.group, ui.detail, ui.confirm = 1, nil, nil, nil
        dirty = true
      elseif ui.tab == "settings" then
        local rotation = contains(view.rotateLeft, x, y) and (ui.rotation + 270) % 360
          or contains(view.rotateRight, x, y) and (ui.rotation + 90) % 360
          or contains(view.resetRotation, x, y) and 0
        if rotation then
          local saved = pcall(writeFile, rotationPath, rotation .. "\n")
          ui.rotation = rotation
          ui.rotationMessage = not saved and "Rotation applied. Could not save to disk." or nil
          dirty = true
        end
      elseif tab then
        pairing = nil
        ui.tab, ui.page, ui.group, ui.detail, ui.confirm = tab, 1, nil, nil, nil
        dirty = true
      elseif contains(view.add, x, y) then
        ui.confirm = nil
        if pairing then
          pairing = nil
        else
          pairing = {offers = {}, page = 1, deadline = computer.uptime() + pairingWindow}
        end
        dirty = true
      elseif contains(view.back, x, y) then
        ui.group, ui.detail, ui.confirm = nil, nil, nil
        if ui.tab == "map" then ui.page = 1 end
        dirty = true
      elseif contains(view.prev, x, y) or contains(view.next, x, y) then
        local target = contains(view.prev, x, y) and view.prev or view.next
        if pairing then pairing.page = target.page else ui.page = target.page end
        dirty = true
      elseif pairing then
        local target = touched(view.offers, x, y)
        if target and computer.uptime() - target.offer.lastSeen < offlineAfter
            and agentCount < machineLimit and #machines < machineLimit then
          local offer = target.offer
          local saved, reason = pcall(savePair, filesystem.concat(statePath, offer.address), offer.name)
          if saved then
            addAgent(offer.address, offer.name)
            for index, candidate in ipairs(pairing.offers) do
              if candidate == offer then
                table.remove(pairing.offers, index)
                break
              end
            end
            send(offer.address, "pair", offer.token)
            pairing.message = "Added. Waiting for status."
          else
            pairing.message = "Save failed: " .. tostring(reason)
          end
          dirty = true
        end
      elseif contains(view.cancel, x, y) then
        ui.confirm, dirty = nil, true
      elseif contains(view.work, x, y) then
        now = computer.uptime()
        local machine, enabled = view.work.machine, view.work.enabled
        if machine == ui.selected and not pending and ui.confirm == view.work.confirm
            and canSetWork(machine, enabled, now) then
          if not ui.confirm then
            ui.confirm = {machine = machine, enabled = enabled, deadline = now + 8}
            machine.message = nil
          elseif now < ui.confirm.deadline then
            ui.confirm = nil
            counter = counter + 1
            local id = string.format("%.3f-%d", now, counter)
            local sent
            if machine.controller then
              sent = send(machine.agent.address, "set-machine", id, machine.controller, enabled)
            else
              sent = send(machine.agent.address, "set-work", id, enabled)
            end
            if sent then
              pending = {machine = machine, id = id, enabled = enabled, deadline = now + commandTimeout}
            else
              machine.message = "Could not send command"
            end
          end
        end
        dirty = true
      else
        local cell = touched(view.markers, x, y)
        local row = touched(view.rows, x, y)
        if cell and #cell.machines > 1 then
          ui.group, ui.detail, ui.confirm, ui.page, dirty = cell, nil, nil, 1, true
        else
          local machine = row and row.machine or cell and cell.machines[1]
          if machine and machine.agent.machines[machine.controller or ""] == machine then
            ui.selected, ui.detail, ui.group, ui.confirm, dirty = machine, true, nil, nil, true
          end
        end
      end
    elseif signal == "screen_resized" and sender == screen then
      ui.confirm = nil
      if ui.group then ui.group, ui.page = nil, 1 end
      dirty, redrawAt = true, 0
    elseif signal == "modem_message" and kind == "hello" and isAddress(sender) and isAddress(data)
        and isLabel(extra) and #extra <= 64 then
      local status = decodeStatus(payload)
      if status and agent then
        -- If the first reply was lost, an approved agent can repeat its hello.
        send(sender, "pair", data)
      elseif status and pairing and agentCount < machineLimit and #machines < machineLimit then
        local offer
        for _, candidate in ipairs(pairing.offers) do
          if candidate.address == sender then offer = candidate; break end
        end
        if not offer and #pairing.offers < 16 then
          offer = {address = sender}
          pairing.offers[#pairing.offers + 1] = offer
        end
        if offer then
          offer.token, offer.name, offer.status, offer.lastSeen = data, extra, status, computer.uptime()
          offer.count = isInteger(count) and count > 0 and count <= 65535 and count or 1
          dirty = true
        end
      end
    elseif signal == "modem_message" and agent then
      if kind == "status" then
        updateMachine(agent, nil, agent.name, data)
      elseif kind == "machine-status" and isAddress(data) and isLabel(extra) and #extra <= 64 then
        updateMachine(agent, data, extra, payload)
      elseif pending and pending.machine.agent == agent and pending.id == data then
        local machine = pending.machine
        local applied
        if kind == "result" and not machine.controller then
          applied = extra
        elseif kind == "machine-result" and machine.controller and machine.controller == extra then
          applied = payload
        end
        if type(applied) == "boolean" then
          if applied then
            machine.status.enabled = pending.enabled
            machine.payload = nil
          end
          machine.message = applied and "Work setting confirmed" or "Work setting unconfirmed"
          pending, dirty = nil, true
        end
      end
    end
  end
end

local function serviceEnabled()
  local config = {}
  assert(loadfile("/etc/rc.cfg", "t", config))()
  for _, name in ipairs(config.enabled or {}) do
    if name == "factory-control" then return true end
  end
  return false
end

local function scriptPath()
  -- OpenOS's lua launcher names the chunk with '=' followed by its filename.
  local source = debug.getinfo(scriptPath, "S").source:match("^[@=](.+)$")
  local program = shell.resolve(assert(source, "Run autostart setup from a script file"))
  assert(filesystem.exists(program), "Cannot find the Factory Control script at " .. program)
  return program
end

local function enableAgentService(configPath, requireConfig, central)
  local program = scriptPath()
  local servicePath = "/etc/rc.d/factory-control.lua"
  local serviceCode = string.format([=[
local thread = require("thread")
local program = %q
local configPath = %q
local session, worker

function start()
  if worker and worker:status() ~= "dead" then return end
  session = {requireConfig = %s, central = %q}
  worker = thread.create(assert(loadfile(program)), "agent-control", configPath, session)
  assert(worker:status() ~= "dead", "Factory Control agent exited during startup")
  assert(worker:detach())
end

function stop()
  if worker and worker:status() ~= "dead" then
    session.stopping = true
    assert(worker:join(10))
  end
  session, worker = nil, nil
end
]=], program, configPath, tostring(requireConfig), central)

  if filesystem.exists(servicePath) then
    assert(readFile(servicePath, "*a") == serviceCode,
      "Existing service uses a different setup. Stop and disable it before removing " .. servicePath)
  else
    writeFile(servicePath, serviceCode)
  end
  if not serviceEnabled() then
    assert(loadfile("/bin/rc.lua"))("factory-control", "enable")
    assert(serviceEnabled(), "Could not enable the Factory Control service")
  end
  print("Factory Control agent-control will start at boot. Run rc factory-control start to start it now.")
end

local centralLauncher = "/etc/factory-control-central.lua"
local centralLauncherHeader = "-- Factory Control central startup\n"

local function setCentralStartup(enabled)
  local path = "/home/.shrc"
  local old = ""
  if filesystem.exists(path) then
    path = assert(filesystem.realPath(path))
    old = assert(readFile(path, "*a"))
  end
  local hook = "lua " .. centralLauncher
  local found = false
  local updated = old:gsub("([^\n]+)(\n?)", function(line, newline)
    if line:gsub("\r$", "") == hook then
      local keep = enabled and not found
      found = true
      if not keep then return "" end
    end
    return line .. newline
  end)
  if enabled and not found then
    local separator = old ~= "" and old:sub(-1) ~= "\n" and "\n" or ""
    updated = old .. separator .. hook .. "\n"
  end
  if updated ~= old then writeFile(path, updated) end
end

local function enableCentralStartup(configPath, requireConfig, hall)
  local bounds = hall and string.format("{originX=%.0f, originZ=%.0f, spanX=%.0f, spanZ=%.0f}",
    hall.originX, hall.originZ, hall.spanX, hall.spanZ) or "nil"
  local code = centralLauncherHeader .. string.format([=[
local bootKey = "factory-control.central.started"
if package.loaded[bootKey] then return end
local program = assert(loadfile(%q))
package.loaded[bootKey] = true
program("central", %q, {requireConfig = %s, hall = %s})
]=], scriptPath(), configPath, tostring(requireConfig), bounds)
  local old
  if filesystem.exists(centralLauncher) then
    old = assert(readFile(centralLauncher, "*a"))
    assert(old:sub(1, #centralLauncherHeader) == centralLauncherHeader,
      "Another file already exists at " .. centralLauncher)
  end
  if code ~= old then writeFile(centralLauncher, code) end
  setCentralStartup(true)
  print("Factory Control central will open on its screen at boot.")
end

local role, first, second, third, extra = ...
local requestControl = role == "agent-control"
local installService = role == "agent-autostart"
local installCentral = role == "central-autostart"
if installCentral or role == "dashboard" then role = "central" end
-- Generated launchers pass local options alongside an absolute config path.
local launch = (requestControl or role == "central") and type(second) == "table" and second or nil
local service = requestControl and launch or nil
if launch then second = nil end
if requestControl or installService then role = "agent" end
if extra or (role ~= "agent" and role ~= "central") or (role == "agent" and second) then
  print("Usage: lua factory-control.lua agent|agent-control|agent-autostart [config.lua]")
  print("       lua factory-control.lua -- central|central-autostart [X1,Z1 X2,Z2] [config.lua]")
  print("       lua factory-control.lua central-autostart off")
  return
end

local function main()
  if installCentral and first == "off" and second == nil then
    setCentralStartup(false)
    print("Factory Control central autostart disabled.")
    return
  end
  local configPath, hall = first, launch and launch.hall
  if second then
    local left, top = parseCorner(first)
    local right, bottom = parseCorner(second)
    assert(left and right and ((top == nil) == (bottom == nil)), "Use two X,Z corners or two integers for a square")
    top, bottom = top or left, bottom or right
    assert(left ~= right and top ~= bottom, "Hall corners must differ on both X and Z")
    hall = {originX = left, originZ = top, spanX = right - left, spanZ = bottom - top}
    configPath = third
  elseif role == "central" and parseCorner(first) then
    error("Specify both hall corners", 0)
  end
  local path = shell.resolve(configPath or "config.lua")
  local config = {}
  local requireConfig = configPath ~= nil and (not launch or launch.requireConfig)
  if requireConfig or filesystem.exists(path) then
    config = assert(loadfile(path))()
    assert(type(config) == "table", "Config must return a table")
  end
  local port = config.port == nil and 34173 or config.port
  local settings = config[role]
  if settings == nil and role == "central" then settings = config.dashboard end
  if settings == nil then settings = {} end
  assert(type(settings) == "table", "Invalid " .. role .. " config")
  -- Keep the original state filename so existing central pairings are reused.
  local stateRole = role == "central" and "dashboard" or role
  local statePath = filesystem.concat(filesystem.path(path), "state", filesystem.name(path) .. "." .. stateRole)
  if installService then
    local central = assert(pairedCentral(settings, statePath),
      "Pair this computer in agent mode before running agent-autostart")
    enableAgentService(path, requireConfig, central)
    return
  end
  if installCentral then
    enableCentralStartup(path, requireConfig, hall)
    return
  end
  assert(isInteger(port) and port >= 1 and port <= 65535, "Set port to an integer from 1 to 65535")
  local modem
  if config.modem then
    modem = assert(component.proxy(config.modem))
  else
    for address in component.list("modem", true) do
      local candidate = component.proxy(address)
      if candidate and candidate.isWireless() then
        assert(not modem, "Multiple wireless modems found. Set modem in config.lua.")
        modem = candidate
      end
    end
  end
  assert(modem and modem.isWireless() and modem.getStrength() > 0,
    "Connect a wireless modem with positive signal strength")

  local function send(address, kind, ...)
    local ok, sent
    if address then
      ok, sent = pcall(modem.send, address, port, protocol, kind, ...)
    else
      ok, sent = pcall(modem.broadcast, port, protocol, kind, ...)
    end
    return ok and sent == true
  end

  local function receive(timeout)
    if service then
      if service.stopping then return "interrupted" end
      timeout = math.min(timeout, 0.5)
    end
    local signal, first, second, third, fourth, fifth, kind, data, extra, payload, count = event.pull(timeout)
    if service then
      if service.stopping then return "interrupted" end
      if signal == "interrupted" then return end
    end
    if signal == "modem_message" then
      if first == modem.address and third == port and fifth == protocol then
        return signal, second, kind, data, extra, payload, count
      end
      return
    end
    return signal, first, second, third, fourth
  end

  local gpu, screen, foreground, fgPalette, background, bgPalette
  if role == "central" then
    local term = require("term")
    assert(term.isAvailable(), "Connect a graphics card and touchscreen to central")
    gpu = term.gpu()
    screen = gpu.getScreen()
    foreground, fgPalette = gpu.getForeground()
    background, bgPalette = gpu.getBackground()
  end

  assert(modem.open(port), "Port is already open on this modem. Stop the other program or change port.")
  local ok, reason
  if role == "agent" then
    ok, reason = pcall(runAgent, settings, send, receive, statePath, requestControl, service)
  else
    ok, reason = pcall(runCentral, settings, send, receive, statePath, gpu, screen, hall)
  end
  pcall(modem.close, port)
  if gpu then
    pcall(gpu.setForeground, foreground, fgPalette)
    pcall(gpu.setBackground, background, bgPalette)
    pcall(require("term").clear)
  end
  if not ok then error(reason, 0) end
end

local ok, reason = pcall(main)
if not ok then
  if service then error(reason, 0) end
  io.stderr:write(tostring(reason) .. "\n")
end
