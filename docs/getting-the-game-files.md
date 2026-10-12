# Getting the game files

The setup needs two things from a Windows PC on which you own and have installed Minecraft for Windows (Bedrock Edition). The first is the game folder. The second is a full memory dump of the running game. You only need to do this once, and it takes about 15 minutes.

The executable in the installed folder is encrypted on disk and only decrypted in memory when Windows starts the game. That is why the setup rebuilds `Minecraft.Windows.exe` from a memory dump. Everything else in the folder (textures, sounds, resource packs, the other DLLs) is a normal file and is copied as it is.

This was tested with version 1.26.52 of the game (package version 1.26.5203.0). Other versions will probably need new addresses in the tools, and `setup.sh` prints a warning if the version differs.

## 1. Take the memory dump

1. Download System Informer from [systeminformer.com](https://systeminformer.com) and start it as administrator.
2. Start Minecraft and wait until the title screen is shown. Do not sign in and do not open a world.
3. In System Informer, find `Minecraft.Windows.exe` in the process list, right-click it and choose **Create dump file...**.
4. Save the file. It is a full dump of about 3 GB with a name such as `Minecraft.Windows.exe_2026-10-11_12-52-38.dmp`.

A dump contains everything the game had in memory. If you signed in before taking it, it can contain sign-in tokens, so keep it private and never upload it anywhere.

## 2. Copy the game folder

In System Informer, right-click `Minecraft.Windows.exe` again and choose **Open file location**. This opens the folder that contains the executable, `layout.xml`, `appxmanifest.xml` and the `data` folder. The usual places are `C:\XboxGames\Minecraft for Windows\Content` and a folder named `Microsoft.MinecraftUWP_...` under `C:\Program Files\WindowsApps`.

Copy the whole folder, about 2 GB. Windows refuses to copy `Minecraft.Windows.exe` itself, and you can skip that file because the setup does not use it. Make sure everything else was copied. A copy that stops part of the way through leaves folders missing, and the game then fails in confusing ways later. The most important one is `data/skin_packs`, which holds the default character skins.

## 3. Move both to the Mac

An external drive formatted as exFAT works well, because the dump is larger than the 4 GB limit of FAT32 drives. Put the folder and the dump anywhere on the Mac.

If you use Bedrock Launcher, open it and choose the folder and the dump when it asks. It copies the game into `~/Library/Application Support/Bedrock Launcher`, so you can delete both copies once the game has started. The rest of this page is for building from source.

If you built from source, run the setup:

```bash
./setup.sh --game "/path/to/the/copied/folder" --dump "/path/to/Minecraft.Windows.exe_....dmp"
```

The setup copies the folder into `game/`, so you can delete your copy afterwards. It also checks the copy against the list of folders in `layout.xml` and prints a warning if any are missing or empty. To see the full list later, run:

```bash
.venv/bin/python tools/check_layout.py game
```

If `data/skin_packs` is missing, the setup writes stand-in skin packs so that the game still works. Copy the real folder from Windows into `game/data/skin_packs` when you can, because the stand-ins only cover the default characters.
