# HDD copy

Copies the on-disk contents of one managed OpenComputers HDD to an empty drive. It includes hidden files, empty directories, and OpenOS boot files if present. The destination keeps its own drive address and label.

## Hardware and setup

- A powered computer running OpenOS with both managed HDDs visible to it. The source can be the HDD running OpenOS.
- An empty, writable destination HDD with enough space for the source contents.
- An Internet Card and access to `raw.githubusercontent.com` to download the script.

Run `mount` to identify the two drives by label and address. The address appears in the first column. The drive mounted at `/` is the OpenOS boot drive. Stop programs that write to either HDD before copying.

## Install and run

Once the script is on GitHub, run these commands in OpenOS. Replace `SOURCE_ADDRESS` and `DESTINATION_ADDRESS` with the addresses shown by `mount`. A unique prefix is enough.

```sh
wget https://raw.githubusercontent.com/SupergerAmadej/GTNH/main/programs/hdd-copy/hdd-copy.lua
lua hdd-copy.lua SOURCE_ADDRESS DESTINATION_ADDRESS
```

After a successful copy, the script removes `/programs/hdd-copy.lua` from the destination HDD if the file is present. Wait for `Copy complete` before removing either HDD. If the copy stops partway through, use an empty destination to try again. To boot from the copy, shut down the computer and start it with the copied HDD in place of the original.

## Compatibility

Targets GTNH 2.9.0 OpenOS and managed HDDs. In-game verification is pending.
