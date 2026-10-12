"""Write a stand-in for game/data/skin_packs/vanilla.

Usage: .venv/bin/python -I tools/make_skin_pack.py [java edition .jar]

Only needed when the copy of the game is missing data/skin_packs. The game
looks up its nine default skins as "c18e65aa-7b21-4637-9b63-8ad63622ef01.<Name>"
(exe RVA 0x862b690). Without the vanilla pack the skin manager (0x140d960)
returns null and the client crashes after joining a world.

Steve and Alex come from the game's own vanilla resource pack. The other seven
default characters come from a Java Edition jar, because Java ships the same
art.
A real copy of the folders from the Windows install replaces all of this.
"""
import json, os, struct, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game/data/skin_packs/vanilla")
BRARCHIVE = os.path.join(ROOT, "game/data/resource_packs/vanilla/__brarchive/textures/entity.brarchive")
JAR = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/Library/Application Support/minecraft/versions/26.3/26.3.jar")
PACK_UUID = "c18e65aa-7b21-4637-9b63-8ad63622ef01"
NAMES = ["Steve", "Alex", "Noor", "Ari", "Sunny", "Makena", "Efe", "Zuri", "Kai"]
SLIM = {"Alex"}
# Other names the game builds with the vanilla pack uuid (exe 0x862b690), using Steve's and Alex's art.
EXTRA = {"Dummy": "steve.png", "Custom": "steve.png", "CustomSlim": "alex.png"}


def brarchive(path):
    # 16-byte header (magic, u32 count, u32 version), 0x100-byte entries
    # (u8 name length, name, u32 offset and u32 size at +0xf8), then the data.
    b = open(path, "rb").read()
    n = struct.unpack_from("<I", b, 8)[0]
    base = 0x10 + n * 0x100
    out = {}
    for i in range(n):
        o = 0x10 + i * 0x100
        name = b[o + 1:o + 1 + b[o]].decode()
        off, size = struct.unpack_from("<II", b, o + 0xf8)
        out[name] = b[base + off:base + off + size]
    return out


def write_pack(path, name, uuid, module_uuid, entries):
    json.dump({"skins": entries, "serialize_name": name, "localization_name": name},
              open(os.path.join(path, "skins.json"), "w"), indent=2)
    json.dump({"format_version": 1,
               "header": {"name": name, "uuid": uuid, "version": [1, 0, 0]},
               "modules": [{"type": "skin_pack", "uuid": module_uuid, "version": [1, 0, 0]}]},
              open(os.path.join(path, "manifest.json"), "w"), indent=2)
    print("wrote", path, len(entries), "skins")


os.makedirs(OUT, exist_ok=True)
bedrock = brarchive(BRARCHIVE)
jar = zipfile.ZipFile(JAR)
skins = []
for name in NAMES:
    png = name.lower() + ".png"
    arm = "slim" if name in SLIM else "wide"
    data = bedrock.get(png) or jar.read(f"assets/minecraft/textures/entity/player/{arm}/{png}")
    open(os.path.join(OUT, png), "wb").write(data)
    skins.append({"localization_name": name,
                  "geometry": "geometry.humanoid.customSlim" if arm == "slim" else "geometry.humanoid.custom",
                  "texture": png, "type": "free"})
for name, png in EXTRA.items():
    skins.append({"localization_name": name,
                  "geometry": "geometry.humanoid.customSlim" if name.endswith("Slim") else "geometry.humanoid.custom",
                  "texture": png, "type": "free"})

write_pack(OUT, "Standard", PACK_UUID, "d9b8a0e4-5ac0-4b6c-9a4b-1f3f2b7c9e10", skins)
