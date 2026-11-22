# CropsNH breeder

An OpenComputers robot tends one CropsNH crossbreeding plot. Plant the parents and prepare the offspring's soil once. The robot sets double crop sticks, analyzes and harvests the offspring, and puts the seeds and produce in a chest. Run it until it gets the crop you want or let it keep collecting new crosses.

**Target version** is GTNH 2.9.0 with CropsNH 2.0.140. In-game validation is pending.

## Setup

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

## Install and run

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

## What to expect

- The Geolyzer recognizes the crop-stick block. The robot reads species and stats from collected seeds. A low-resistance crop may need a few harvests to yield a seed, even with a Reinforced Spade. The console prints growth, gain, and resistance for each seed stack it collects.
- The robot retries the center plot after ten minutes without a usable result from an occupied plot. Give slow-growing crops more time with the optional third argument, in seconds. For example, `lua cropsnh-breeder.lua "Crop Name" 1 1200` allows twenty minutes. Keep the center clear of unrelated blocks and loose items.
- The parents stay in place for the whole run. The robot can only obtain crops that breed or spread on sticks. Crops with only a **Crop Breeder** recipe in NEI still need that machine.
- The robot shades the center, so check the target crop's light and nutrient requirements. Keep the area around the center open to light.
- If the robot cannot place or clear crop sticks, check the center soil, the robot's height above it, and whether your claim allows the robot to interact with blocks. You can restart the program at the same position.

The robot uses the stock pack's item NBT support and the GTNH Data Card's `decodeNBT` method. [GTNH 2.9.0 OpenComputers configuration](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack/blob/2.9.0/config/OpenComputers.cfg#L611-L618) · [GTNH Data Card implementation](https://github.com/GTNewHorizons/OpenComputers/blob/1.12.68-GTNH/src/main/scala/li/cil/oc/server/component/DataCard.scala#L147-L152)
