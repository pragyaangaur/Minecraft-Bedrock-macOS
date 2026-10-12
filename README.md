# Minecraft Bedrock on macOS

This project runs the Windows version of Minecraft Bedrock Edition on an Apple Silicon Mac. It uses the game's own Windows files, a patched build of [WineGDK](https://github.com/Weather-OS/WineGDK) and [DXMT](https://github.com/3Shain/dxmt), which turns Direct3D 11 into Metal. The game runs fully offline. Single-player worlds work, including survival and creative mode, the Nether, the End and the Ender Dragon. On an M4 Mac it runs at about 100 frames per second at a 12 chunk render distance.

Mojang does not make a Mac version of Bedrock. This repository contains no game files. You need your own copy of Minecraft for Windows, installed on a Windows PC, and the setup builds everything else from source on your Mac.

## Requirements

- A Mac with Apple Silicon and Rosetta 2. It was tested on an M4 with 16 GB of memory and macOS 27.
- Xcode with Apple's Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`).
- [Homebrew](https://brew.sh) with these packages:

  ```bash
  brew install llvm lld mingw-w64 bison flex meson ninja cmake pkgconf python
  ```

- About 30 GB of free disk space and one to two hours for the first build.
- A Windows PC with Minecraft for Windows version 1.26.52, to take the game files from.

## Setup

1. Get the game folder and a memory dump of the running game from your Windows PC. [docs/getting-the-game-files.md](docs/getting-the-game-files.md) explains both steps.
2. Run the setup with both of them:

   ```bash
   ./setup.sh --game "/path/to/the/game/folder" --dump "/path/to/Minecraft.Windows.exe_....dmp"
   ```

   It checks the requirements, then downloads and builds GnuTLS, FreeType, WineGDK, LLVM 15 and DXMT into `build/`. It also rebuilds the game's executable from the dump and creates a Wine prefix in `prefix/`. You can run it again at any time, and it skips the steps that are already done.

3. Double-click `Play Minecraft.command`, or run:

   ```bash
   tools/play_minecraft.sh
   ```

Add `HUD=1` in front of the command to show Apple's frame rate overlay. The player name comes from your macOS account name, and `PLAYER_NAME=Steve tools/play_minecraft.sh` sets another one. Your worlds are saved in `prefix/drive_c/users/<you>/AppData/Roaming/Minecraft Bedrock/Users/Shared/games/com.mojang/minecraftWorlds`.

## What does not work

- Anything online is unavailable, including signing in, Realms, the Marketplace and multiplayer servers.
- The game pauses when its window loses focus, as it does on Windows.
- Only version 1.26.52 has been tested. Other versions will likely need new addresses in the tools.

## How it works

[docs/how-it-works.md](docs/how-it-works.md) describes every layer and the bugs that had to be fixed. The short version is below.

- The executable is encrypted on disk, so `tools/` rebuilds it from a full memory dump. The tools restore its import table and undo the start-up state the dump captured.
- `patches/wine-gdk` adds the parts of the Xbox GDK runtime this game needs, fixes a heap overrun in WineGDK's async code and fixes Wine's mouse support through GameInput.
- `patches/dxmt` makes DXMT build with current Xcode.
- `stubs/` holds small stand-in DLLs, including an offline replacement for the game's HTTP library.
- `tools/patch_fmod.py` guards FMOD's mixer against a divide by zero at start-up.

## Repository layout

| Path | Contents |
| --- | --- |
| `setup.sh` | Builds everything and prepares your copy of the game |
| `Play Minecraft.command` | Starts the game from Finder |
| `scripts/` | The setup steps, one script per component |
| `patches/` | Patches for WineGDK and DXMT, applied to pinned upstream versions |
| `stubs/` | Stand-in Windows DLLs, a seed persona profile and their build script |
| `tools/` | The executable rebuild pipeline, the game runner and the launcher |
| `tools/trace/` | Builds a copy of the executable with logging detours |
| `tools/winput/` | A small Windows program that sends keys and mouse input to the game |
| `tools/dev/` | Helpers for screenshots, input and disassembly while debugging |
| `docs/` | How to get the game files and how the port works |

## Licence

The scripts, tools and stubs in this repository are under the MIT licence in [LICENSE](LICENSE). The patches in `patches/wine-gdk` change WineGDK and fall under its LGPL 2.1 licence. The patches in `patches/dxmt` change DXMT and fall under its MIT licence. Minecraft is a trademark of Mojang Synergies AB, and this project is not affiliated with Mojang or Microsoft.
