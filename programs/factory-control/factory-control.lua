local component = require("component")
local computer = require("computer")
local event = require("event")

local protocol = "factory-control/1"
local sampleInterval = 3
local offlineAfter = 10
local commandTimeout = 6

local function isInteger(value)
  return type(value) == "number" and math.abs(value) < math.huge and value % 1 == 0
end

local function isAddress(value)
  return type(value) == "string" and #value == 36
    and value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x+$")
end

local function readScanner(address)
  local ok, lines = pcall(component.invoke, address, "getSensorInformation")
  local problems, usage
  if ok and type(lines) == "table" then
    for _, line in ipairs(lines) do
      if type(line) == "string" then
        local plain = line:gsub("§[0-9a-fk-orA-FK-OR]", "")
        problems = tonumber(plain:match("^Problems:%s*(%d+)%s*$")) or problems
        usage = plain:match("^Currently uses:%s*([%d.,eE+%-]+)%s*EU/t%s*$") or usage
      end
    end
  end
  return problems, usage
end

local function readMachine(address, allowControl)
  local machine = component.proxy(address)
  local x, y, z = machine.getCoordinates()
  assert(isInteger(x) and isInteger(y) and isInteger(z), "Controller coordinates unavailable")
  local active, enabled = machine.isMachineActive(), machine.isWorkAllowed()
  local progress, maximum = machine.getWorkProgress(), machine.getWorkMaxProgress()
  assert(type(active) == "boolean" and type(enabled) == "boolean"
    and isInteger(progress) and isInteger(maximum), "Controller state unavailable")
  local problems, usage = readScanner(address)
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
  local x, y, z = tonumber(fields[1]), tonumber(fields[2]), tonumber(fields[3])
  local progress, maximum = tonumber(fields[6]), tonumber(fields[7])
  local problems = tonumber(fields[8])
  if not (isInteger(x) and isInteger(y) and isInteger(z) and isInteger(progress) and isInteger(maximum)) then return end
  for _, index in ipairs({4, 5, 10}) do
    if fields[index] ~= "0" and fields[index] ~= "1" then return end
  end
  if fields[8] ~= "" and not (isInteger(problems) and problems >= 0) then return end
  if fields[9] ~= "" and not fields[9]:match("^[%d.,eE+%-]+$") then return end
  return {
    x = x, y = y, z = z, active = fields[4] == "1", enabled = fields[5] == "1",
    progress = progress, maximum = maximum, problems = problems,
    usage = fields[9] ~= "" and fields[9] or nil, control = fields[10] == "1",
  }
end

local function runAgent(settings, send, receive)
  local address, dashboard = settings.controller, settings.dashboardModem
  assert(isAddress(address), "Set agent.controller to the controller's full component address")
  assert(isAddress(dashboard), "Set agent.dashboardModem to the dashboard's full modem address")
  local allowControl = settings.allowControl == true
  local nextSample = 0
  local pending, lastError
  print("Factory agent running. Ctrl+C to exit.")
  while true do
    local now = computer.uptime()
    if pending and now >= pending.checkAt then
      local ok, enabled = pcall(component.invoke, address, "isWorkAllowed")
      local applied = ok and enabled == pending.enabled
      if applied or now >= pending.deadline then
        send(dashboard, "result", pending.id, applied)
        pending = nil
        nextSample = now
      else
        pending.checkAt = now + 0.25
      end
    end
    if now >= nextSample then
      local ok, payload = pcall(readMachine, address, allowControl)
      if ok then
        if not send(dashboard, "status", payload) then
          ok, payload = false, "Could not send status. Check the wireless card and power."
        end
      end
      if not ok and payload ~= lastError then print(tostring(payload)) end
      lastError = not ok and payload or nil
      nextSample = now + sampleInterval
    end

    local wakeAt = pending and math.min(nextSample, pending.checkAt) or nextSample
    local signal, sender, kind, id, enabled = receive(math.max(0, wakeAt - computer.uptime()))
    if signal == "interrupted" then return end
    if sender == dashboard and kind == "set-work" and type(id) == "string" and #id <= 64
        and type(enabled) == "boolean" and (not pending or id ~= pending.id) then
      if allowControl and not pending and pcall(component.invoke, address, "setWorkAllowed", enabled) then
        now = computer.uptime()
        pending = {id = id, enabled = enabled, checkAt = now + 0.25, deadline = now + 3}
      else
        send(dashboard, "result", id, false)
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

local function drawDashboard(gpu, hall, machines, selected, pending)
  local width, height = gpu.getViewport()
  local markers, button = {}, nil
  gpu.setBackground(colors.background)
  gpu.setForeground(colors.text)
  gpu.fill(1, 1, width, height, " ")
  if width < 64 or height < 18 then
    gpu.set(1, 1, ("Factory Control needs a 64 x 18 viewport"):sub(1, width))
    return markers, button
  end

  local divider = math.floor(width * 0.55)
  local detailX = divider + 3
  local detailWidth = width - detailX
  local function detail(row, line)
    gpu.set(detailX, row, line:sub(1, detailWidth))
  end

  gpu.set(2, 1, "FACTORY CONTROL  |  HALL MAP")
  gpu.set(2, 2, "X east >  Z south v")
  gpu.setBackground(colors.panel)
  gpu.fill(2, 4, divider - 2, height - 7, " ")
  gpu.fill(divider + 2, 4, width - divider - 2, height - 7, " ")
  local visible, online = 0, 0
  for _, machine in ipairs(machines) do
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
        markers[#markers + 1] = rect
        visible = visible + 1
      end
    end
  end

  gpu.setBackground(colors.panel)
  if visible == 0 then gpu.set(3, 5, "No machines in map bounds") end
  if selected and selected.status then
    local status = selected.status
    local state = machineState(selected)
    detail(5, string.format("%02d  %s", selected.number, selected.name))
    detail(6, state .. (selected.online and "" or " (last reading)"))
    detail(7, string.format("XYZ %d, %d, %d", status.x, status.y, status.z))
    detail(8, "Work " .. (status.enabled and "enabled" or "disabled"))
    detail(9, "Maintenance " .. (status.problems and (status.problems .. " problems") or "unknown"))
    detail(10, "Progress " .. (status.maximum > 0
      and string.format("%.0f%%", 100 * status.progress / status.maximum) or "--"))
    detail(11, "Usage " .. (status.usage and (status.usage .. " EU/t") or "--"))
    if pending and pending.machine == selected then
      detail(13, "Pending confirmation...")
    elseif selected.online and status.control and not pending then
      local label = status.enabled and " Disable work " or " Enable work "
      gpu.setBackground(colors.standby)
      detail(13, label)
      button = {x = detailX, y = 13, w = #label, h = 1, enabled = not status.enabled}
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
  gpu.set(2, height - 1, string.format("%d online / %d paired | %d on map", online, #machines, visible))
  gpu.set(2, height, "Ctrl+C to exit")
  return markers, button
end

local function runDashboard(settings, send, receive, gpu, screen)
  local hall, peers = settings.hall, settings.machines
  assert(type(hall) == "table" and isInteger(hall.originX) and isInteger(hall.originZ)
    and isInteger(hall.spanX) and hall.spanX > 0 and isInteger(hall.spanZ) and hall.spanZ > 0,
    "Set dashboard.hall originX, originZ, spanX and spanZ")
  assert(type(peers) == "table", "Set dashboard.machines to a modem address -> label table")
  local machines, byAddress = {}, {}
  for address, name in pairs(peers) do
    assert(isAddress(address) and type(name) == "string" and name:match("^[ -~]+$"),
      "Each dashboard machine needs a full modem address and a plain-text label")
    local machine = {address = address, name = name, online = false}
    machines[#machines + 1] = machine
    byAddress[address] = machine
  end
  assert(#machines > 0 and #machines <= 99, "Configure between 1 and 99 dashboard machines")
  table.sort(machines, function(a, b)
    if a.name == b.name then return a.address < b.address end
    return a.name < b.name
  end)
  for index, machine in ipairs(machines) do machine.number = index end

  local selected, pending, markers, button
  local dirty, counter = true, 0
  while true do
    local now = computer.uptime()
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
    if dirty then
      markers, button = drawDashboard(gpu, hall, machines, selected, pending)
      dirty = false
    end

    local signal, sender, kind, data, extra = receive(0.5)
    local machine = byAddress[sender]
    if signal == "interrupted" then return end
    if signal == "touch" and sender == screen and extra == 0 then
      local x, y = kind, data
      if contains(button, x, y) and selected.online and not pending then
        now = computer.uptime()
        counter = counter + 1
        local id = string.format("%.3f-%d", now, counter)
        if send(selected.address, "set-work", id, button.enabled) then
          pending = {machine = selected, id = id, enabled = button.enabled, deadline = now + commandTimeout}
          selected.message = nil
        else
          selected.message = "Could not send command"
        end
        dirty = true
      else
        for index = #markers, 1, -1 do
          if contains(markers[index], x, y) then
            selected, dirty = markers[index].machine, true
            break
          end
        end
      end
    elseif signal == "screen_resized" and sender == screen then
      dirty = true
    elseif signal == "modem_message" and machine then
      if kind == "status" then
        local status = decodeStatus(data)
        if status then
          machine.status, machine.online, machine.lastSeen = status, true, computer.uptime()
          dirty = true
        end
      elseif kind == "result" and pending and pending.machine == machine and pending.id == data
          and type(extra) == "boolean" then
        if extra then machine.status.enabled = pending.enabled end
        machine.message = extra and "Work setting confirmed" or "Work setting unconfirmed"
        pending, dirty = nil, true
      end
    end
  end
end

local role, configPath, extra = ...
if extra or (role ~= "agent" and role ~= "dashboard") then
  print("Usage: lua factory-control.lua agent|dashboard [config.lua]")
  return
end

local function main()
  local loadConfig = assert(loadfile(configPath or "config.lua"))
  local config = loadConfig()
  assert(type(config) == "table" and type(config[role]) == "table", "Missing " .. role .. " config")
  local port, settings = config.port, config[role]
  assert(isInteger(port) and port >= 1 and port <= 65535, "Set port to an integer from 1 to 65535")
  local modem = config.modem and assert(component.proxy(config.modem)) or component.getPrimary("modem")
  assert(modem.isWireless() and modem.getStrength() > 0, "Connect a wireless modem with positive signal strength")

  local function send(address, kind, ...)
    local ok, sent = pcall(modem.send, address, port, protocol, kind, ...)
    return ok and sent == true
  end

  local function receive(timeout)
    local signal, first, second, third, fourth, fifth, kind, data, extra = event.pull(timeout)
    if signal == "modem_message" then
      if first == modem.address and third == port and fifth == protocol then
        return signal, second, kind, data, extra
      end
      return
    end
    return signal, first, second, third, fourth
  end

  local gpu, screen, foreground, fgPalette, background, bgPalette
  if role == "dashboard" then
    local term = require("term")
    assert(term.isAvailable(), "Connect a graphics card and touchscreen to the dashboard")
    gpu = term.gpu()
    screen = gpu.getScreen()
    foreground, fgPalette = gpu.getForeground()
    background, bgPalette = gpu.getBackground()
  end

  assert(modem.open(port), "Port is already open on this modem. Stop the other program or change port.")
  local ok, reason = pcall(role == "agent" and runAgent or runDashboard, settings, send, receive, gpu, screen)
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
