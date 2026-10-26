"""Prints every Steam library folder of the Steam install in argv[1], the install itself first.

Libraries come from steamapps/libraryfolders.vdf; only the "path" keys are needed, so a regex is enough.
"""
import os
import re
import sys


def libraries(steam_root: str) -> list[str]:
    found = [os.path.realpath(steam_root)]
    vdf = os.path.join(steam_root, "steamapps", "libraryfolders.vdf")
    try:
        with open(vdf, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return found
    for raw in re.findall(r'"path"\s+"((?:[^"\\]|\\.)*)"', text):
        path = os.path.realpath(raw.replace("\\\\", "\\"))
        if path not in found and os.path.isdir(path):
            found.append(path)
    return found


if __name__ == "__main__":
    for library in libraries(sys.argv[1]):
        print(library)
