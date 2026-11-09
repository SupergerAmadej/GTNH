# Factory Control

Monitor and control GregTech production multiblocks from a wireless touchscreen. Run the same script in `agent` mode on each machine computer and `central` mode in the control room. Each agent can serve several controllers.

## Hardware and connections

- Production multiblocks with controllers that expose `getCoordinates`, `isMachineActive`, `isWorkAllowed`, `getWorkProgress`, and `getWorkMaxProgress`. Work controls also require `setWorkAllowed`.
- An OpenComputers Adapter placed directly against each controller. Cable the Adapters you want to group to the same agent computer. Run `components -l` there to verify the methods and see the controller addresses.
- Powered OpenComputers computers running OpenOS, each with a Wireless Network Card. The GTNH 2.9.0 pack sets maximum wireless send ranges of 16 blocks for Tier 1 and 400 for Tier 2. Test both directions with the computers in their installed positions. [GTNH 2.9.0 configuration](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/OpenComputers.cfg#L874)
- A Tier 2 or 3 touchscreen connected to the central computer and driven by a graphics card that gives at least a 64 × 18 text viewport. Use the wall as central's OpenOS terminal. Keep keyboard access for setup and **Ctrl+C**. [Screen tiers and touch](https://ocdoc.cil.li/block:screen)
- An Internet Card with access to `raw.githubusercontent.com` for installation.

## Install and pair

Run the following on each computer to install from `main`.

```sh
mkdir factory-control
cd factory-control
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/factory-control/factory-control.lua
```

Replace `main` with a tested commit SHA for a repeatable install. If you also want the config template, download `install.lua` instead and run `lua install.lua` in a fresh directory. For a pinned install, use the same SHA in that download URL and as the argument to `lua install.lua SHA`.

1. On the control-room computer, run `lua factory-control.lua central` or supply the hall corners as shown below. Touch **Add agent** to open the 60-second pairing window.
2. On the machine computer, run `lua factory-control.lua agent`. The agent selects its wireless modem and discovers compatible controllers on the local component network. It advertises on port `34173`.
3. Touch the agent's name in the pairing panel. A number in brackets shows the controller count for a group. Each reporting controller gets its own square. Touch **Close pairing** when done.

Pair each agent once. With automatic discovery, connecting another compatible controller to that agent adds it to central without another pairing. Use **Machines** to select any reported controller, including ones whose squares overlap or lie outside the hall bounds.

Both computers save their pairings under `state/` beside their config. Start each program again from the same directory to reuse the pairings. For an upgrade in a new directory, copy `state/` and any local `config.lua` across. Central keeps the last position for agents that go offline during the session.

To move an automatically paired agent to a new central computer, stop the agent and remove its `state/config.lua.agent` file before starting it again. To remove its entry from the old central computer, stop the program there and delete the file named after the agent's modem address inside `state/config.lua.dashboard/`. Central uses the original state directory to preserve existing pairings. If you use a custom config filename, the state paths use that filename in place of `config.lua`.

## Set the hall layout

Give `central` two `X,Z` coordinates. The first maps to the upper left and the second maps to the lower right. Use world coordinates for the hall corners. Either axis can run in decreasing order if the screen should face that way.

```sh
lua factory-control.lua -- central -120,35 -80,70
```

The `--` keeps OpenOS from treating negative coordinates as options. Two plain integers describe a square. For example, `central 20 80` maps `(20,20)` to the upper left and `(80,80)` to the lower right. You can pass a config filename after the corners.

Command-line corners override `central.hall` for that run. If you supply neither, central fits the map to the reported controllers. Controllers outside fixed bounds remain selectable under **Machines**.

## Optional configuration

Copy `config.example.lua` to `config.lua` to override the defaults. An optional second argument to the program selects a different config file and a separate pairing state.

- If a computer has multiple wireless modems, set `modem` to the full address from `components modem`.
- Automatic discovery uses multiblock scanner readings to distinguish controllers from cables, hatches, and single-block machines. Use `agent.controllers` to select controllers explicitly if a multiblock uses an unrecognized scanner format, or to give controllers custom display names. The keys are full controller addresses from `components -l` and the values are labels.
- An existing `agent.controller` setting keeps that agent in legacy single-controller mode. Remove it to discover all connected controllers, or replace it with `agent.controllers`.
- To advertise a custom agent name, set `agent.name` before pairing. A `central.machines` entry for the agent's modem address takes precedence over its saved agent label.
- For manual pairing, set `agent.centralModem` and a matching `central.machines` entry. Set the same `port` on all computers if you override `34173`.
- To save default hall bounds in config, set `central.hall`. `originX` and `originZ` are the upper-left corner. `spanX` and `spanZ` are the signed differences from that corner to the lower-right corner.
- Existing `dashboard` commands and config tables and `agent.dashboardModem` settings are still accepted. Prefer `central` and `agent.centralModem` for new setups.

To read the controller position during setup, run `lua` on the agent and enter the following using the controller's address. Exit the interpreter before starting the agent.

```lua
print(require("component").invoke("CONTROLLER_ADDRESS", "getCoordinates"))
```

## Run and verify

1. Look for a blue square on the map while an enabled machine is idle, and a green square once it starts work. Red takes priority when the scanner reports maintenance problems. Gray indicates a disabled machine or one whose last report is at least 10 seconds old.
2. Select a square or a row under **Machines** to see its label, coordinates, work permission, progress, maintenance count, and usage in EU/t. Maintenance and usage are read from the English `Problems` and `Currently uses` scanner lines. Central shows unavailable fields as `unknown` or `--`.
3. Disconnect one controller from the agent. Check that its square goes gray and the other machines keep updating. Reconnect it and check that it resumes reporting.
4. To try control, verify the control-room modem address and set it explicitly as `agent.centralModem` in the agent's config. The agent prints the paired address at startup. Set `agent.allowControl = true` and restart the agent. Select one controller and touch **Disable work** or **Enable work**. Check that central confirms the setting and that only the selected controller's work permission changes.

Wireless pairing grants monitoring. Enable commands on a trusted network and use OpenOS `useradd` on central to limit touchscreen input to its operators. Keep live config and pairing state on the in-game computers.

The map uses one X/Z plane. Central can track up to 99 controllers across its paired agents. Practical capacity depends on the computer and screen.

## Compatibility

Use the updated script on central and on agents that serve multiple controllers. Central also accepts legacy single-controller agents and existing pairings. Targeted at GTNH 2.9.0 with the pack's default Computronics machine driver and `GregtechMachineCoordinates` enabled. The standalone LSC power monitor covers bank-specific readings. In-game verification is pending. [Computronics machine configuration](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/computronics.cfg#L90)
