return {
  port = 34174, -- Use the same port on central and every reactor computer.
  -- modem = "LOCAL_MODEM_ADDRESS", -- Required only if this computer sees multiple modems.

  agent = {
    -- name = "Reactor West", -- Label used during pairing.
    -- centralModem = "CENTRAL_MODEM_ADDRESS", -- Optional manual pairing.
    -- reactor = "REACTOR_CHAMBER_ADDRESS", -- Optional with one reactor_chamber component.
    -- transposer = "TRANSPOSER_ADDRESS", -- Optional with one transposer.
    -- redstone = "REDSTONE_COMPONENT_ADDRESS", -- Optional with one redstone component.
    -- batteryBuffer = "BATTERY_BUFFER_ADDRESS", -- Optional with one gt_batterybuffer.
    -- reactorSide = "east", -- Override the detected reactor face.
    -- supplySide = "up", -- Override the detected supply face.
    -- returnSide = "down", -- Override the detected return face.
    -- redstoneSide = "front", -- Use one output face. The default uses the dedicated device's six faces.
    coolantSwapPercent = 75, -- Percentage of heat capacity used.
    maxHullHeat = 500, -- Shut down at this many hull heat units.
  },

  central = {
    -- reactors = { ["REACTOR_MODEM_ADDRESS"] = "Reactor 1" }, -- Optional manual pairing.
  },
}
