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
2. Put the Transposer directly against a reactor chamber. Place two inventories against two other Transposer faces. Stock one with fresh quad uranium rods and fully cooled 360k He cells. Leave space in the other for hot cells and spent rods. Route the hot cells through your Vacuum Freezer and send cooled cells back to supply. Leave the reactor slots under the agent's control.
3. Wire one dedicated Redstone I/O face to activate the reactor with level 15 and stop it at 0. Any other signal into the reactor or its chambers can override shutdown. Keep a local way to cut the run signal. A hard computer crash can leave a Redstone I/O output high. [OpenComputers redstone](https://ocdoc.cil.li/component:redstone) · [Transposer](https://ocdoc.cil.li/component:transposer)
4. Put an Adapter against the reactor's **GregTech Battery Buffer** and connect it to the same computer. Run `components gt_batterybuffer` to verify the driver. The program measures charge across the installed batteries by adding their stored EU and capacities. [Computronics battery buffer driver](https://github.com/GTNewHorizons/Computronics/blob/1.9.13-GTNH/src/main/java/pl/asie/computronics/integration/gregtech/gregtech5/DriverBatteryBuffer.java)

Use a Tier 2 or 3 touchscreen and GPU for central, with a viewport of at least 64 × 12. Give it a modem that can reach every agent in both directions. Wireless cards let the reactor computers keep their component networks separate. Keep the reactor and its controller loaded together and power the computer independently of its reactor. Use an Internet Card for installation. [OpenComputers modems](https://ocdoc.cil.li/component:modem)

## Install and configure

From OpenOS, run this on central and each agent once these files are available on GitHub.

```sh
mkdir vacuum-reactor
cd vacuum-reactor
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/vacuum-reactor/install.lua
lua install.lua
cp config.example.lua config.lua
edit config.lua
```

For a repeatable install, replace `main` in the installer URL with the tested commit SHA and pass the same SHA to `lua install.lua SHA`.

- Run `components modem` on each computer to find its modem address. Set `agent.centralModem` on each reactor computer to central's full modem address. In central's `central.reactors`, enter each reactor computer's full modem address and the name it should show. Use the same `port` everywhere. When a computer has multiple modems, set `modem` to the intended local address.
- On each agent, set `reactorSide`, `supplySide`, and `returnSide` to the corresponding **world directions from the Transposer**. Set `redstoneSide` to the **device-relative output face** driving that reactor, such as `front` or `left`. The template's directions are examples. If there is more than one component of a given type, use `components -l` to find and set its full address.
- Set `agent.batteryBuffer = true` to require one connected buffer, or set it to the full component address to select a specific one. Older configs pick up a single connected buffer automatically. An older config without a connected buffer keeps its previous local behavior. Update both central and the agents so central can acknowledge their reports.
- The default coolant swap point is **75% of capacity used**. The default hull cutoff is **500 HU**. `coolantSwapPercent` and `maxHullHeat` in the agent config apply to that reactor. OpenComputers reads the rounded GT item-damage percentages. Supply should contain unused rods and cells returned by the freezer at zero heat.

## Run

Start central on the control-room computer.

```sh
lua vacuum-reactor.lua central
```

Start an agent on each reactor computer.

```sh
lua vacuum-reactor.lua agent
```

- The agent starts with its output off. Press **A** at the reactor to arm it. It checks the layout, services any slots that need attention, and applies the run signal. Press **D** locally to disable or **Ctrl+C** to stop the agent and drop its run signal.
- At central, touch a row and then touch **Disable** and **Confirm stop**. The keyboard works too. Select with the arrow keys and press **D** twice. Central confirms shutdown after that agent reports the redstone output off, the reactor inactive, and zero EU/t. If a command goes unconfirmed, check that reactor locally.
- During maintenance, the agent drops redstone and waits at least two game seconds and for verified zero output before moving items. It verifies each replacement and checks the full layout again before it can resume. A remote disable, local disable, or fault requires **A** at the reactor before it can run again, including after an agent restart.
- Central marks a reactor **Offline** after five seconds without a report. An armed agent switches to battery control after five seconds without a reply from central, or immediately if it starts with central already offline. It starts charging at **25% or below**, keeps charging through the middle of the range, and holds the reactor in **Standby** at **95% or above**. Local coolant and fuel servicing continues in standby. A missing or unreadable battery reading during fallback stops the reactor and requires local rearming after repair. When central replies again, an armed reactor returns to its normal running mode.

## First in-game check

1. Cut the reactor's run signal before setup. With both programs running, check that the correct agent appears as **Disabled**. Verify the chamber and Transposer are on the same reactor and the output face is the one wired to it.
2. Stock the two item types, arm locally, and check that the reactor reaches **Running** with the expected EU/t and low hull heat. Watch a coolant swap and a spent-rod replacement. Confirm the signal drops before any item moves, hot cells and spent rods land in the return inventory, and the GUI layout is correct after refilling.
3. Disable it from central. Check both the confirmation and the reactor's actual redstone and EU/t. Verify the other reactors stay in their previous states. Restart the agent and confirm it waits for local arming.
4. With the reactor stopped, remove the available replacement item and leave a slot that needs that item. Arm and confirm the fault keeps redstone off. Restock and rearm to verify recovery.
5. With an armed reactor and the buffer between 25% and 95%, stop central and check that the reactor goes into standby. Draw the buffer down to 25%, let it charge, and verify the run signal drops at 95%. Check the actual charge in-game. A small buffer can move past either threshold between readings or while the reactor is stopping.

## Compatibility

Targeted at **GTNH 2.9.0**, OpenComputers 1.12.68-GTNH, and the IC2 electric reactor. In-game verification is pending. [GTNH 2.9.0 release](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/releases/tag/2.9.0) · [OpenComputers 1.12.68-GTNH](https://github.com/GTNewHorizons/OpenComputers/releases/tag/1.12.68-GTNH)
