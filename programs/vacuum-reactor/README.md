# Vacuum reactor control

Run one OpenComputers agent per IC2 vacuum reactor and a central dashboard for the fleet. The agent replaces hot coolant cells and spent fuel from local storage. If central goes offline, each armed agent runs its reactor as needed to recharge its local battery buffer. The central screen shows reactor state, hull heat, EU/t, hottest cell, and lowest fuel durability. Select a reactor to disable it and see whether it stopped.

## Reactor layout

Use the IC2 Nuclear Reactor with six chambers, 40 **Quad Fuel Rods (Uranium)** (`R`), and 14 **360k He Coolant Cells** (`C`). Rows run top to bottom in the reactor GUI.

```text
C R R R C R R C R
R R C R R R R C R
C R R R R C R R R
R R R C R R R R C
R C R R R R C R R
R C R R C R R R C
```

You can load the layout yourself or stock the supply inventory and let the agent fill empty slots while stopped. The agent checks every slot before turning on. It stops and latches a fault if a component is missing while running, a slot holds the wrong item, or a swap fails. After fixing a fault, arm again at that reactor's keyboard.

## Hardware and wiring

On each reactor computer, use OpenOS, a keyboard and screen for local arming, and a Network Card. Cable an **Adapter**, **Transposer**, and **Redstone I/O** to that computer. Connect them to the same reactor.

1. Put the Adapter against a reactor chamber so OpenOS sees `reactor_chamber`. Use only one chamber connection on the Adapter or select the intended component address in config.
2. Put the Transposer directly against a reactor chamber. Place a supply inventory and a return inventory against two other Transposer faces. Put fresh quad uranium rods and fully cooled 360k He cells in supply so the agent can identify it. The remaining inventory holds hot cells and spent rods. Route hot cells through your Vacuum Freezer and send cooled cells back to supply. Leave the reactor slots under the agent's control.
3. Use a dedicated Redstone I/O for this reactor alone. Connect any output face to the reactor's run input. Automatic setup drives all six output faces at level 15 to run and 0 to stop. Keep a local way to cut the run signal. A hard computer crash can leave a Redstone I/O output high, and any other signal into the reactor or its chambers can override shutdown. [OpenComputers redstone](https://ocdoc.cil.li/component:redstone) · [Transposer](https://ocdoc.cil.li/component:transposer)
4. Put an Adapter against the reactor's **GregTech Battery Buffer** and connect it to the same computer. Run `components gt_batterybuffer` to verify the driver. The program measures charge across the installed batteries by adding their stored EU and capacities. [Computronics battery buffer driver](https://github.com/GTNewHorizons/Computronics/blob/1.9.13-GTNH/src/main/java/pl/asie/computronics/integration/gregtech/gregtech5/DriverBatteryBuffer.java)

Use a Tier 2 or 3 touchscreen and GPU for central, with a viewport of at least 64 × 12. Give it a modem that can reach every agent in both directions. Wireless cards let the reactor computers keep their component networks separate. Keep the reactor and its controller loaded together and power the computer independently of its reactor. Use an Internet Card for installation. [OpenComputers modems](https://ocdoc.cil.li/component:modem)

## Install and pair

From OpenOS, run this on central and each agent once these files are available on GitHub.

```sh
mkdir vacuum-reactor
cd vacuum-reactor
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/vacuum-reactor/install.lua
lua install.lua
```

For a repeatable install, replace `main` in the installer URL with the tested commit SHA and pass the same SHA to `lua install.lua SHA`.

Start central on the control-room computer.

```sh
lua vacuum-reactor.lua central
```

Start an agent on each reactor computer.

```sh
lua vacuum-reactor.lua agent
```

On central, touch **Add reactor agents**, then touch each agent you want to pair. The window stays open for 60 seconds. Touch **Close pairing** to return to the dashboard sooner. The agent console shows the same short name as the dashboard. You can pair an agent before its hardware is complete.

An incomplete agent shows **Setup**. Select it and open **Setup details** to see missing or ambiguous components, storage faces, or battery readings. The list refreshes as you connect equipment. Keep the local run line cut during setup. The agent checks whether it can control its Redstone I/O and reads the reactor, and the first local arm checks whether the run signal actually reaches the reactor.

Both computers save pairings under `state/` beside the optional config. Run them from the same directory on future starts. To pair an agent with a different central computer, stop the agent and remove its `state/config.lua.agent` file, then restart and pair it. On the old central computer, stop the dashboard and remove that agent's modem address file from `state/config.lua.central/`. For a custom config filename, the state paths use that filename.

## Run

- The agent starts disarmed. Once paired and set up, press **A** at the reactor to arm it. It checks the layout, services any slots that need attention, and applies the run signal. Press **D** locally to disable or **Ctrl+C** to stop the agent and drop its run signal.
- At central, touch a row and then touch **Disable** and **Confirm stop**. The keyboard works too. Select with the arrow keys and press **D** twice. Central confirms shutdown after that agent reports the redstone output off, the reactor inactive, and zero EU/t. If a command goes unconfirmed, check that reactor locally.
- During maintenance, the agent drops redstone and waits at least two game seconds and for verified zero output before moving items. It verifies each replacement and checks the full layout again before it can resume. A remote disable, local disable, or fault requires **A** at the reactor before it can run again, including after an agent restart.
- Central marks a reactor **Offline** after five seconds without a report. An armed agent switches to battery control after five seconds without a reply from central, or immediately if it starts with central already offline. It starts charging at **25% or below**, keeps charging through the middle of the range, and holds the reactor in **Standby** at **95% or above**. Local coolant and fuel servicing continues in standby. A missing or unreadable battery reading during fallback stops the reactor and requires local rearming after repair. When central replies again, an armed reactor returns to its normal running mode.

## Optional overrides

Copy `config.example.lua` to `config.lua` if you want to name agents or override discovery. A second argument to either role selects a different config file and its own pairing state.

- Set `agent.name` to label an agent before pairing. Existing manual pairing through `agent.centralModem` and `central.reactors` still works. Both ends must use the same `port`. If there are multiple modems, set `modem` to the one to use.
- Run `components -l` to find full addresses when more than one component of a type is connected. Set `agent.reactor`, `agent.transposer`, `agent.redstone`, or `agent.batteryBuffer` to choose a specific device. Automatic setup requires a GregTech Battery Buffer with at least one installed battery. Existing manual configs without a buffer retain their previous local behavior.
- If there are extra inventories next to the Transposer or the supply is empty, set `reactorSide`, `supplySide`, or `returnSide` to the relevant **world direction from the Transposer**. Set `redstoneSide` to limit output to one **device-relative face**, such as `front` or `left`.
- `coolantSwapPercent` defaults to **75% of capacity used** and `maxHullHeat` defaults to **500 HU**. OpenComputers reads the rounded GT item-damage percentages. Supply should contain unused rods and cells returned by the freezer at zero heat.

When upgrading an existing installation, keep your local config and `state/` directory. Update both central and the agents for discovery and setup diagnostics.

## First in-game check

1. Cut the reactor's run signal before setup. Pair the reactor from central and review any **Setup** issues. Once connected, check that it appears as **Disabled**. Verify the chamber Adapter, Transposer, and dedicated Redstone I/O belong to the same reactor before enabling its run line.
2. Stock the two item types, arm locally, and check that the reactor reaches **Running** with the expected EU/t and low hull heat. Watch a coolant swap and a spent-rod replacement. Confirm the signal drops before any item moves, hot cells and spent rods land in the return inventory, and the GUI layout is correct after refilling.
3. Disable it from central. Check both the confirmation and the reactor's actual redstone and EU/t. Verify the other reactors stay in their previous states. Restart the agent and confirm it waits for local arming.
4. With the reactor stopped, remove the available replacement item and leave a slot that needs that item. Arm and confirm the fault keeps redstone off. Restock and rearm to verify recovery.
5. With an armed reactor and the buffer between 25% and 95%, stop central and check that the reactor goes into standby. Draw the buffer down to 25%, let it charge, and verify the run signal drops at 95%. Check the actual charge in-game. A small buffer can move past either threshold between readings or while the reactor is stopping.

## Compatibility

Targeted at **GTNH 2.9.0**, OpenComputers 1.12.68-GTNH, and the IC2 electric reactor. In-game verification is pending. [GTNH 2.9.0 release](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/releases/tag/2.9.0) · [OpenComputers 1.12.68-GTNH](https://github.com/GTNewHorizons/OpenComputers/releases/tag/1.12.68-GTNH)
