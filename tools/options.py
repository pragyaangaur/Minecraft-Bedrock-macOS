"""Fill in settings in the game's options.txt without touching anything else.

Usage: .venv/bin/python -I tools/options.py <options.txt> key=value [key:=value ...]

A key given as key=value is only written when it is missing or has an empty
value, so settings changed in the game are kept. A key given as key:=value is
always written. A missing file is created with just these keys,
and the game adds its defaults for everything else on the next start. The
game writes the file with CRLF line endings, and they are kept.
"""
import os
import sys


def main():
    path, pairs = sys.argv[1], [a.split("=", 1) for a in sys.argv[2:]]
    pairs = [(key[:-1], value, True) if key.endswith(":") else (key, value, False) for key, value in pairs]
    lines = open(path, encoding="utf-8", newline="").read().split("\r\n") if os.path.exists(path) else []
    if lines and lines[-1] == "":
        lines.pop()
    index = {line.split(":", 1)[0]: i for i, line in enumerate(lines) if ":" in line}
    changed = False
    for key, value, always in pairs:
        if key not in index:
            lines.append(f"{key}:{value}")
            changed = True
        elif lines[index[key]] == f"{key}:" or (always and lines[index[key]] != f"{key}:{value}"):
            lines[index[key]] = f"{key}:{value}"
            changed = True
    if changed:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", encoding="utf-8", newline="").write("\r\n".join(lines) + "\r\n")


if __name__ == "__main__":
    main()
