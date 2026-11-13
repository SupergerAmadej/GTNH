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

Pair each agent once. With automatic discovery, connecting another compatible controller to that agent adds it to central without another pairing.

The agent console prints the number of reporting multiblocks, the number of connected OpenComputers components, and the remaining slots for components that each cost one slot. It refreshes the readout when the numbers change. Cards and other peripherals count toward the limit, and filesystems count as a quarter slot each before rounding down. The free-slot estimate uses the detected processor and GTNH defaults. If your server changes the limits or the processor is unrecognized, set `agent.componentLimit` to the actual limit in the agent's local config. [GTNH component counting](https://github.com/GTNewHorizons/OpenComputers/blob/1.12.68-GTNH/src/main/scala/li/cil/oc/server/machine/Machine.scala) · [GTNH 2.9.0 defaults](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/OpenComputers.cfg)

Both computers save their pairings under `state/` beside their config. Start each program again from the same directory to reuse the pairings. For an upgrade in a new directory, copy `state/` and any local `config.lua` across. Central keeps the last position for agents that go offline during the session.

To move an automatically paired agent to a new central computer, stop the agent and remove its `state/config.lua.agent` file before starting it again. To remove its entry from the old central computer, stop the program there and delete the file named after the agent's modem address inside `state/config.lua.dashboard/`. Central uses the original state directory to preserve existing pairings. If you use a custom config filename, the state paths use that filename in place of `config.lua`.

## Enable machine controls

Pair the agent in `agent` mode first. On the agent, press **Ctrl+C** and start it again from the same directory.

```sh
lua factory-control.lua agent-control
```

This enables per-machine controls for that run using the saved central modem address. If you paired using a custom config filename, pass the same filename after `agent-control`. On central, select a controller, touch **Disable work** or **Enable work**, then confirm. Restart an automatically paired agent in `agent` mode to return to monitoring.

For a manual pairing, you can keep controls enabled in normal `agent` mode by setting `agent.centralModem` and `agent.allowControl = true` in the local config.

### Start agent-control at boot

On a paired agent, stop the foreground process with **Ctrl+C**. Run these commands from the same directory you used to pair it. Use the filename you downloaded in the first command.

```sh
lua factory-control.lua agent-autostart
rc factory-control start
```

`agent-autostart` registers an OpenOS boot service for that script and its current central pairing. Pass the same config filename after `agent-autostart` if you used a custom one when pairing. The second command starts the service immediately. OpenOS starts it in the background on subsequent boots, including on headless agents.

Use `rc factory-control stop` to stop the running service and `rc factory-control disable` to turn off future boot starts. For upgrades, keep the registered script at the same path and run `rc factory-control restart` to load the updated file. To use a different script, config path, or central pairing, stop and disable the service, remove `/etc/rc.d/factory-control.lua`, then run `agent-autostart` again.

## Set the hall layout

Give `central` two `X,Z` world coordinates for opposite corners of the hall. At the default rotation, the first maps to the upper left and the second to the lower right. Either axis can run in decreasing order.

```sh
lua factory-control.lua -- central -120,35 -80,70
```

The `--` keeps OpenOS from treating negative coordinates as options. Two plain integers describe a square. For example, `central 20 80` maps `(20,20)` to the upper left and `(80,80)` to the lower right. You can pass a config filename after the corners.

Command-line corners override `central.hall` for that run. If you supply neither, central fits the map to the reported controllers. Controllers outside fixed bounds remain selectable under **Machines**.

Touch **Settings** in the bottom-right corner, then **Rotate left** or **Rotate right** to turn the map in 90-degree steps. The map previews each turn immediately. Use **Reset** for the original orientation and **Done** to return to the hall map. Central saves the rotation in `state/config.lua.dashboard/hall-rotation` for the next boot.

## Use the central display

- **Hall map** shows controller positions. Each tile has a status symbol, machine number, and short label. A tile like `+02` opens a list of the controllers that share that screen cell.
- **Issues** lists maintenance problems and offline controllers, with the problem count or time since the last report. **Machines** includes every reported controller, even outside the map.
- Touch a tile or list row for the full name, coordinates, agent, EU/t, progress, maintenance count, and work permission. At 100 × 22 or larger the details open beside the active view. On smaller screens use **Back** to return from the full-width detail view.
- Work controls require a separate confirmation tap. Central shows when the agent confirms, declines, or times out. Offline controllers and agents in monitoring mode have no work buttons.
- To clear a stale entry, open the offline controller from **Issues**, **Machines**, or the map. Tap **Remove offline**, then confirm. Its agent stays paired and the controller reappears when it reports again.

### Automate issue handling

Open **Settings** in the bottom-right corner. Both toggles default to **Off** and save their state for the next start.

- **Disable on maintenance** disables work on any online controller reporting maintenance problems, including existing faults when the toggle is turned on. Its agent must have remote control enabled. After repair, select the controller and enable work manually.
- **Emit redstone on issue** holds a redstone signal at strength 15 while **Issues** has at least one maintenance or offline entry. It returns to 0 when the last issue clears, when you turn the toggle off, or when central exits normally. Removing an offline entry clears that issue until the controller reports again.

Connect a dedicated OpenComputers Redstone I/O block to central's component network, or install a Redstone Card. With one redstone component, central uses it automatically and drives all six sides by default. With multiple components, set `central.redstone` to the full address of the intended device. Set `central.redstoneSide` to a side number from 0 to 5 to use just that side. Settings shows the output level or any connection error. [OpenComputers redstone API](https://ocdoc.cil.li/component:redstone)

## Start central at boot

On central, run the setup command from the same directory you use to start Factory Control. Use your downloaded filename and your hall corners.

```sh
lua factory-control.lua -- central-autostart -120,35 -80,70
```

Central opens in the foreground once OpenOS has a screen, and **Ctrl+C** returns to the shell. The setup remembers the script path, hall corners, and config path. Pass your config filename after the corners if you use one. Omit the corners to use your config bounds or automatic map fitting.

Run the setup again to change the saved corners or script path. `lua factory-control.lua central-autostart off` disables startup while keeping your existing shell commands and pairings.

## Optional configuration

Copy `config.example.lua` to `config.lua` to override the defaults. An optional second argument to the program selects a different config file and a separate pairing state.

- If a computer has multiple wireless modems, set `modem` to the full address from `components modem`.
- Automatic discovery uses multiblock scanner readings to distinguish controllers from cables, hatches, and single-block machines. Use `agent.controllers` to select controllers explicitly if a multiblock uses an unrecognized scanner format, or to give controllers custom display names. The keys are full controller addresses from `components -l` and the values are labels.
- Automatically discovered controllers use known English game names where available. Other names are formatted from their registry IDs. A label in `agent.controllers` takes precedence.
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

1. Look for blue `S` while an enabled machine is on standby and green `R` once it starts work. Red `!` indicates maintenance and takes priority over other states for reporting controllers. Amber `D` indicates disabled work. Gray `?` means the last report is at least 10 seconds old.
2. Select a square or a row under **Machines** to see its label, coordinates, work permission, progress, maintenance count, and usage in EU/t. Maintenance and usage are read from the English `Problems` and `Currently uses` scanner lines. Central shows unavailable fields as `unknown` or `--`.
3. Disconnect one controller from the agent. Check that it goes gray, appears under **Issues**, and has no work controls. Reconnect it and check that it resumes reporting.
4. Restart the paired agent in `agent-control` mode. Select one controller, touch **Disable work** or **Enable work**, and confirm. Check that central confirms the setting and that only the selected controller's work permission changes.
5. With a control-enabled agent, turn on **Disable on maintenance** and check that a reporting controller with a maintenance fault stops accepting work. With a Redstone I/O connected, turn on **Emit redstone on issue** and verify that the output stays high while an issue is listed and goes low when the list clears.

Wireless pairing grants monitoring. Enable commands on a trusted network and use OpenOS `useradd` on central to limit touchscreen input to its operators. Keep live config and pairing state on the in-game computers.

The map uses one X/Z plane. Central can track up to 99 controllers across its paired agents. Practical capacity depends on the computer and screen.

## Compatibility

Use the updated script on central and on agents that serve multiple controllers. Central also accepts legacy single-controller agents and existing pairings. Targeted at GTNH 2.9.0 with the pack's default Computronics machine driver and `GregtechMachineCoordinates` enabled. The standalone LSC power monitor covers bank-specific readings. In-game verification is pending. [Computronics machine configuration](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/computronics.cfg#L90)
