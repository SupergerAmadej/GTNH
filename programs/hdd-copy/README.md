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

## Install a program and start it at boot

Pass a program folder name as the optional third argument. This requires an Internet Card on the computer doing the copy.

```sh
lua hdd-copy.lua SOURCE_ADDRESS DESTINATION_ADDRESS lsc-power-monitor
```

The script installs the program from this repository's `main` branch into `/programs/<program>` on the destination. It uses the program's `install.lua` if present. If that directory already exists, the new installation gets a numbered suffix such as `-2`.

On a copy of OpenOS, `/home/.shrc` launches the new program in the foreground when the interactive shell starts. The new command runs first, and existing `.shrc` commands run after it exits. Remove the added first line to disable the new startup command.

Use `factory-control` for central mode or `factory-control:agent` for agent mode. Hardware, pairing, and any program-specific configuration follow the selected program's README.

## Compatibility

Targets GTNH 2.9.0 OpenOS and managed HDDs. In-game verification is pending.
