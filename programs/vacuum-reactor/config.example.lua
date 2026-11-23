return {
  port = 34174, -- Use the same port on central and every reactor computer.
  -- modem = "LOCAL_MODEM_ADDRESS", -- Required only if this computer sees multiple modems.

  agent = {
    centralModem = "CENTRAL_MODEM_ADDRESS",
    -- reactor = "REACTOR_CHAMBER_ADDRESS", -- Optional with one reactor_chamber component.
    -- transposer = "TRANSPOSER_ADDRESS", -- Optional with one transposer.
    -- redstone = "REDSTONE_COMPONENT_ADDRESS", -- Optional with one redstone component.
    batteryBuffer = true, -- Require one gt_batterybuffer, or give its full component address.
    reactorSide = "east", -- Transposer face touching the IC2 reactor chamber.
    supplySide = "up", -- Transposer face touching fresh rods and cooled cells.
    returnSide = "down", -- Transposer face touching the hot coolant/spent rod inventory.
    redstoneSide = "front", -- Face of the redstone device driving the reactor.
    coolantSwapPercent = 75, -- Percentage of heat capacity used.
    maxHullHeat = 500, -- Shut down at this many hull heat units.
  },

  central = {
    reactors = {
      ["FIRST_REACTOR_MODEM_ADDRESS"] = "Reactor 1",
      -- ["SECOND_REACTOR_MODEM_ADDRESS"] = "Reactor 2",
    },
  },
}
