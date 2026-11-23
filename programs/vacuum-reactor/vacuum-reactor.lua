local component = require("component")
local computer = require("computer")
local event = require("event")
local keys = require("keyboard").keys
local shell = require("shell")
local sides = require("sides")
local term = require("term")

local protocol = "gtnh-vacuum-reactor/1"
local packetKinds = {
  [protocol .. "/status"] = "status",
  [protocol .. "/disable"] = "disable",
  [protocol .. "/heartbeat"] = "heartbeat",
}
local coolant = "gregtech:gt.360k_Helium_Coolantcell"
local fuel = "gregtech:gt.rodUranium4"
local spentFuel = "gregtech:gt.depletedRodUranium4"
local wearScale = 100 -- GregTech mirrors coolant heat and rod wear into vanilla damage.
local coolantSlots = {
  [1] = true, [5] = true, [8] = true,
  [12] = true, [17] = true,
  [19] = true, [24] = true,
  [31] = true, [36] = true,
  [38] = true, [43] = true,
  [47] = true, [50] = true, [54] = true,
}

local chamberName = "blockReactorChamber"
local coreSize = 54
local sampleInterval = 0.5
local reportInterval = 1
local stopWait = 2 -- IC2 processes its reactor contents every 20 game ticks.
local powerTimeout = 4
local offlineAfter = 5
local disableTimeout = 8
local batteryStart = 25
local batteryStop = 95

local function finite(value)
  return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isAddress(value)
  return type(value) == "string" and #value == 36 and value:match("^%x+%-%x+%-%x+%-%x+%-%x+$")
end

local function plainText(value)
  return tostring(value):gsub("[^ -~]", "?")
end

local function componentAddress(kind, configured)
  if configured ~= nil then
    assert(isAddress(configured) and component.type(configured) == kind,
      "Set the full address of a connected " .. kind .. " component")
    return configured
  end
  local devices = component.list(kind, true)
  local address = assert(devices(), "Connect a " .. kind .. " component")
  assert(not devices(), "Multiple " .. kind .. " components found. Set the address in config.lua.")
  return address
end

local function getSide(value, setting)
  local side = type(value) == "string" and sides[value] or value
  assert(finite(side) and side % 1 == 0 and side >= 0 and side <= 5, "Set agent." .. setting .. " to a valid side")
  return side
end

local function screenKeyboards(screen)
  local keyboards = {}
  for _, address in ipairs(component.invoke(screen, "getKeyboards")) do keyboards[address] = true end
  return keyboards
end

local function receive(modem, port, timeout)
  local signal, address, sender, receivedPort, distance, tag, a, b, c, d, e, f, g = event.pull(timeout)
  if signal == "modem_message" then
    local kind = packetKinds[tag]
    if address == modem.address and receivedPort == port and kind then
      return signal, sender, kind, a, b, c, d, e, f, g
    end
    return
  end
  return signal, address, sender, receivedPort, distance
end

local function send(modem, port, address, kind, ...)
  pcall(modem.send, address, port, protocol .. "/" .. kind, ...)
end

local function writeOutput(agent, level)
  local redstone, side = agent.redstone, agent.redstoneSide
  local previous = redstone.getOutput(side)
  if previous ~= level then redstone.setOutput(side, level) end
  assert(redstone.getOutput(side) == level, "Redstone output did not reach " .. level)
  if level == 0 then
    if previous ~= 0 then agent.offSince = nil end
    agent.offSince = agent.offSince or computer.uptime()
    agent.startedAt = nil
  else
    agent.offSince, agent.stopped = nil, false
    agent.startedAt = agent.startedAt or computer.uptime()
  end
end

local function forceOff(agent)
  local ok = pcall(writeOutput, agent, 0)
  if not ok then
    -- Try the write even if the first attempt failed during readback.
    pcall(agent.redstone.setOutput, agent.redstoneSide, 0)
    agent.offSince, agent.stopped = nil, false
  end
  return ok
end

local function scanInventory(transposer, side, label)
  local stacks, reason = transposer.getAllStacks(side)
  assert(stacks, "Cannot read " .. label .. " inventory: " .. tostring(reason))
  local count = stacks.count()
  assert(finite(count) and count > 0, "No slots in " .. label .. " inventory")
  return stacks.getAll(), count
end

local function readSlot(transposer, side, slot)
  local stack, reason = transposer.getStackInSlot(side, slot)
  assert(not reason, "Cannot read slot " .. slot .. ": " .. tostring(reason))
  return stack or {}
end

local function validDamage(stack, maxDamage)
  return stack.maxDamage == maxDamage and finite(stack.damage) and stack.damage >= 0 and stack.damage <= maxDamage
end

local function scanCore(agent, allowEmpty)
  assert(agent.transposer.getInventoryName(agent.reactorSide) == chamberName,
    "Transposer reactor side must touch the IC2 reactor chamber")
  local slots, count = scanInventory(agent.transposer, agent.reactorSide, "reactor")
  assert(count == coreSize, "Reactor needs six chambers and 54 slots")
  local coolantSwap, fuelSwap
  local hottest, leastFuel = -1, 100
  for slot = 1, coreSize do
    local stack = slots[slot - 1] -- ItemStackArrayValue.getAll() uses zero-based keys.
    assert(type(stack) == "table", "Missing inventory data for slot " .. slot)
    local isCoolant = coolantSlots[slot]
    local expected = isCoolant and coolant or fuel
    local empty = next(stack) == nil
    if empty then
      assert(allowEmpty, "Reactor slot " .. slot .. " became empty while running")
    else
      assert(stack.size == 1 and (stack.name == expected or (not isCoolant and stack.name == spentFuel)),
        "Wrong item in reactor slot " .. slot)
    end

    if isCoolant then
      if not empty then
        assert(validDamage(stack, wearScale), "Missing coolant heat data in slot " .. slot)
        hottest = math.max(hottest, stack.damage)
      end
      if empty or stack.damage >= agent.coolantSwapPercent then
        if not coolantSwap or (stack.damage or 100) > (coolantSwap.old.damage or 100) then
          coolantSwap = {slot = slot, old = stack, fresh = coolant, label = "coolant"}
        end
      end
    else
      local used = wearScale
      if stack.name == fuel then
        assert(validDamage(stack, wearScale), "Missing fuel durability in slot " .. slot)
        used = stack.damage
      end
      leastFuel = math.min(leastFuel, wearScale - used)
      if used >= wearScale and not fuelSwap then
        fuelSwap = {slot = slot, old = stack, fresh = fuel, label = "fuel"}
      end
    end
  end
  agent.hottest, agent.leastFuel = hottest, leastFuel
  return coolantSwap or fuelSwap
end

local function isFresh(stack, swap)
  return stack and stack.name == swap.fresh and validDamage(stack, wearScale) and stack.damage == 0
end

local function swapItem(agent, swap)
  local transposer = agent.transposer
  local supply, supplyCount = scanInventory(transposer, agent.supplySide, "supply")
  local source
  for slot = 1, supplyCount do
    if isFresh(supply[slot - 1], swap) then
      source = slot
      break
    end
  end
  assert(source, "No fresh " .. swap.label .. " in supply inventory")

  local sink
  if swap.old.name then
    local returns, returnCount = scanInventory(transposer, agent.returnSide, "return")
    for slot = 1, returnCount do
      local stack = returns[slot - 1]
      assert(type(stack) == "table", "Missing return inventory data")
      if next(stack) == nil then sink = sink or slot end
      if swap.old.name == spentFuel and stack.name == spentFuel
        and finite(stack.size) and finite(stack.maxSize) and stack.size < stack.maxSize then
        sink = slot
        break
      end
    end
    assert(sink, "Return inventory is full")
  end

  assert(isFresh(readSlot(transposer, agent.supplySide, source), swap), "Supply changed during swap")
  local current = readSlot(transposer, agent.reactorSide, swap.slot)
  assert(current.name == swap.old.name and current.damage == swap.old.damage and current.size == swap.old.size,
    "Reactor slot " .. swap.slot .. " changed during swap")
  assert(agent.redstone.getOutput(agent.redstoneSide) == 0 and agent.reactor.producesEnergy() == false,
    "Reactor received power during swap")
  if sink then
    assert(transposer.transferItem(agent.reactorSide, agent.returnSide, 1, swap.slot, sink) == 1,
      "Could not remove " .. swap.label .. " from slot " .. swap.slot)
  end
  assert(transposer.transferItem(agent.supplySide, agent.reactorSide, 1, source, swap.slot) == 1,
    "Could not fill reactor slot " .. swap.slot)
  assert(isFresh(readSlot(transposer, agent.reactorSide, swap.slot), swap),
    "Replacement in slot " .. swap.slot .. " failed verification")
end

local function samplePower(agent)
  local powered = agent.reactor.producesEnergy()
  local heat = agent.reactor.getHeat()
  local maxHeat = agent.reactor.getMaxHeat()
  local output = agent.reactor.getReactorEUOutput()
  assert(type(powered) == "boolean" and finite(heat) and heat >= 0 and finite(maxHeat) and maxHeat > 0
    and finite(output) and output >= 0, "Reactor readings unavailable")
  agent.heat, agent.output = heat, output
  local now = computer.uptime()
  agent.stopped = agent.offSince ~= nil and now - agent.offSince >= stopWait and not powered and output == 0
  assert(not agent.offSince or now - agent.offSince < powerTimeout or agent.stopped,
    "Reactor still powered with redstone output off")
  return powered
end

local function readBatteryPercent(buffer)
  local stored, capacity, slot = 0, 0, 1
  while true do
    local maximum, reason = buffer.getMaxBatteryCharge(slot)
    if maximum == nil and reason == "slot does not exist" then break end
    if maximum == nil then
      assert(reason == "slot is empty", "Cannot read battery buffer slot " .. slot .. ": " .. tostring(reason))
    else
      local charge = buffer.getBatteryCharge(slot)
      assert(finite(maximum) and maximum > 0 and finite(charge) and charge >= 0 and charge <= maximum,
        "Invalid charge reading in battery buffer slot " .. slot)
      stored, capacity = stored + charge, capacity + maximum
    end
    slot = slot + 1
  end
  assert(capacity > 0, "Battery buffer contains no batteries")
  return 100 * (stored / capacity)
end

local function wantsPower(agent)
  if not agent.batteryBuffer or (agent.centralSeen and computer.uptime() - agent.centralSeen < offlineAfter) then
    agent.batteryCharging = false
    return true, "Generating power"
  end

  local percent = readBatteryPercent(agent.batteryBuffer)
  if percent <= batteryStart then agent.batteryCharging = true end
  if percent >= batteryStop then agent.batteryCharging = false end
  if agent.batteryCharging then return true, "Charging local battery to " .. batteryStop .. "%" end
  return false, "Waiting for local battery to reach " .. batteryStart .. "%"
end

local function agentStep(agent)
  agent.stopped = false
  agent.heat, agent.output, agent.hottest, agent.leastFuel = -1, -1, -1, -1
  local output = agent.redstone.getOutput(agent.redstoneSide)
  if not agent.armed then
    writeOutput(agent, 0)
  elseif agent.startedAt then
    assert(output == 15, "Run signal was interrupted")
  else
    assert(output == 0, "Unexpected redstone output")
  end

  local powered = samplePower(agent)
  if agent.armed then
    assert(agent.heat < agent.maxHullHeat, "Hull heat cutoff reached")
  end

  local swap = scanCore(agent, output == 0 or not agent.armed)
  if not agent.armed then
    return agent.stopped and "DISABLED" or "STOPPING", agent.disarmReason
  end

  local generate, demand = wantsPower(agent)
  if swap then
    writeOutput(agent, 0)
    if agent.stopped then swapItem(agent, swap) end
    return "SWAPPING", "Replace " .. swap.label .. " in slot " .. swap.slot
  end
  if not generate then
    writeOutput(agent, 0)
    return agent.stopped and "STANDBY" or "STOPPING", demand
  end

  if not agent.startedAt then
    if not agent.stopped then return "STARTING", "Checking that the reactor is stopped" end
    writeOutput(agent, 15)
    return "STARTING", "Waiting for reactor output"
  end
  if powered and agent.output > 0 then return "RUNNING", demand end
  assert(computer.uptime() - agent.startedAt < powerTimeout, "Reactor failed to produce power")
  return "STARTING", "Waiting for reactor output"
end

local statusColors = {
  RUNNING = 0x71df9b, STARTING = 0x8fc9ff, SWAPPING = 0x8fc9ff,
  STANDBY = 0x8fc9ff, DISABLED = 0xf5d184, STOPPING = 0xf5d184, FAULT = 0xff8585, OFFLINE = 0xadb4bd,
}

local function online(reactor, now)
  return reactor.lastSeen and now - reactor.lastSeen < offlineAfter
end

local function updateStatus(reactor, now, status, detail, heat, output, hottest, fuelRemaining, stopReport)
  if status == "OFFLINE" or not statusColors[status] or type(detail) ~= "string" or #detail > 120
    or not finite(heat) or not finite(output) or not finite(hottest) or not finite(fuelRemaining)
    or type(stopReport) ~= "string" or #stopReport > 64 then return end
  reactor.status, reactor.detail = status, plainText(detail)
  reactor.heat, reactor.output = heat, output
  reactor.hottest, reactor.fuelRemaining, reactor.stopped = hottest, fuelRemaining, stopReport ~= ""
  reactor.lastSeen = now
  if reactor.pending and stopReport == reactor.pending.id then
    reactor.pending, reactor.notice = nil, "Shutdown confirmed"
  elseif reactor.notice == "Shutdown confirmed" and not reactor.stopped then
    reactor.notice = nil
  end
  return true
end

local function field(value, decimals, suffix)
  if value == nil or value < 0 then return "--" end
  return string.format("%." .. decimals .. "f", value) .. (suffix or "")
end

local function runCentral(settings, modem, port, gpu, screen)
  local reactors, byAddress = {}, {}
  assert(type(settings.reactors) == "table", "Set central.reactors in config.lua")
  for address, name in pairs(settings.reactors) do
    assert(isAddress(address) and address ~= modem.address and type(name) == "string"
      and #name > 0 and #name <= 48 and plainText(name) == name,
      "Set each central.reactors entry to a reactor modem address and a plain-text name")
    local reactor = {address = address, name = name}
    reactors[#reactors + 1], byAddress[address] = reactor, reactor
  end
  assert(#reactors > 0, "Add at least one modem address to central.reactors")
  table.sort(reactors, function(a, b)
    if a.name == b.name then return a.address < b.address end
    return a.name < b.name
  end)

  local keyboards = screenKeyboards(screen)
  local width, height = gpu.getResolution()
  assert(width >= 64 and height >= 12, "Central needs at least a 64 x 12 screen")
  local rowsPerPage = height - 8
  local page, selected = 1, 1
  local confirming, confirmUntil
  local session, sequence = tostring(os.time()), 0
  local nextDraw = 0
  local background, foreground, heading, cursor = 0x111820, 0xe2e8ef, 0x1c2936, 0x2a425a
  local lastPage = math.ceil(#reactors / rowsPerPage)
  local nameWidth = width - 50
  local rowFormat = " %-" .. nameWidth .. "s %-10s %8s %10s %9s %6s "
  local drawn = {}

  local function line(y, value, color, fill, status)
    local last = drawn[y]
    if last and last.value == value and last.color == color and last.fill == fill and last.status == status then return end
    gpu.setBackground(fill or background)
    gpu.setForeground(color or foreground)
    gpu.fill(1, y, width, 1, " ")
    if #value > 0 then gpu.set(1, y, value:sub(1, width)) end
    if status then
      gpu.setForeground(statusColors[status])
      gpu.set(nameWidth + 3, y, status)
    end
    drawn[y] = {value = value, color = color, fill = fill, status = status}
  end

  local function selectRow(index)
    if index < 1 or index > #reactors then return end
    selected = index
    page = math.floor((index - 1) / rowsPerPage) + 1
    confirming = nil
  end

  local function draw(now)
    line(1, " Vacuum reactor control", foreground, heading)
    line(2, string.format(" %d reactors   |   Page %d/%d", #reactors, page, lastPage))
    line(3, rowFormat:format("Reactor", "Status", "Hull HU", "EU/t", "Cell heat", "Fuel"), foreground, heading)
    for row = 1, rowsPerPage do
      local index = (page - 1) * rowsPerPage + row
      local reactor = reactors[index]
      if reactor then
        local live = online(reactor, now)
        local status = live and reactor.status or "OFFLINE"
        local value = rowFormat:format(reactor.name:sub(1, nameWidth), status,
          field(live and reactor.heat or nil, 0), field(live and reactor.output or nil, 0),
          field(live and reactor.hottest or nil, 0, "%"), field(live and reactor.fuelRemaining or nil, 0, "%"))
        line(row + 3, value, foreground, index == selected and cursor or background, status)
      else
        line(row + 3, "")
      end
    end

    local reactor = reactors[selected]
    local live = online(reactor, now)
    local detail = live and reactor.detail or (reactor.lastSeen and "No recent report" or "Waiting for first report")
    if live and reactor.status == "FAULT" and not reactor.stopped then detail = "Stop unconfirmed | " .. detail end
    line(height - 4, " " .. reactor.name .. "  |  " .. detail, foreground, heading)
    local notice = reactor.pending and "Waiting for reactor to confirm shutdown" or reactor.notice or ""
    if confirming == reactor then notice = "Confirm shutdown of " .. reactor.name end
    line(height - 3, " " .. notice)
    local button = ""
    if live and not reactor.pending then
      button = confirming == reactor and "[ Confirm stop ]" or "[ Disable ]"
    end
    line(height - 2, " " .. button, statusColors.DISABLED, heading)
    line(height - 1, " [ Previous ]  [ Next ]", foreground, heading)
    line(height, " Up/Down select   Left/Right page   D disable   Ctrl+C exit")
  end

  local function requestDisable(now)
    local reactor = reactors[selected]
    if not online(reactor, now) or reactor.pending then return end
    if reactor ~= confirming or now >= confirmUntil then
      confirming, confirmUntil = reactor, now + 6
      return
    end
    sequence = sequence + 1
    local id = session .. "-" .. sequence
    reactor.pending = {id = id, deadline = now + disableTimeout, retryAt = now}
    reactor.notice, confirming = nil, nil
  end

  local disableHeld
  while true do
    local now = computer.uptime()
    if confirming and (now >= confirmUntil or not online(confirming, now)) then confirming = nil end
    for _, reactor in ipairs(reactors) do
      local pending = reactor.pending
      if pending and now >= pending.deadline then
        reactor.pending, reactor.notice = nil, "Shutdown unconfirmed. Check the reactor locally."
      elseif pending and now >= pending.retryAt then
        send(modem, port, reactor.address, "disable", pending.id)
        pending.retryAt = now + 1
      end
    end
    if now >= nextDraw then
      draw(now)
      nextDraw = computer.uptime() + 0.5
    end

    local signal, address, kind, a, b, c, d, e, f, g = receive(modem, port,
      math.max(0, nextDraw - computer.uptime()))
    if signal == "interrupted" then return end
    now = computer.uptime()
    if signal == "modem_message" and kind == "status" and byAddress[address] then
      if updateStatus(byAddress[address], now, a, b, c, d, e, f, g) then
        send(modem, port, address, "heartbeat")
      end
    elseif signal == "touch" and address == screen then
      local x, y = kind, a
      if y >= 4 and y <= height - 5 then
        selectRow((page - 1) * rowsPerPage + y - 3)
      elseif y == height - 2 and x >= 2 and x <= (confirming and 17 or 12) then
        requestDisable(now)
      elseif y == height - 1 then
        if x >= 2 and x <= 13 and page > 1 then selectRow((page - 2) * rowsPerPage + 1) end
        if x >= 16 and x <= 23 and page < lastPage then selectRow(page * rowsPerPage + 1) end
      end
      nextDraw = 0
    elseif signal == "key_down" and keyboards[address] then
      if a == keys.up then selectRow(selected - 1) end
      if a == keys.down then selectRow(selected + 1) end
      if a == keys.left and page > 1 then selectRow((page - 2) * rowsPerPage + 1) end
      if a == keys.right and page < lastPage then selectRow(page * rowsPerPage + 1) end
      if a == keys.d and not disableHeld then
        disableHeld = true
        requestDisable(now)
      end
      nextDraw = 0
    elseif signal == "key_up" and keyboards[address] and a == keys.d then
      disableHeld = false
    end
  end
end

local function makeAgent(settings)
  assert(isAddress(settings.centralModem), "Set agent.centralModem to central's full modem address")
  local agent = {
    central = settings.centralModem,
    reactorSide = getSide(settings.reactorSide, "reactorSide"),
    supplySide = getSide(settings.supplySide, "supplySide"),
    returnSide = getSide(settings.returnSide, "returnSide"),
    redstoneSide = getSide(settings.redstoneSide, "redstoneSide"),
    coolantSwapPercent = settings.coolantSwapPercent or 75,
    maxHullHeat = settings.maxHullHeat or 500,
    redstone = component.proxy(componentAddress("redstone", settings.redstone)),
    disarmReason = "Local arming required",
    heat = -1, output = -1, hottest = -1, leastFuel = -1,
    command = "",
  }
  assert(forceOff(agent), "Could not verify redstone output is off")
  assert(agent.reactorSide ~= agent.supplySide and agent.reactorSide ~= agent.returnSide
    and agent.supplySide ~= agent.returnSide, "Use three distinct Transposer faces")
  assert(finite(agent.coolantSwapPercent) and agent.coolantSwapPercent >= 1 and agent.coolantSwapPercent <= 85,
    "Set coolantSwapPercent to 1 through 85")
  assert(finite(agent.maxHullHeat) and agent.maxHullHeat >= 1 and agent.maxHullHeat <= 1000,
    "Set maxHullHeat to 1 through 1000 HU")
  agent.reactor = component.proxy(componentAddress("reactor_chamber", settings.reactor))
  agent.transposer = component.proxy(componentAddress("transposer", settings.transposer))
  local buffer = settings.batteryBuffer
  if buffer ~= nil or component.list("gt_batterybuffer", true)() then
    if buffer == true then buffer = nil end
    local address = componentAddress("gt_batterybuffer", buffer)
    agent.batteryBuffer = component.proxy(address)
  end
  return agent
end

local function runAgent(agent, modem, port)
  local keyboards = {}
  local console = term.isAvailable()
  if console then
    keyboards = screenKeyboards(term.gpu().getScreen())
    print("Vacuum reactor agent | A arm | D disable | Ctrl+C exit")
    print("Modem: " .. modem.address)
  end
  local nextSample, nextReport = 0, 0
  local status, detail, armHeld
  while true do
    local now = computer.uptime()
    if now >= nextSample then
      local ok, newStatus, newDetail = pcall(agentStep, agent)
      if not ok then
        local poweredOff = forceOff(agent)
        local reason = plainText(newStatus):gsub("^.-:%s*%d+:?%s*", "", 1)
        agent.armed = false
        agent.fault = agent.fault or reason
        if not poweredOff or reason == "Reactor still powered with redstone output off" then
          agent.fault = poweredOff and reason or "Could not verify redstone output is off"
        end
      end
      if agent.fault then
        newStatus, newDetail = "FAULT", agent.fault
      end
      newDetail = newDetail:sub(1, 120)
      if newStatus ~= status or newDetail ~= detail then
        status, detail, nextReport = newStatus, newDetail, 0
        if console then print(status .. " | " .. detail) end
      end
      nextSample = computer.uptime() + sampleInterval
    end
    if computer.uptime() >= nextReport then
      -- GTNH caps packets at eight parts. The last part also acknowledges a requested stop.
      local stopReport = ""
      if agent.stopped then
        stopReport = not agent.armed and agent.command ~= "" and agent.command or "off"
      end
      send(modem, port, agent.central, "status", status, detail, agent.heat, agent.output,
        agent.hottest, agent.leastFuel, stopReport)
      nextReport = computer.uptime() + reportInterval
    end

    local signal, sender, kind, data = receive(modem, port,
      math.max(0, math.min(nextSample, nextReport) - computer.uptime()))
    if signal == "interrupted" then return end
    if signal == "modem_message" and sender == agent.central and kind == "heartbeat" and data == nil then
      local previous = agent.centralSeen
      agent.centralSeen = computer.uptime()
      if not previous or agent.centralSeen - previous >= offlineAfter then nextSample = 0 end
    elseif signal == "modem_message" and sender == agent.central and kind == "disable"
      and type(data) == "string" and #data > 0 and #data <= 64 and data ~= agent.command then
      agent.armed, agent.command, agent.disarmReason = false, data, "Disabled from central"
      nextSample, nextReport = 0, 0
    elseif signal == "key_down" and keyboards[sender] then
      if data == keys.a and not armHeld then
        armHeld = true
        if not agent.armed then
          agent.armed, agent.fault, agent.batteryCharging = true, nil, false
          nextSample = 0
        end
      elseif data == keys.d then
        agent.armed, agent.disarmReason = false, "Disabled at reactor"
        nextSample = 0
      end
    elseif signal == "key_up" and keyboards[sender] and data == keys.a then
      armHeld = false
    end
  end
end

local role, path, extra = ...
if (role ~= "agent" and role ~= "central") or extra then
  io.stderr:write("Usage: lua vacuum-reactor.lua agent|central [config.lua]\n")
  return
end

local config = assert(loadfile(shell.resolve(path or "config.lua")))()
assert(type(config) == "table" and type(config[role]) == "table", "Set the " .. role .. " table in config.lua")
local settings = config[role]
local port = config.port or 34174
assert(finite(port) and port % 1 == 0 and port >= 1 and port <= 65535, "Set port to an integer from 1 to 65535")

local agent = role == "agent" and makeAgent(settings) or nil
local modem = component.proxy(componentAddress("modem", config.modem))
if modem.isWireless() then assert(modem.getStrength() > 0, "Set positive wireless modem strength") end
assert(modem.open(port), "Modem port already open. Stop the other program or change port.")

local ok, reason
if agent then
  ok, reason = pcall(runAgent, agent, modem, port)
  if not forceOff(agent) then io.stderr:write("Redstone output off could not be confirmed. Check the reactor.\n") end
else
  local gpu, screen, fg, fgPalette, bg, bgPalette, blink
  ok, reason = pcall(function()
    assert(term.isAvailable(), "Connect a graphics card and screen to central")
    gpu = term.gpu()
    screen = gpu.getScreen()
    fg, fgPalette = gpu.getForeground()
    bg, bgPalette = gpu.getBackground()
    blink = term.getCursorBlink()
    term.setCursorBlink(false)
    runCentral(settings, modem, port, gpu, screen)
  end)
  if fg then pcall(gpu.setForeground, fg, fgPalette) end
  if bg then pcall(gpu.setBackground, bg, bgPalette) end
  if blink ~= nil then pcall(term.setCursorBlink, blink) end
  if gpu then pcall(term.clear) end
end
pcall(modem.close, port)
if not ok then error(reason, 0) end
