local target, countArg, timeoutArg = ...

if target == "--help" then
  print('Usage: lua cropsnh-breeder.lua ["crop name"|any] [seed count] [retry seconds]')
  print("Defaults: any crop, 1 seed, 600 seconds before replacing a stalled cross.")
  print("Use a seed count of 0 to keep breeding.")
  return
end

local function normalize(name)
  return name:lower():gsub("[^%w]", "")
end

target = normalize(target or "any")
local goal = tonumber(countArg or 1)
local retryAfter = tonumber(timeoutArg or 600)
assert(target ~= "", "Enter a crop name or any.")
assert(goal and goal >= 0 and goal < math.huge and goal % 1 == 0, "Enter a whole seed count of 0 or more.")
assert(retryAfter and retryAfter >= 60 and retryAfter < math.huge, "Enter a retry time of at least 60 seconds.")

local component = require("component")
local computer = require("computer")
local sides = require("sides")

assert(component.isAvailable("robot"), "Run this program on an OpenComputers robot.")
local robot = require("robot")
local inventory = assert(component.inventory_controller, "Install an Inventory Controller Upgrade.")
local geolyzer = assert(component.geolyzer, "Install a Geolyzer.")
local data = assert(component.data, "Install a Tier 1 or better Data Card.")
assert(data.decodeNBT, "This Data Card must support decodeNBT.")

local cropSticks = "cropsnh:cropSticks"
local seedItem = "cropsnh:genericSeed"
local sticksSlot, lensSlot, firstLootSlot = 1, 2, 3
local slots = robot.inventorySize()
local pollSeconds = 12

local function checkSupply(slot, name, label)
  local stack = inventory.getStackInInternalSlot(slot)
  assert(stack and stack.name == name, "Put " .. label .. " in inventory slot " .. slot .. ".")
end

local function blockBelow()
  local block, reason = geolyzer.analyze(sides.down)
  assert(block and block.name, "Cannot scan below the robot: " .. tostring(reason))
  assert(block.name == cropSticks or block.name == "minecraft:air",
    "Expected crop sticks or air below the robot, found " .. block.name .. ".")
  return block.name
end

local function withTool(slot, action)
  robot.select(slot)
  assert(inventory.equip(), "Could not equip the item in slot " .. slot .. ".")
  local ok, reason = pcall(action)
  assert(inventory.equip(), "Could not return the tool to inventory slot " .. slot .. ".")
  if not ok then error(reason, 0) end
end

local function armPlot()
  local needed = blockBelow() == "minecraft:air" and 2 or 1
  local before = robot.count(sticksSlot)
  assert(before > needed, "Add more CropsNH crop sticks to inventory slot 1.")
  if needed == 2 then
    robot.select(sticksSlot)
    robot.placeDown(sides.down, true)
  else
    withTool(sticksSlot, function() robot.useDown(sides.down) end)
  end
  assert(blockBelow() == cropSticks and before - robot.count(sticksSlot) == needed,
    "Could not set double crop sticks. Check the soil and robot block-interaction permissions.")
end

local function sendToChest(slot)
  robot.select(slot)
  local waiting = false
  while robot.count(slot) > 0 do
    local before = robot.count(slot)
    local size = inventory.getInventorySize(sides.front) or 0
    for chestSlot = 1, size do
      inventory.dropIntoSlot(sides.front, chestSlot, robot.count(slot))
      if robot.count(slot) == 0 then return end
    end
    if robot.count(slot) == before then
      if not waiting then print("Waiting for space in the chest in front of the robot.") end
      waiting = true
      os.sleep(5)
    end
  end
end

local function readSeed(stack)
  assert(type(stack.tag) == "string", "Seed NBT is unavailable. Check allowItemStackNBTTags in OpenComputers.cfg.")
  local root = data.decodeNBT(stack.tag)
  local tags = root and root.__value
  assert(type(tags) == "table" and tags.crop and tags.gr and tags.ga and tags.re,
    "Could not read the CropsNH seed's crop and stats.")
  return tags.crop.__value, tags.gr.__value, tags.ga.__value, tags.re.__value
end

local function drainLoot(result)
  for slot = firstLootSlot, slots do
    if robot.count(slot) > 0 then
      local stack = assert(inventory.getStackInInternalSlot(slot), "Could not inspect robot inventory.")
      if stack.name == cropSticks then
        result.sticks = true
        robot.select(slot)
        robot.transferTo(sticksSlot)
      elseif stack.name == seedItem then
        local crop, growth, gain, resistance = readSeed(stack)
        local label = stack.label or crop
        local shortLabel = normalize(label:lower():gsub("%s+seeds?$", ""))
        result.seeds = result.seeds + stack.size
        if target == "any" or target == normalize(crop) or target == normalize(label) or target == shortLabel then
          result.matches = result.matches + stack.size
        end
        print(("%dx %s (%s/%s/%s), crop ID %s"):format(stack.size, label, growth, gain, resistance, crop))
      end
      if robot.count(slot) > 0 then sendToChest(slot) end
    end
  end
end

local function collectDrops(sticksBefore)
  local result = {sticks = false, seeds = 0, matches = 0}
  -- Give any drops that OpenComputers did not pick up directly time to settle.
  os.sleep(0.75)
  repeat
    robot.select(firstLootSlot)
    local pickedUp = robot.suckDown(64)
    drainLoot(result)
  until not pickedUp
  result.sticks = result.sticks or (sticksBefore and robot.count(sticksSlot) > sticksBefore)
  return result
end

local function waitForCharge()
  if computer.energy() >= computer.maxEnergy() * 0.1 then return end
  print("Waiting for charge. Check the adjacent Charger and its redstone signal.")
  repeat os.sleep(5) until computer.energy() >= computer.maxEnergy() * 0.2
end

local function resetPlot()
  local result = {seeds = 0, matches = 0}
  if blockBelow() == cropSticks then
    robot.swingDown(sides.down)
    result = collectDrops()
  end
  -- A swing may remove the crop but leave a single crop stick.
  armPlot()
  return result
end

assert(slots >= firstLootSlot, "Install an Inventory Upgrade for the robot.")
checkSupply(sticksSlot, cropSticks, "CropsNH crop sticks")
checkSupply(lensSlot, "cropsnh:plantLens", "a Plant Lens")
assert(inventory.getInventorySize(sides.front), "Place an output chest directly in front of the robot.")
waitForCharge()
local below = blockBelow()

local carried = {sticks = false, seeds = 0, matches = 0}
drainLoot(carried)
withTool(firstLootSlot, function()
  local tool = inventory.getStackInInternalSlot(firstLootSlot)
  assert(tool and tool.name == "cropsnh:reinforcedSpade", "Equip a Reinforced Spade in the robot's tool slot.")
end)

if below == "minecraft:air" then armPlot() end
local collected = carried.matches
local keepCrop = false
local retryAt = computer.uptime() + retryAfter

print("Breeding " .. target .. " on the plot directly below. Press Ctrl+C to stop.")
while goal == 0 or collected < goal do
  waitForCharge()
  if blockBelow() == "minecraft:air" then
    armPlot()
    retryAt = computer.uptime() + retryAfter
    keepCrop = false
  end

  withTool(lensSlot, function() robot.useDown(sides.down) end)
  local sticksBefore = robot.count(sticksSlot)
  robot.select(firstLootSlot)
  robot.useDown(sides.down)
  local harvest = collectDrops(sticksBefore)
  collected = collected + harvest.matches
  if goal > 0 and collected >= goal then break end

  if harvest.sticks and harvest.seeds == 0 then
    -- Right-clicking an empty cross returns one stick and leaves a single stick.
    armPlot()
    retryAt = computer.uptime() + retryAfter
    keepCrop = false
  elseif harvest.matches > 0 and target ~= "any" then
    -- Keep the desired plant and harvest more of the same seed as it regrows.
    keepCrop = true
    retryAt = computer.uptime() + retryAfter
  elseif (harvest.seeds > 0 and not keepCrop) or computer.uptime() >= retryAt then
    local reset = resetPlot()
    collected = collected + reset.matches
    keepCrop = false
    retryAt = computer.uptime() + retryAfter
  end

  if goal == 0 or collected < goal then os.sleep(pollSeconds) end
end

print(("Done. %d matching seeds sent to the chest."):format(collected))
