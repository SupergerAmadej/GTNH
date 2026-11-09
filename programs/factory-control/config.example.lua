return {
  port = 34173, -- Use the same port on the dashboard and every agent.
  -- modem = "LOCAL_WIRELESS_MODEM_ADDRESS", -- Optional with one modem installed.

  -- Fill this section in on the computer next to the multiblock.
  agent = {
    controller = "CONTROLLER_COMPONENT_ADDRESS",
    dashboardModem = "DASHBOARD_WIRELESS_MODEM_ADDRESS",
    allowControl = false,
  },

  -- Fill this section in on the control-room computer.
  dashboard = {
    hall = {originX = 0, originZ = 0, spanX = 32, spanZ = 24},
    machines = {
      ["AGENT_WIRELESS_MODEM_ADDRESS"] = "Electric Blast Furnace",
    },
  },
}
