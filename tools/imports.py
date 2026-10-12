"""Stage 1: list what a Windows executable imports, grouped by DLL."""
import json, sys, collections, pefile

exe = sys.argv[1]
pe = pefile.PE(exe, fast_load=True)
pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"],
                                       pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT"]])
out = collections.OrderedDict()
for attr in ("DIRECTORY_ENTRY_IMPORT", "DIRECTORY_ENTRY_DELAY_IMPORT"):
    for entry in getattr(pe, attr, []):
        dll = entry.dll.decode(errors="replace")
        out.setdefault(dll, []).extend(
            (i.name.decode(errors="replace") if i.name else f"ord#{i.ordinal}") for i in entry.imports)
print(f"{exe}: machine={hex(pe.FILE_HEADER.Machine)} sections={[s.Name.rstrip(b'\0').decode() for s in pe.sections]}")
for dll, fns in sorted(out.items(), key=lambda kv: -len(kv[1])):
    print(f"{len(fns):5d}  {dll}")
json.dump(out, open("out/imports.json", "w"), indent=1)
print("full list -> out/imports.json")
