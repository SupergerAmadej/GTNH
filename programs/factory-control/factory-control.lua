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

local function readPair(path)
  local file = assert(io.open(path, "r"))
  local value = file:read("*l")
  file:close()
  return value
end

local function savePair(path, value)
  local directory = filesystem.path(path)
  if not filesystem.exists(directory) then assert(filesystem.makeDirectory(directory)) end
  if filesystem.exists(path) then
    assert(readPair(path) == value, "A different pairing is already saved")
    return
  end
  -- Keep incomplete writes separate from valid pairings.
  local temporary = path .. ".tmp"
  local file = assert(io.open(temporary, "w"))
  local written, writeError = file:write(value, "\n")
  local flushed, flushError = file:flush()
  file:close()
  assert(written and flushed, writeError or flushError)
  assert(filesystem.rename(temporary, path))
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

local function runAgent(settings, send, receive, statePath, requestControl)
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
  local pinnedCentral = settings.centralModem
  if pinnedCentral == nil then pinnedCentral = settings.dashboardModem end
  local central = pinnedCentral
  if central == nil and filesystem.exists(statePath) then central = readPair(statePath) or "" end
  assert(central == nil or isAddress(central), "Invalid central modem address in config or pairing state")
  assert(not requestControl or central, "Pair this computer in agent mode before running agent-control")
  -- Require a local opt-in tied to an already known central modem.
  local allowControl = requestControl or (settings.allowControl == true and pinnedCentral ~= nil)
  local token
  local label = settings.name
  assert(label == nil or (isLabel(label) and #label <= 64), "Set agent.name to a label of up to 64 characters")
  if not central then
    token = require("uuid").next()
    print("Open Add agent on central. Ctrl+C to exit.")
  else
    local mode = allowControl and "Machine control enabled" or "Monitoring only"
    print("Factory agent paired to " .. central .. ". " .. mode .. ". Ctrl+C to exit.")
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
  background = 0x101820, panel = 0x1C2935, text = 0xF1F5F9,
  fault = 0x9E2731, operating = 0x17643D, standby = 0x205496, offline = 0x52616D,
}

local function machineState(machine)
  local status = machine.status
  if not machine.online then return "OFFLINE", colors.offline end
  if status.problems and status.problems > 0 then return "MAINTENANCE", colors.fault end
  if status.active then return "OPERATING", colors.operating end
  if not status.enabled then return "DISABLED", colors.offline end
  return "STANDBY", colors.standby
end

local function contains(rect, x, y)
  return rect and x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h
end

local function touched(targets, x, y)
  for index = #targets, 1, -1 do
    if contains(targets[index], x, y) then return targets[index] end
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

local function drawCentral(gpu, hall, machines, agentCount, selected, pending, pairing, listPage)
  local width, height = gpu.getViewport()
  local view = {markers = {}, offers = {}, rows = {}}
  gpu.setBackground(colors.background)
  gpu.setForeground(colors.text)
  gpu.fill(1, 1, width, height, " ")
  if width < 64 or height < 18 then
    gpu.set(1, 1, ("Factory Control needs a 64 x 18 viewport"):sub(1, width))
    return view
  end

  local divider = math.floor(width * 0.55)
  local detailX = divider + 3
  local detailWidth = width - detailX
  local function detail(row, line)
    gpu.set(detailX, row, line:sub(1, detailWidth))
  end

  gpu.set(2, 1, "FACTORY CONTROL  |  HALL MAP")
  local right = hall and hall.spanX < 0 and "west" or "east"
  local down = hall and hall.spanZ < 0 and "north" or "south"
  gpu.set(2, 2, "X " .. right .. " >  Z " .. down .. " v")
  local addLabel = pairing and " Close pairing " or " Add agent "
  local listLabel = listPage and " Back " or " Machines "
  gpu.setBackground(colors.standby)
  detail(2, addLabel)
  view.add = {x = detailX, y = 2, w = #addLabel, h = 1}
  local listX = detailX + #addLabel + 1
  gpu.set(listX, 2, listLabel)
  view.list = {x = listX, y = 2, w = #listLabel, h = 1}
  gpu.setBackground(colors.panel)
  gpu.fill(2, 4, divider - 2, height - 7, " ")
  gpu.fill(divider + 2, 4, width - divider - 2, height - 7, " ")
  local visible, online = 0, 0
  local function drawMarker(machine)
    local status = machine.status
    if machine.online then online = online + 1 end
    if status then
      local x = (status.x - hall.originX) / hall.spanX
      local z = (status.z - hall.originZ) / hall.spanZ
      if x >= 0 and x <= 1 and z >= 0 and z <= 1 then
        local rect = {x = 3 + math.floor(x * (divider - 7)), y = 5 + math.floor(z * (height - 10)),
          w = 4, h = 2, machine = machine}
        local _, color = machineState(machine)
        gpu.setBackground(color)
        gpu.fill(rect.x, rect.y, rect.w, rect.h, " ")
        local label = string.format("%2d", machine.number)
        gpu.set(rect.x, rect.y, machine == selected and "[" .. label .. "]" or " " .. label .. " ")
        view.markers[#view.markers + 1] = rect
        visible = visible + 1
      end
    end
  end
  for _, machine in ipairs(machines) do
    if machine ~= selected then drawMarker(machine) end
  end
  if selected then drawMarker(selected) end

  gpu.setBackground(colors.panel)
  if visible == 0 then gpu.set(3, 5, "No machines in map bounds") end
  if pairing then
    detail(5, "PAIR A NEW AGENT")
    if #pairing.offers == 0 then
      detail(7, (agentCount >= machineLimit or #machines >= machineLimit)
        and "Central limit reached" or "Waiting for a new agent...")
    end
    for index, offer in ipairs(pairing.offers) do
      local row = 7 + 2 * (index - 1)
      if row + 1 >= height - 4 then break end
      gpu.setBackground(colors.standby)
      local prefix = offer.count > 1 and (" + [" .. offer.count .. "] ") or " + "
      detail(row, prefix .. offer.name)
      detail(row + 1, string.format(" XYZ %d, %d, %d", offer.status.x, offer.status.y, offer.status.z))
      view.offers[index] = {x = detailX, y = row, w = detailWidth, h = 2, offer = offer}
    end
    gpu.setBackground(colors.panel)
    detail(height - 4, pairing.message or "Touch an agent to pair")
  elseif listPage then
    detail(5, "MACHINES")
    if #machines == 0 then detail(7, "Waiting for machine status") end
    local pageSize = height - 11
    local pages = math.max(1, math.ceil(#machines / pageSize))
    local page = math.min(listPage, pages)
    local first = (page - 1) * pageSize + 1
    for index = first, math.min(#machines, first + pageSize - 1) do
      local machine = machines[index]
      local row = index - first + 7
      local _, color = machineState(machine)
      gpu.setBackground(color)
      detail(row, string.format("%02d  %s", machine.number, machine.name))
      view.rows[#view.rows + 1] = {x = detailX, y = row, w = detailWidth, h = 1, machine = machine}
    end
    if pages > 1 then
      local nextLabel = string.format(" Page %d/%d  Next > ", page, pages)
      gpu.setBackground(colors.standby)
      detail(height - 4, nextLabel)
      view.next = {x = detailX, y = height - 4, w = #nextLabel, h = 1, page = page % pages + 1}
    end
  elseif selected and selected.status then
    local status = selected.status
    local state = machineState(selected)
    local title = string.format("%02d  %s", selected.number, selected.name)
    detail(5, #title <= detailWidth and title or selected.name)
    detail(6, state .. (selected.online and "" or " (last reading)"))
    detail(7, string.format("XYZ %d, %d, %d", status.x, status.y, status.z))
    detail(8, "Work " .. (status.enabled and "enabled" or "disabled"))
    detail(9, "Maintenance " .. (status.problems and (status.problems .. " problems") or "unknown"))
    detail(10, "Progress " .. (status.maximum > 0
      and string.format("%.0f%%", 100 * status.progress / status.maximum) or "--"))
    detail(11, "Usage " .. (status.usage and (status.usage .. " EU/t") or "--"))
    if selected.controller then detail(12, "Agent " .. selected.agent.name) end
    if pending and pending.machine == selected then
      detail(13, "Pending confirmation...")
    elseif selected.online and status.control and not pending then
      local label = status.enabled and " Disable work " or " Enable work "
      gpu.setBackground(colors.standby)
      detail(13, label)
      view.work = {x = detailX, y = 13, w = #label, h = 1, enabled = not status.enabled}
    elseif not status.control then
      detail(13, "Remote control disabled")
    end
    gpu.setBackground(colors.panel)
    detail(14, selected.message or "")
  else
    detail(5, "Touch a machine square")
    detail(6, "to see its details.")
  end

  gpu.setBackground(colors.background)
  gpu.set(2, height - 2, "Red maintenance | Green running | Blue standby | Gray inactive")
  gpu.set(2, height - 1, string.format("%d/%d machines online | %d agents paired | %d on map",
    online, #machines, agentCount, visible))
  gpu.set(2, height, "Ctrl+C to exit")
  return view
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
        addAgent(address, readPair(filesystem.concat(statePath, address)))
      end
    end
  end

  local selected, pending, view, pairing, listPage
  local dirty, counter, redrawAt = true, 0, 0
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
      if selected and selected.agent == agent then selected = nil end
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
    for _, machine in ipairs(machines) do
      if machine.online and now - machine.lastSeen >= offlineAfter then
        machine.online = false
        dirty = true
      end
    end
    if pending and now >= pending.deadline then
      pending.machine.message = "Command timed out"
      pending, dirty = nil, true
    end
    if dirty and now >= redrawAt then
      view = drawCentral(gpu, hall or fitHall(machines), machines, agentCount, selected, pending, pairing, listPage)
      dirty = false
      redrawAt = computer.uptime() + redrawInterval
    end

    local timeout = dirty and math.max(0, math.min(0.5, redrawAt - computer.uptime())) or 0.5
    local signal, sender, kind, data, extra, payload, count = receive(timeout)
    local agent = agents[sender]
    if signal == "interrupted" then return end
    if signal == "touch" and sender == screen and extra == 0 then
      local x, y = kind, data
      redrawAt = 0
      if contains(view.add, x, y) then
        if pairing then
          pairing = nil
        else
          listPage = nil
          pairing = {offers = {}, deadline = computer.uptime() + pairingWindow}
        end
        dirty = true
      elseif contains(view.list, x, y) then
        pairing = nil
        if listPage then listPage = nil else listPage = 1 end
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
      elseif contains(view.work, x, y) and selected and selected.online and not pending then
        now = computer.uptime()
        counter = counter + 1
        local id = string.format("%.3f-%d", now, counter)
        local sent
        if selected.controller then
          sent = send(selected.agent.address, "set-machine", id, selected.controller, view.work.enabled)
        else
          sent = send(selected.agent.address, "set-work", id, view.work.enabled)
        end
        if sent then
          pending = {machine = selected, id = id, enabled = view.work.enabled, deadline = now + commandTimeout}
          selected.message = nil
        else
          selected.message = "Could not send command"
        end
        dirty = true
      elseif contains(view.next, x, y) then
        listPage, dirty = view.next.page, true
      else
        local target = touched(view.rows, x, y) or touched(view.markers, x, y)
        if target and target.machine.agent.machines[target.machine.controller or ""] == target.machine then
          selected, listPage, dirty = target.machine, nil, true
        end
      end
    elseif signal == "screen_resized" and sender == screen then
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

local role, first, second, third, extra = ...
local requestControl = role == "agent-control"
if requestControl then role = "agent" end
if role == "dashboard" then role = "central" end
if extra or (role ~= "agent" and role ~= "central") or (role == "agent" and second) then
  print("Usage: lua factory-control.lua agent|agent-control [config.lua]")
  print("       lua factory-control.lua -- central [X1,Z1 X2,Z2] [config.lua]")
  return
end

local function main()
  local configPath, hall = first, nil
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
  if configPath or filesystem.exists(path) then
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
    local signal, first, second, third, fourth, fifth, kind, data, extra, payload, count = event.pull(timeout)
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
    ok, reason = pcall(runAgent, settings, send, receive, statePath, requestControl)
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
if not ok then io.stderr:write(tostring(reason) .. "\n") end
