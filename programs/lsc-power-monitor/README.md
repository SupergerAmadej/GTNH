# LSC power monitor

An OpenOS dashboard for one Lapotronic Supercapacitor. It refreshes about once a second and shows stored EU, total capacity, charge percentage, a charge bar, five-second average input and output in EU/t, and passive loss in EU/t.

## Hardware and setup

- A formed Lapotronic Supercapacitor.
- A powered OpenComputers computer running OpenOS with a graphics card, screen, and keyboard. The terminal needs at least 42 columns and 12 rows.
- An OpenComputers Adapter placed directly against the LSC controller. Connect the Adapter to the computer with an OpenComputers Cable.
- An Internet Card and access to `raw.githubusercontent.com` for the in-game download.

## Install and run

Once the script is on GitHub, run these commands in OpenOS.

```sh
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/lsc-power-monitor/lsc-power-monitor.lua
lua lsc-power-monitor.lua
```

The monitor discovers a single LSC automatically. If it finds several, it prints their component addresses. Pass the full address of the one you want to monitor.

```sh
lua lsc-power-monitor.lua LSC_ADDRESS
```

Press **Ctrl+C** to return to the shell. For a repeatable install, replace `main` in the download URL with the commit SHA you have tested in-game.

## Mirror to four 3×2 screen walls

Build each wall from six OpenComputers Screen blocks of the same tier, three blocks wide and two tall. Leave a block gap between walls on the same plane so they form separate displays. Connect each wall to the computer's OpenComputers network with cable. Run `components screen` to check that each wall appears as one screen component.

```sh
lua lsc-power-monitor.lua --mirror
```

The monitor uses one graphics card to update each connected 3×2 wall in turn from the same LSC reading. The OpenOS terminal also shows the dashboard and reports how many 3×2 walls updated. The terminal counts as a wall if it is itself 3×2. Keep a keyboard on the terminal screen for Ctrl+C. To select a particular bank, run `lua lsc-power-monitor.lua --mirror LSC_ADDRESS`.

## Compatibility

Targeted at GTNH 2.9.0. The monitor uses the LSC callbacks for exact EU values and the 2.9.0 scanner fields for rates. Narrow viewports may display large EU values in scientific notation. [GTNH OpenComputers LSC callbacks](https://github.com/GTNewHorizons/OpenComputers/pull/179)

In-game verification is pending.
