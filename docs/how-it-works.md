# How it works

The game that runs here is the unmodified Windows build of Minecraft Bedrock Edition. It runs on WineGDK, which is Wine with an implementation of the Xbox GDK runtime that the Windows build depends on. DXMT translates its Direct3D 11 calls to Metal. Everything is x86_64 code and runs under Rosetta 2. This page describes each layer and the problems that had to be solved to get from a blank screen to a playable game.

All addresses below are relative virtual addresses (RVAs) in version 1.26.52. The rebuilt executable keeps the image base it had on the PC, `0x7ff6b18a0000`.

## The executable

The Store and GDK packages keep `Minecraft.Windows.exe` encrypted on disk, so a plain copy does not even parse as a PE file. The tools rebuild it from a full memory dump of the running game in three steps.

- `tools/extract_module.py` finds the module in the dump's module list, reads its pages from the memory list and moves the sections back to their file offsets.
- `tools/make_loadable.py` undoes what the Windows loader wrote into the image. It restores every import address table slot from the import name table. It also points the Control Flow Guard check and dispatch pointers at a `ret` and a `jmp rax` inside the image, because on the PC they pointed into ntdll. The `pefile` library writes its own parsed thunks back over the import table when it saves, so these patches are applied to the serialised bytes afterwards.
- `tools/clean_data.py` undoes the start-up state left in `.data`. The dump was taken at the title screen, so the C runtime believed its static constructors had already run, and many globals pointed into the PC's heap. The script resets the CRT start-up flag and the thread-safe statics epoch, and it clears every pointer into memory outside the image. When such a pointer heads an MSVC `std::string`, it turns the string into a valid empty one.

Counters and flags that the game changed while it ran cannot be told apart from their initial values, and they are left alone. No problem has been traced back to them so far.

## The GDK runtime

The game asks `xgameruntime.dll` for about a dozen GDK classes through `QueryApiImpl`. WineGDK implements threading, the system class, networking and a few others. The patches in `patches/wine-gdk` fill in what this game needs and fix the bugs it hit. The runtime is honest about what is missing. No user is signed in, the process is not a packaged app, and the Store licence query is refused. The game handles all of these and runs as it would on a PC that is not signed in.

The most important fix was in `XAsync.cpp`. `AllocState` cleared the `internal` field of every `XAsyncBlock` with a loop up to `sizeof(internal)`. In WineGDK that field is an array of four pointers, so the loop wrote 32 pointers, which is 256 bytes, into a 32-byte area. It overwrote the heap block headers behind every async block the game allocated. That one bug caused most of the early crashes, in places as far apart as the HTTP code, a job queue and libHttpClient. Patch 0007 clears exactly the 32 bytes.

Other runtime patches do the following.

- They implement `IXSystemImpl2` to `IXSystemImpl5` and return a stable app-specific device id.
- They treat a null task queue as the process queue, as the real GDK does.
- They complete `XUserAddAsync` with "no default user" instead of leaving it pending forever.
- They add small honest implementations of XPackage, XGame, XGameProtocol, XError, XGameInvite and XAccessibility.
- They turn two modal message boxes into log lines and let the runtime start without the optional Xodus companion service.

## Graphics

The game tries Direct3D 12 first. WineGDK is built without Vulkan, so that fails and the game falls back to Direct3D 11, which DXMT implements on Metal. DXMT reports feature level 11_1 on Apple Silicon, and the game uses its `Direct3D_SM50` shaders. Two small patches in `patches/dxmt` make DXMT v0.80 build with current Xcode and Metal tools.

Wine's Mac driver gives DXMT a Metal view inside the window, but it did not resize that view when the window changed size. In fullscreen the picture stayed at the old window size and the rest of the screen was white. Patch 0022 resizes the view whenever the window moves or changes size. The game also has its own problem when it starts in fullscreen, because it keeps drawing at the size of the window it first created. The picture is then stretched and clicks land below the cursor. The launcher therefore always starts the game in a window, and pressing F11 in the game switches to fullscreen with the right size.

Wine used to bind the game's sound to whichever output device was the default when the game opened it. Patch 0023 uses Apple's default output unit for that device instead, so the sound follows the Mac when earphones are plugged in or taken out while the game runs.

The game picks a render distance of 41 chunks on a Mac with 16 GB of memory. At that distance an M4 is limited by the GPU to about 26 frames per second. The setup starts new installs at 12 chunks, which runs at about 105 frames per second.

## Network

The game runs fully offline. Its HTTP library, libHttpClient, sends every request through `XCurl.dll`, a build of libcurl. `stubs/src/XCurl.c` replaces it with a stand-in that behaves like a PC with no network. Every transfer fails with "could not connect" after 250 ms. Failing at once raced the game's own bookkeeping and crashed it, and the delay makes it match a real failed connection. A local world is a local server that the client connects to over loopback, so single player works with no network at all.

## Sound

FMOD's mixer could divide by zero during start-up. Its loader publishes a new channel array while the mixer still reads a channel count of zero. `tools/patch_fmod.py` writes a copy of `fmod.dll` that returns "nothing mixed" in that case. It checks the original bytes first and refuses to patch any other FMOD version.

## Input

The game reads the mouse only through GameInput. Wine's GameInput refused to create the mouse device when no window was in the foreground, which is always the case at start-up. It also kept a pointer to a stack variable and read an uninitialised state. Patches 0017 to 0019 fix these. The keyboard goes through normal window messages, so keys reach the game only while its window is frontmost.

## Skins and the player model

The local player is only drawn once the game has a skin and a persona profile for it. Two separate things were missing.

- The game looks up its nine default skins as `c18e65aa-7b21-4637-9b63-8ad63622ef01.<Name>`. That uuid is the vanilla skin pack in `data/skin_packs`. A copy of the game without that folder made the skin manager return null, and the client crashed right after joining a world.
- Offline, the game cannot fetch a persona profile, so the persona skin registrar never runs and the player has no model. The setup seeds an offline profile for one of the default characters (`stubs/seed`). Any character created in the Dressing Room replaces it.

When the copy of the game has no `data/skin_packs`, `tools/make_skin_pack.py` writes stand-in vanilla and persona packs from the game's own textures and, if it is installed, the Java Edition jar.

Offline there is also no gamertag. The game then used the untranslated key of the character's name, `persona.makena_name.title` cut to 16 characters, as the player name. The setup sets `mp_username` in `options.txt` to your macOS account name, and `PLAYER_NAME=...` overrides it.

## Debugging

`tools/run_wine.sh` runs the game with any Wine debug channels. `+seh` shows every exception and the game's own `OutputDebugStringA` messages. Avoid `+file` and `+relay` when hunting crashes, because they slow the game enough that timing-dependent crashes stop happening. The tens of thousands of `__processing_throw` lines that `+seh` prints are calls to `std::uncaught_exceptions()`, and no exception is thrown.

`tools/trace/trace_patch.py` builds a copy of the executable with logging detours at chosen addresses, which is how the skin lookup was followed. The helpers in `tools/dev` take screenshots of the game window, send input with `winput.exe` and disassemble the rebuilt executable.

## Known limits

- Signing in, Realms, the Marketplace and online servers do not work, because the game is offline by design.
- Most of the music is missing if the copy of the game is missing `data/resource_packs/vanilla_music`.
- The game pauses whenever its window loses focus. That is the normal behaviour of the Windows build.
- Only version 1.26.52 has been tested.
