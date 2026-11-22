local hw, targetArg, statsArg, countArg, configArg = ...
local filesystem = require("filesystem")
local serialization = require("serialization")
local shell = require("shell")
local robot, inventory, computer, sides = hw.robot, hw.inventory, hw.computer, hw.sides
local seedSide, outputSide = sides.down, sides.up
local air = "minecraft:air"

assert(targetArg and targetArg ~= "", 'Usage: lua cropsnh-breeder.lua field "crop" [31/31/31] [count] [config.lua]')
local requested = statsArg or "1/1/1"
local gr, ga, re = requested:match("^(%d+)/(%d+)/(%d+)$")
local minimum = {tonumber(gr), tonumber(ga), tonumber(re)}
for i = 1, 3 do
  assert(minimum[i] and minimum[i] >= 1 and minimum[i] <= 31, "Use growth/gain/resistance between 1 and 31.")
end
local goal = tonumber(countArg or 1)
assert(goal and goal >= 1 and goal < math.huge and goal % 1 == 0, "Enter a positive seed count.")

local configPath = shell.resolve(configArg or "config.lua")
local config = assert(loadfile(configPath))()
assert(type(config) == "table" and type(config.plots) == "table" and #config.plots > 0,
  "Copy config.example.lua to config.lua and describe at least one plot.")
local retryAfter = config.retrySeconds or 600
assert(type(retryAfter) == "number" and retryAfter >= 60 and retryAfter < math.huge,
  "retrySeconds must be at least 60.")

-- X is forward from the dock. Z is right as seen from the dock.
local offsets = {{"left", 0, -1}, {"right", 0, 1}, {"front", 1, 0}, {"back", -1, 0}}
local breeders, statPlots, aliases, layout = {}, {}, {}, {}
local function cropKey(crop)
  assert(type(crop) == "string" and hw.normalize(crop) ~= "", "Enter a crop ID for each crop and parent.")
  return hw.normalize(crop)
end

for n, entry in ipairs(config.plots) do
  local crop = cropKey(entry.crop)
  local plot = {x = n * 4, crop = crop, stats = entry.stats == true, parents = {}, label = entry.label or entry.crop}
  aliases[cropKey(plot.label)] = crop
  local inputs = entry.parents
  if plot.stats then inputs = {left = entry.crop} end
  assert(type(inputs) == "table", "Plot " .. n .. " needs a parents table or stats = true.")
  for _, offset in ipairs(offsets) do
    local side, dx, dz = offset[1], offset[2], offset[3]
    if inputs[side] then
      local x, z = plot.x + dx, dz
      plot.parents[#plot.parents + 1] = {crop = cropKey(inputs[side]), x = x, z = z, key = x .. "," .. z}
    end
  end
  local supplied = 0
  for _ in pairs(inputs) do supplied = supplied + 1 end
  assert(supplied > 0 and supplied == #plot.parents, "Use left, right, front or back for parents in plot " .. n .. ".")
  local group = plot.stats and statPlots or breeders
  group[crop] = group[crop] or {}
  group[crop][#group[crop] + 1] = plot
  local signature = {crop, tostring(plot.stats)}
  for _, parent in ipairs(plot.parents) do signature[#signature + 1] = parent.key .. "=" .. parent.crop end
  layout[n] = table.concat(signature, ";")
end

local target = aliases[cropKey(targetArg)] or cropKey(targetArg)
local needsStats = minimum[1] > 1 or minimum[2] > 1 or minimum[3] > 1
local useStatPlots = statPlots[target] and (needsStats or not breeders[target])
assert(not needsStats or useStatPlots, "Configure a stats plot for " .. targetArg .. " to raise its stats.")
assert(useStatPlots or breeders[target], "Configure a cross or stats plot for " .. targetArg .. ".")

assert((inventory.getInventorySize(seedSide) or 0) > 0 and (inventory.getInventorySize(outputSide) or 0) > 0,
  "Start at the dock facing the plots, with the seed chest underneath and the output chest above.")

local statePath = filesystem.concat(filesystem.path(configPath), "state", filesystem.name(configPath) .. ".field")
local signature = table.concat(layout, "|")
local state, hasCheckpoint
for slot = 0, 1 do
  local path = statePath .. "." .. slot
  if filesystem.exists(path) then
    hasCheckpoint = true
    local file = assert(io.open(path, "r"))
    local contents = file:read("*a")
    file:close()
    local ok, saved = pcall(serialization.unserialize, contents)
    if ok and type(saved) == "table" and type(saved.revision) == "number"
        and (not state or saved.revision > state.revision) then state = saved end
  end
end
assert(state or not hasCheckpoint, "Could not read the field checkpoints at " .. statePath)
state = state or {layout = signature, revision = 0, parents = {}, centers = {}}
assert(type(state.layout) == "string" and state.parents and state.centers
    and (state.layout == signature or signature:sub(1, #state.layout + 1) == state.layout .. "|"),
  "The saved field layout differs. Use a separate config file for a new layout.")
state.layout = signature

local function save()
  local directory = filesystem.path(statePath)
  if not filesystem.exists(directory) then assert(filesystem.makeDirectory(directory)) end
  state.revision = state.revision + 1
  local temporary = statePath .. ".tmp"
  local file = assert(io.open(temporary, "w"))
  local written, reason = file:write(serialization.serialize(state))
  local flushed, flushError = file:flush()
  file:close()
  assert(written and flushed, reason or flushError)
  -- Publish to the older slot so the previous checkpoint survives an interrupted save.
  local destination = statePath .. "." .. (state.revision % 2)
  if filesystem.exists(destination) then assert(filesystem.remove(destination)) end
  assert(filesystem.rename(temporary, destination))
end

local x, z, heading = 0, 0, 0
local function face(wanted)
  while heading ~= wanted do
    local left = (heading - wanted) % 4 == 1
    local ok, reason
    if left then ok, reason = robot.turnLeft() else ok, reason = robot.turnRight() end
    assert(ok, "Could not turn: " .. tostring(reason))
    heading = (heading + (left and -1 or 1)) % 4
  end
end

local function travel(toX, toZ)
  local function along(current, destination, increasing, decreasing, update)
    if current == destination then return end
    local step = destination > current and 1 or -1
    face(step == 1 and increasing or decreasing)
    while current ~= destination do
      local ok, reason = robot.forward()
      assert(ok, ("Passage blocked at %d,%d: %s"):format(x, z, tostring(reason)))
      current = current + step
      update(current)
    end
  end
  along(z, 0, 1, 3, function(value) z = value end)
  along(x, toX, 0, 2, function(value) x = value end)
  along(z, toZ, 1, 3, function(value) z = value end)
  if toX == 0 and toZ == 0 then face(0) end
end

local function charge(distance)
  -- Stock GTNH charges 15 OC energy per move. Reserve extra for turns and work.
  local needed = 500 + distance * 40
  assert(computer.maxEnergy() >= needed, "This plot is too far from the dock for the robot's battery.")
  if computer.energy() >= needed then return end
  print("Waiting for the dock Charger.")
  repeat os.sleep(5) until computer.energy() >= needed
end

local function trip(toX, toZ, work)
  charge(toX + math.abs(toZ))
  travel(toX, toZ)
  local result = work()
  travel(0, 0)
  return result
end

local function seedInfo(stack)
  if not stack or stack.name ~= hw.seedItem then return end
  local name, growth, gain, resistance = hw.readSeed(stack)
  return {crop = cropKey(name), growth = growth, gain = gain, resistance = resistance, label = stack.label or name}
end

local function deficit(seed)
  return math.max(0, minimum[1] - seed.growth) + math.max(0, minimum[2] - seed.gain)
    + math.max(0, minimum[3] - seed.resistance)
end

local function better(candidate, previous)
  if not previous then return true end
  local left, right = deficit(candidate), deficit(previous)
  if left ~= right then return left < right end
  if candidate.resistance ~= previous.resistance then return candidate.resistance > previous.resistance end
  return candidate.growth + candidate.gain > previous.growth + previous.gain
end

local bank
local function stock()
  if bank then return bank end
  bank = {}
  local size = assert(inventory.getInventorySize(seedSide), "Seed chest is missing at the dock.")
  for slot = 1, size do
    local seed = seedInfo(inventory.getStackInSlot(seedSide, slot))
    if seed and better(seed, bank[seed.crop]) then
      seed.slot = slot
      bank[seed.crop] = seed
    end
  end
  return bank
end

local delivered = 0
local function drain(plot, parent, recover)
  local savedImprovement = false
  for slot = hw.firstLootSlot, hw.slots do
    if robot.count(slot) > 0 then
      local stack = assert(inventory.getStackInInternalSlot(slot), "Could not inspect the robot inventory.")
      local seed = seedInfo(stack)
      if stack.name == hw.cropSticks then
        robot.select(slot)
        robot.transferTo(hw.sticksSlot)
      elseif seed and plot and seed.crop == target and deficit(seed) == 0 then
        delivered = delivered + hw.sendToChest(slot, outputSide)
        print(("%s %d/%d/%d, delivered %d/%d"):format(seed.label, seed.growth, seed.gain, seed.resistance, delivered, goal))
      elseif seed and (recover or (plot and seed.crop == plot.crop and not plot.stats)) then
        hw.sendToChest(slot, seedSide)
        bank = nil
      elseif seed and plot and plot.stats and seed.crop == plot.crop and not savedImprovement
          and deficit(seed) < deficit(parent) then
        hw.sendToChest(slot, seedSide, 1)
        savedImprovement = true
        bank = nil
      end
      if robot.count(slot) > 0 then hw.sendToChest(slot, outputSide) end
    end
  end
end

local function setParent(parent, candidate)
  local slot = hw.firstLootSlot
  robot.select(slot)
  inventory.suckFromSlot(seedSide, candidate.slot, 1)
  bank = nil
  local seed = seedInfo(inventory.getStackInInternalSlot(slot))
  assert(seed and seed.crop == parent.crop and robot.count(slot) == 1
      and seed.growth == candidate.growth and seed.gain == candidate.gain and seed.resistance == candidate.resistance,
    "Seed chest changed during pickup. Restart at the dock.")
  local old = state.parents[parent.key]
  trip(parent.x, parent.z, function()
    local block = hw.blockBelow()
    assert(old or block == air, "Clear the parent tile at " .. parent.key .. " before the first run.")
    state.pending = {x = parent.x, z = parent.z, key = parent.key}
    save()
    if block == hw.cropSticks then
      robot.swingDown(sides.down)
      hw.sweepDrops()
    end
    if hw.blockBelow() == air then hw.placeSticks(1, true) end
    hw.withTool(slot, function() robot.useDown(sides.down) end)
    assert(robot.count(slot) == 0, "Could not plant " .. seed.crop .. " at " .. parent.key .. ". Check the soil.")
    state.parents[parent.key] = seed
    state.pending = nil
    save()
  end)
  print(("Planted %s %d/%d/%d at %s"):format(seed.label, seed.growth, seed.gain, seed.resistance, parent.key))
  drain()
end

local function visit(plot)
  for _, parent in ipairs(plot.parents) do
    local current = state.parents[parent.key]
    local candidate = stock()[parent.crop]
    if candidate and (not current or (plot.stats and deficit(candidate) < deficit(current))) then
      setParent(parent, candidate)
    end
  end
  for _, parent in ipairs(plot.parents) do
    if not state.parents[parent.key] then return false end
  end

  trip(plot.x, 0, function()
    local block = hw.blockBelow()
    if not state.centers[plot.x] then
      assert(block == air, "Clear the breeding tile at " .. plot.x .. ",0 before its first run.")
      state.centers[plot.x] = true
      save()
    end
    if block == air then hw.armPlot() end
    local now = computer.uptime()
    plot.retryAt = plot.retryAt or now + retryAfter

    hw.withTool(hw.lensSlot, function() robot.useDown(sides.down) end)
    local before = robot.count(hw.sticksSlot)
    robot.select(hw.firstLootSlot)
    robot.useDown(sides.down)
    hw.sweepDrops()

    local emptyCross = robot.count(hw.sticksSlot) > before
    local anySeed, wantedSeed, qualified = false, false, false
    for slot = hw.firstLootSlot, hw.slots do
      local stack = inventory.getStackInInternalSlot(slot)
      emptyCross = emptyCross or (stack and stack.name == hw.cropSticks)
      local seed = seedInfo(stack)
      anySeed = anySeed or seed ~= nil
      wantedSeed = wantedSeed or (seed and seed.crop == plot.crop)
      qualified = qualified or (seed and seed.crop == target and deficit(seed) == 0)
    end
    if emptyCross and not anySeed then
      hw.armPlot()
      plot.retryAt = now + retryAfter
    elseif (anySeed and (not wantedSeed or (plot.stats and not qualified))) or (not wantedSeed and now >= plot.retryAt) then
      robot.swingDown(sides.down)
      hw.sweepDrops()
      hw.armPlot()
      plot.retryAt = now + retryAfter
    elseif wantedSeed then
      plot.retryAt = now + retryAfter
    end
  end)
  drain(plot, state.parents[plot.parents[1].key])
  return true
end

local function worklist()
  local jobs, seen, visiting, missing = {}, {}, {}, {}
  local function produce(crop, always)
    if seen[crop] or (not always and stock()[crop]) then return end
    assert(not visiting[crop], "Cyclic breeding route at " .. crop .. ". Add a starter seed to break the cycle.")
    if not breeders[crop] then missing[crop] = true; return end
    visiting[crop] = true
    for _, plot in ipairs(breeders[crop]) do
      for _, parent in ipairs(plot.parents) do
        if not state.parents[parent.key] then produce(parent.crop) end
      end
      jobs[#jobs + 1] = plot
    end
    visiting[crop] = nil
    seen[crop] = true
  end

  if useStatPlots then
    for _, plot in ipairs(statPlots[target]) do
      if not state.parents[plot.parents[1].key] then produce(target) end
      jobs[#jobs + 1] = plot
    end
  else
    produce(target, true)
  end
  local shortages = {}
  for crop in pairs(missing) do shortages[#shortages + 1] = crop end
  table.sort(shortages)
  return jobs, table.concat(shortages, ", ")
end

local function run()
  drain(nil, nil, true)
  hw.checkSpade()
  if state.pending then
    local pending = state.pending
    trip(pending.x, pending.z, function()
      assert(hw.blockBelow() == air, "Clear interrupted parent tile " .. pending.key .. " and restart at the dock.")
    end)
    state.parents[pending.key] = nil
    state.pending = nil
    save()
  end

  print(("Breeding %s to at least %s. Press Ctrl+C to stop."):format(targetArg, requested))
  local previousShortages
  while delivered < goal do
    bank = nil
    local jobs, shortages = worklist()
    if shortages ~= previousShortages and shortages ~= "" then
      print("Waiting for starter seeds in the chest below: " .. shortages)
    end
    previousShortages = shortages
    for _, plot in ipairs(jobs) do
      visit(plot)
      if delivered >= goal then break end
    end
    if delivered < goal then os.sleep(hw.pollSeconds) end
  end
end

local ok, reason = pcall(run)
if not ok then
  local returned, homeError = pcall(travel, 0, 0)
  if not returned then io.stderr:write("Return the robot to its dock before restarting: " .. tostring(homeError) .. "\n") end
  error(reason, 0)
end
print(("Done. %d matching seeds sent to the output chest."):format(delivered))
