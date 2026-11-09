return {
  port = 34173, -- Use the same port on central and every agent.
  -- modem = "LOCAL_WIRELESS_MODEM_ADDRESS", -- Optional with one modem installed.

  -- All settings are optional for the default wireless pairing flow.
  agent = {
    -- Omit controllers to discover every compatible controller connected to this agent.
    -- controllers = {
    --   ["BLAST_FURNACE_COMPONENT_ADDRESS"] = "Electric Blast Furnace",
    --   ["VACUUM_FREEZER_COMPONENT_ADDRESS"] = "Vacuum Freezer",
    -- },
    -- controller = "CONTROLLER_COMPONENT_ADDRESS", -- Legacy single-controller mode.
    -- name = "Factory Hall West", -- Agent label advertised when pairing.
    -- centralModem = "CENTRAL_WIRELESS_MODEM_ADDRESS", -- Manual pairing.
    allowControl = false, -- Set true with centralModem to enable control in normal agent mode.
  },

  central = {
    -- Default hall bounds when central starts without corner arguments.
    -- hall = {originX = 0, originZ = 0, spanX = 32, spanZ = 24},
    -- machines = { ["AGENT_WIRELESS_MODEM_ADDRESS"] = "Factory Hall West" }, -- Manual agent pairing.
  },
}
