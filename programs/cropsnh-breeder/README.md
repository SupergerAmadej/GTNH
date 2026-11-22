# CropsNH breeder

An OpenComputers robot places double crop sticks, analyzes and harvests offspring, and puts seeds and produce in a chest. Run it over one plot with parents you plant by hand, or set up a row of plots and let the robot plant parents, run intermediate crosses, and select for a stat target.

**Target version** is GTNH 2.9.0 with CropsNH 2.0.140. In-game validation is pending.

## One plot

1. Build a robot with OpenOS, an Inventory Upgrade, an Inventory Controller Upgrade, a Geolyzer, and a Tier 1 or better Data Card. Add an Internet Card for `wget`. Use a chassis with enough component slots for these upgrades and your OpenOS hardware.
2. Use NEI's **Crop Breeding** or **Crop Mutation Pools** tab to choose the parents and the center plot's soil and sub-soil. Plant the parents on the four sides of the center as required by the recipe. Leave the center soil bare. Feed the plot with a Crop Manager if needed. Leave the manager's harvesting disabled.
3. Place the robot directly over the center, one block above where the crop sticks go. Place a chest against the robot's front and a powered OpenComputers Charger against another side of the robot. Turn on the Charger with redstone. You can attach the robot to the underside of the Charger to leave the center bare.
4. Equip a **Reinforced Spade** in the tool slot. Put 16 CropsNH crop sticks in the first inventory slot and a **Plant Lens** in the second. The other slots hold drops until the robot can put them in the chest.

From above, the field looks like this. Use only the parent positions needed for your cross.

```text
       Parent
Parent Center Parent
       Parent
```

### Install and run

Run these commands in the robot's OpenOS terminal.

```sh
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/cropsnh-breeder/cropsnh-breeder.lua
lua cropsnh-breeder.lua
```

The default run stops after putting one seed of any species into the chest. To test it, plant Wheat next to the center on matching soil and let the robot collect a seed from a spread. Higher resistance makes seeds more likely to drop.

```sh
lua cropsnh-breeder.lua "Crop Name"
lua cropsnh-breeder.lua "Crop Name" 4
lua cropsnh-breeder.lua any 0
```

The first two commands take the crop name shown in NEI or the crop ID printed on the console. They stop after one or four matching seeds, respectively. The last command keeps collecting crosses until you press **Ctrl+C**. Any other seeds also go into the chest. The robot waits if the chest fills or its charge runs low.

### What to expect

- The Geolyzer recognizes the crop-stick block. The robot reads species and stats from collected seeds. A low-resistance crop may need a few harvests to yield a seed, even with a Reinforced Spade. The console prints growth, gain, and resistance for each seed stack it collects.
- The robot retries the center plot after ten minutes without a usable result from an occupied plot. Give slow-growing crops more time with the optional third argument, in seconds. For example, `lua cropsnh-breeder.lua "Crop Name" 1 1200` allows twenty minutes. Keep the center clear of unrelated blocks and loose items.
- The parents stay in place for the whole run. The robot can only obtain crops that breed or spread on sticks. Crops with only a **Crop Breeder** recipe in NEI still need that machine.
- The robot shades the center, so check the target crop's light and nutrient requirements. Keep the area around the center open to light.
- If the robot cannot place or clear crop sticks, check the center soil, the robot's height above it, and whether your claim allows the robot to interact with blocks. You can restart the program at the same position.

The robot uses the stock pack's item NBT support and the GTNH Data Card's `decodeNBT` method. [GTNH 2.9.0 OpenComputers configuration](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/OpenComputers.cfg#L611-L618) · [GTNH Data Card implementation](https://github.com/GTNewHorizons/OpenComputers/blob/1.12.68-GTNH/src/main/scala/li/cil/oc/server/component/DataCard.scala#L147-L152)

## Multiple plots with one robot

Use the same robot hardware and tool slots. Put about a stack of crop sticks in slot 1 for the initial planting. This mode uses a **dock** with the seed chest directly below the robot, the output chest directly above it, and a powered, redstone-enabled Charger touching a horizontal side. Start the robot at the dock, facing down the row of plots.

```text
Layout from above, with the robot facing right at the dock

                 left parent       left parent       left parent
Dock  ───────────  Plot 1  ────────  Plot 2  ────────  Plot 3  ── …
                 right parent      right parent
```

The crop center tiles are **4, 8, 12, … blocks straight ahead of the dock**, at crop-stick height one block below the robot. Keep a clear flight path at robot height over the row and each parent tile. The parent tiles are one block from the center in the four directions named in the config, relative to the way the robot faces at the dock. Leave unused parent tiles empty. The pack allows flight close to the ground, so keep the route over terrain and in loaded chunks. [GTNH 2.9.0 flight settings](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/OpenComputers.cfg#L1594-L1601)

### Install field mode

Install in a fresh directory so the installer can fetch all three files from the same Git ref.

```sh
mkdir cropsnh-field
cd cropsnh-field
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/cropsnh-breeder/install.lua
lua install.lua
cp config.example.lua config.lua
edit config.lua
```

For a pinned install, use the same commit SHA in the URL and as the argument to `lua install.lua SHA`.

### Test field mode with Wheat

For a one-plot test, prepare hydrated farmland at the center four blocks ahead of the dock and one block to its left. Leave both tiles bare and keep them lit. Put one `1/1/1` CropsNH Wheat seed bag in the lower chest. Use a Crop Manager with water, fertilizer, and Weed-EX. Enable fertilizing and disable harvesting. The Wheat parent needs **101+ stored fertilizer** to improve by spreading.

Run these commands at the dock in the robot's OpenOS terminal. The longer retry interval gives low-growth Wheat time to mature before the robot replaces a stalled cross.

```sh
cd /home
mkdir cropsnh-wheat
cd cropsnh-wheat
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/cropsnh-breeder/install.lua
lua install.lua
echo 'return {retrySeconds=2400,plots={{crop="wheat",stats=true}}}' > config.lua
lua cropsnh-breeder.lua field Wheat 31/31/31 1
```

### Prepare the plots and start

1. In `config.lua`, list the crosses available in your field. Each `crop` and parent uses its CropsNH crop ID, as printed by the one-plot mode. An optional `label` lets you use the display name on the command line. The order of the entries sets their locations. List the same cross more than once to grow it at several centers.
2. Prepare the soil, sub-soil, light, and nutrients for each crop according to NEI. Leave the center and parent tiles bare. Place **CropsNH seed bags** for the starter crops in the seed chest. Supply one seed per parent tile that needs it. The robot plants the parents and puts intermediate seeds into the same chest for later crosses. For a crop that can only be made in the Crop Breeder, supply its seed in the chest.
3. For automatic stat improvement, give the target crop a separate entry with `stats = true`. Prepare both that center and its **left** parent tile for the target crop. Power a Crop Manager and supply fertilizer and Weed-EX. Enable fertilizing and disable harvesting. Keep stored fertilizer at the parent above **100** so spreading can raise stats under the default rules. [CropsNH spreading stat rules](https://github.com/GTNewHorizons/CropsNH/blob/2.0.140/src/main/java/com/gtnewhorizon/cropsnh/handler/ConfigurationHandler.java#L158-L189)

The included example runs **Wheat + Brown Mushroom → Oak Bonsai**, then **Oak Bonsai + Sugar Cane → Birch Bonsai**. The third plot spreads Birch Bonsai. Put Wheat, Brown Mushroom, and Sugar Cane seed bags in the lower chest. [CropsNH bonsai mutation recipes](https://github.com/GTNewHorizons/CropsNH/blob/2.0.140/src/main/java/com/gtnewhorizon/cropsnh/loaders/MutationLoader.java#L275-L287)

```sh
lua cropsnh-breeder.lua field "Birch Bonsai" 31/31/31 1
```

The arguments after the crop name are the minimum Growth/Gain/Resistance and the number of qualifying seeds to collect. They default to `1/1/1` and `1`. The robot returns to the dock between jobs. It only schedules intermediate crosses for parents it still needs, using the routes described in `config.lua`. It replaces the stat plot's parent with an offspring whose stats are closer to the target. Allow time for the replacement parent to grow. The output chest also receives produce and surplus seeds, so leave space for those on long runs.

### Restarting a field run

Start each run at the same dock facing the same way. The robot attempts to return to the dock if interrupted. If it cannot, return it to the dock by hand before restarting. The robot saves the parents it has planted under `state/` beside your config. Keep the same positions and parent assignments for those plots. You can append plots to the end of the config. If power cuts out while a parent is being planted, the program identifies that tile on restart. Clear that tile before restarting again so the robot can replant it. Coordinates in messages are blocks forward and right from the dock.
