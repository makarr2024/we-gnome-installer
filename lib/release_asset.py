"""Reads a GitHub release JSON on stdin, prints the asset matching argv[1].

Output: tag, name, download URL, size, sha256 (empty when GitHub has no digest), tab separated.
"""
import json
import re
import sys


def main() -> int:
    pattern = re.compile(sys.argv[1])
    release = json.load(sys.stdin)
    for asset in release.get("assets", []):
        if pattern.search(asset["name"]):
            digest = asset.get("digest") or ""
            sha = digest.split(":", 1)[1] if digest.startswith("sha256:") else ""
            print("\t".join([release["tag_name"], asset["name"], asset["browser_download_url"], str(asset["size"]), sha]))
            return 0
    print(f"release {release.get('tag_name')} has no asset matching {sys.argv[1]}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
