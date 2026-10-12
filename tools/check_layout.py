"""Check a copied game folder against the directory list in its layout.xml.

Usage: .venv/bin/python -I tools/check_layout.py <game folder>

The GDK package lists every directory of the install in layout.xml. A copy
from Windows that stopped part of the way through leaves some of them missing
or empty, and the game then fails in odd places later (a missing
data/skin_packs makes the client crash after joining a world). This prints
every listed directory that is missing or empty and exits with status 1 if
there are any.
"""
import os
import re
import sys


def main():
    game = sys.argv[1]
    layout = open(os.path.join(game, "layout.xml"), encoding="utf-8-sig").read()
    dirs = sorted({d.replace("\\", "/").lstrip("./") for d in re.findall(r'DestinationPath="([^"]*)"', layout)})
    problems = []
    for d in dirs:
        path = os.path.join(game, d)
        if not os.path.isdir(path):
            problems.append(("missing", d))
        elif not os.listdir(path):
            problems.append(("empty", d))
    for kind, d in problems:
        print(f"{kind:8} {d}")
    print(f"{len(dirs)} directories listed, {len(problems)} missing or empty")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
