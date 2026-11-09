# Factory Control

An OpenOS pilot for monitoring and controlling a GregTech production multiblock from a wireless touchscreen dashboard. Run the same script in `agent` mode by the machine and `dashboard` mode in the control room.

## Hardware and connections

- An Electric Blast Furnace or similar production multiblock with a controller that exposes `getCoordinates`, `isMachineActive`, `isWorkAllowed`, `getWorkProgress`, and `getWorkMaxProgress`.
- An OpenComputers Adapter placed directly against the controller and cabled to the machine computer. Run `components -l` there to verify the methods and find the controller component address.
- Two powered OpenComputers computers running OpenOS, each with a Wireless Network Card. The GTNH 2.9.0 pack sets maximum wireless send ranges of 16 blocks for Tier 1 and 400 for Tier 2. Test both directions with the computers in their installed positions. [GTNH 2.9.0 configuration](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/OpenComputers.cfg#L874)
- A Tier 2 or 3 touchscreen connected to the dashboard computer and driven by a graphics card that gives at least a 64 × 18 text viewport. Use the wall as the dashboard computer's OpenOS terminal. Keep keyboard access for setup and **Ctrl+C**. [Screen tiers and touch](https://ocdoc.cil.li/block:screen)
- An Internet Card with access to `raw.githubusercontent.com` for installation.

## Install and pair

Once the program is on GitHub, run the following on each computer. Use a fresh directory for upgrades, then copy the local settings across.

```sh
mkdir factory-control
cd factory-control
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/factory-control/install.lua
lua install.lua
cp config.example.lua config.lua
edit config.lua
```

For a repeatable install, use the same tested commit SHA in the installer URL and as the argument to `lua install.lua SHA`.

1. On both computers, run `components modem` and record the full address of the wireless modem. Set the same `port` on both computers. If a computer has multiple modems, set `modem` to its local wireless modem address.
2. On the agent, set `agent.controller` to the controller address from `components -l`. Set `agent.dashboardModem` to the control room's wireless modem address. Leave `allowControl` set to `false` for the first test.
3. On the dashboard, set the key in `dashboard.machines` to the agent's wireless modem address. The value is the display name. Set `originX` and `originZ` to the hall's minimum X and Z. Set `spanX` and `spanZ` to the block distances to its maximum X and Z. The controller must be within those bounds.

To read the controller position during setup, run `lua` on the agent and enter the following using the controller's address. Exit the interpreter before starting the agent.

```lua
print(require("component").invoke("CONTROLLER_ADDRESS", "getCoordinates"))
```

## Run and verify

On the machine computer, run `lua factory-control.lua agent`. On the control-room computer, run `lua factory-control.lua dashboard`. An optional second argument selects a different config file. The default is `config.lua` in the working directory.

1. Look for a blue square on the map while an enabled machine is idle, and a green square once it starts work. Red takes priority when the scanner reports maintenance problems. Gray indicates a disabled machine or one whose last report is at least 10 seconds old.
2. Touch the square to see its label, world coordinates, work permission, progress, maintenance count, and usage in EU/t. Maintenance and usage are read from the English `Problems` and `Currently uses` scanner lines. The dashboard shows unavailable fields as `unknown` or `--`.
3. Stop the agent and check that the square goes gray. Restart it and check that the same square resumes updating.
4. To try control, set `agent.allowControl = true` and restart the agent. Touch **Disable work** or **Enable work** in the detail panel. Check that the dashboard confirms the setting and the machine's in-game work permission matches. The button changes permission to work. The operating color follows the controller's actual activity.

Pairing filters by modem address. Enable commands on a trusted network, and use OpenOS `useradd` on the dashboard to limit touchscreen input to its operators. Keep live addresses and settings in `config.lua` on the in-game computers.

The map uses one X/Z plane. Additional agents can be paired by adding their modem addresses and labels to `dashboard.machines`. Keep enough space between controllers at the chosen map scale for their squares to remain separately clickable.

## Compatibility

Targeted at GTNH 2.9.0 with the pack's default Computronics machine driver and `GregtechMachineCoordinates` enabled. The pilot uses production-machine scanner fields. The standalone LSC power monitor covers the LSC's bank-specific readings. In-game verification is pending. [Computronics machine configuration](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/computronics.cfg#L90)
