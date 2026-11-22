# CropsNH breeder

Use an OpenComputers robot to collect CropsNH seeds in GTNH 2.9.0. **Field mode** plants parents, runs intermediate crosses, and breeds toward a stat target. **Single-plot mode** collects seeds from one cross you set up by hand.

Targets CropsNH 2.0.140. The `1/1/1` to `31/31/31` Wheat run passed in simulation. In-game validation is pending.

## Robot hardware and tools

| Part | Where it goes |
| --- | --- |
| Tier 2 Computer Case, Tier 1 APU, Tier 2 Memory, Tier 1 Screen, Keyboard, and Lua BIOS EEPROM | Assemble the robot in an OpenComputers Electronics Assembler. |
| Managed HDD with OpenOS | Install OpenOS using a Disk Drive and an OpenOS floppy, or put a preloaded HDD in the robot during assembly. A Tier 1 HDD is enough for the program. |
| Inventory Upgrade and Inventory Controller Upgrade | Install both in the robot. |
| Geolyzer | Put the **OpenComputers Geolyzer block** into a robot upgrade slot in the Electronics Assembler. |
| Tier 1 or better Data Card | Install in the robot. The script uses it to read crop IDs and stats from harvested seeds. |
| Internet Card | Install in whichever computer runs `wget`. This can be the computer preparing the robot's HDD. |

[Robot assembly and preloaded HDDs](https://github.com/GTNewHorizons/OpenComputers/blob/1.12.68-GTNH/src/main/resources/assets/opencomputers/doc/en_US/block/robot.md) · [Geolyzer upgrade](https://github.com/GTNewHorizons/OpenComputers/blob/1.12.68-GTNH/src/main/resources/assets/opencomputers/doc/en_US/block/geolyzer.md)

| Robot slot | Item |
| --- | --- |
| Tool slot | **Reinforced Spade** |
| Inventory slot 1 | **CropsNH crop sticks**. Start with a stack for field mode or 16 for single-plot mode. |
| Inventory slot 2 | **Plant Lens** |
| Inventory slots 3 onward | Leave empty for seeds and drops. |

## Test field mode with Wheat

This test starts with **one `1/1/1` CropsNH Wheat seed bag**. The robot plants it and replaces the parent with better offspring until it collects a `31/31/31` seed.

### 1. Build the dock and plot

- Put the **seed chest directly below** the robot and the **output chest directly above** it. Place the powered OpenComputers Charger against a horizontal side and turn it on with a lever.
- Face the robot down the row. Prepare the **center four blocks straight ahead of the dock** and the **parent one block left of the center**, relative to where the robot is facing.
- Put lit, hydrated farmland **two blocks below the robot's flight level** at both tiles. Leave the block immediately above each soil block empty. That's where the robot places the crop sticks. Keep the flight path over the row and parent clear.
- Give a Crop Manager water, fertilizer, and Weed-EX. Set it to tend both tiles, enable fertilizing, and turn harvesting off. Keep the parent at **101+ stored fertilizer** so spreading can improve its stats. Put the Wheat seed bag in the lower chest. [CropsNH spreading rules](https://github.com/GTNewHorizons/CropsNH/blob/2.0.140/src/main/java/com/gtnewhorizon/cropsnh/handler/ConfigurationHandler.java#L158-L189)

```text
Forward from dock   0       1       2       3       4
One block left                                     [P]
Aisle           [Dock >]    .       .       .      [C]

[P] Parent tile   [C] Center tile
```

### 2. Choose the HDD to install on

**Installing on the robot.** Boot OpenOS on the robot and start in its home directory.

```sh
cd /home
```

**Preloading the HDD on another computer.** Run `mount` and find the robot HDD by its label and the address in the first column. The prep computer's boot drive appears at `/` and can also appear under `/mnt` with the same address.

If the robot HDD is blank, insert an OpenOS floppy. Substitute the floppy's address and the robot HDD's address from `mount` before running the installer. [OpenOS installer options](https://github.com/GTNewHorizons/OpenComputers/blob/1.12.68-GTNH/src/main/resources/assets/opencomputers/loot/openos/lib/core/install_basics.lua#L7-L20)

```sh
install --from=FLOPPY_ADDRESS --to=ROBOT_HDD_ADDRESS --nosetboot --noreboot
```

Replace `/mnt/abc` with the robot HDD's actual mount path. Confirm that `pwd` shows its `home` directory before downloading.

```sh
cd /mnt/abc/home
pwd
```

### 3. Download the program and write the Wheat config

Run this block from the destination HDD's `home` directory. Use a fresh `cropsnh-wheat` directory. The installer downloads all three program files from `main`.

```sh
mkdir cropsnh-wheat
cd cropsnh-wheat
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/cropsnh-breeder/install.lua
lua install.lua
echo 'return {retrySeconds=2400,plots={{crop="wheat",stats=true}}}' > config.lua
```

For a repeatable install, use the same commit SHA in place of `main` in the installer URL and in `lua install.lua SHA`.

### 4. Run the test on the robot

If you preloaded the HDD, shut down the prep computer and move the HDD to the robot. Boot OpenOS with the robot at the dock facing the plot.

```sh
cd /home/cropsnh-wheat
lua cropsnh-breeder.lua field Wheat 31/31/31 1
```

The run stops after depositing **at least one `31/31/31` Wheat seed** in the upper chest. Early plants can take several harvests to drop a seed. The `2400`-second retry gives low-growth Wheat time to mature. The upper chest also receives produce and surplus seeds, so leave space for long runs.

To multiply maxed seeds, use the same plot with a `31/31/31` starter or a maxed plant from a completed run. Set the final argument to your desired seed count. The last harvest can exceed that count.

```sh
lua cropsnh-breeder.lua field Wheat 31/31/31 16
```

## Multiple plots with one robot

Use the same dock and an open flight path over loaded ground. Put the centers **4, 8, 12, … blocks** ahead of it, following the order of `plots` in the config. The `left`, `right`, `front`, and `back` parent tiles are immediately adjacent to each center, relative to the robot’s facing at the dock. Leave unused parent tiles empty. [GTNH robot flight settings](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/OpenComputers.cfg#L1594-L1601)

- List each planned cross with its output `crop` ID and `parents`. Use the IDs printed by the script. An optional `label` lets you target the crop by its display name. Duplicate a plot entry to run the same cross at several centers.
- Use NEI to prepare the soil, sub-soil, and light for each crop. Leave the center and parent tiles bare. Stock the lower chest with one CropsNH seed bag per starter parent. The robot breeds intermediate seeds using the configured crosses. Supply any machine-only intermediate seed from the Crop Breeder.
- For a stat target, add a `stats = true` plot for that crop. Prepare its center and left parent tile with matching soil, and keep the parent above 100 stored fertilizer.

The [example config](config.example.lua) uses Wheat and Brown Mushroom for Oak Bonsai, then Oak Bonsai and Sugar Cane for Birch Bonsai. The third plot raises Birch Bonsai's stats. On a field prepared for those three plots, copy the example to a separate config and run it as follows. [CropsNH bonsai recipes](https://github.com/GTNewHorizons/CropsNH/blob/2.0.140/src/main/java/com/gtnewhorizon/cropsnh/loaders/MutationLoader.java#L275-L287)

```sh
cp config.example.lua bonsai.lua
lua cropsnh-breeder.lua field "Birch Bonsai" 31/31/31 1 bonsai.lua
```

The field arguments after the crop name are the **minimum Growth/Gain/Resistance**, the **number of qualifying seeds**, and an optional **config filename**. They default to `1/1/1`, `1`, and `config.lua`.

### Restart a field run

Press **Ctrl+C** to stop. The robot tries to return to the dock. If it stops elsewhere, return it by hand and face it down the row before restarting. The program records planted parents in `state/` beside the config. Keep the same positions and assignments when restarting. Add new plots at the end of the config.

If the robot reports an interrupted planting, clear the named parent tile and restart from the dock. Coordinates in messages count blocks forward and right from the dock.

## Single-plot mode

Choose a crop-stick cross in NEI. Plant the parents by hand on the required sides of one center tile and leave the center bare. Put the robot directly above that center with an output chest against its **front** at robot height. Place a powered, redstone-enabled Charger against another side. A Crop Manager can tend the crops with harvesting disabled.

For a standalone install, download the script in a fresh directory and start it.

```sh
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/cropsnh-breeder/cropsnh-breeder.lua
lua cropsnh-breeder.lua
```

From an existing field installation, run `lua cropsnh-breeder.lua` from its directory.

The default run collects one seed of any crop. Pass a crop name and a count to target a species, or use `any 0` to collect continuously. An optional third argument sets the stalled-crop retry in seconds. The default is `600`.

```sh
lua cropsnh-breeder.lua Wheat 4
lua cropsnh-breeder.lua any 0
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Robot waits for charge | Make sure the adjacent Charger has power and a redstone signal. |
| Robot reports a blocked passage or cannot place sticks | Check the clear flight path, crop-stick height, soil, and the robot's block interaction permissions. |
| Wheat grows slowly or yields no seeds | Check light, water, fertilizer, and Weed-EX. Allow time for the parent to mature and for low-resistance offspring to drop a seed. |
| Robot waits for chest space | Clear space in the chest named on the console. |
| Script cannot read seed NBT | Check `allowItemStackNBTTags=true` and that the robot has a Data Card with `decodeNBT`. |

[GTNH 2.9.0 NBT setting](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/OpenComputers.cfg#L611-L618) · [GTNH Data Card implementation](https://github.com/GTNewHorizons/OpenComputers/blob/1.12.68-GTNH/src/main/scala/li/cil/oc/server/component/DataCard.scala#L147-L152)
