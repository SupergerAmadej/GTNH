# GTNH OpenComputers programs

Lua programs for in-game computers in a GregTech: New Horizons playthrough. Edit the scripts here, push them to GitHub, and use OpenOS `wget` to download the programs each computer needs.

## Layout

Each program gets its own folder. A single-file program looks like this:

```text
programs/
└── power-monitor/          # Example program
    ├── power-monitor.lua   # Main script
    └── README.md           # Hardware, setup, install, and usage
```

If a program grows into several files, its folder can include an `install.lua` that fetches them together. If a program needs settings that differ between computers, its folder can include a `config.example.lua` to copy and customize in-game.

## Install in-game

You'll need a computer running OpenOS with an Internet Card and HTTP access to `raw.githubusercontent.com`. After publishing a script to a public GitHub repo, open the file on GitHub and copy its **Raw** URL.

For example, once a `power-monitor` program exists, replace `OWNER` and `REPO` with your GitHub details and run the download command in OpenOS. After the download succeeds, run the script.

```sh
wget https://raw.githubusercontent.com/OWNER/REPO/main/programs/power-monitor/power-monitor.lua
lua power-monitor.lua
```

Use `main` to fetch the latest pushed code while developing. Replace `main` with a tested commit SHA when you want to reinstall the exact same version later. For updates, download to a separate filename first so you can keep the working copy until the download succeeds.

## Programs

The first program will be listed here when it is added.
