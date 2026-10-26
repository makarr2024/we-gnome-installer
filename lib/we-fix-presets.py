#!/usr/bin/env python3
"""Makes Wallpaper Engine presets with their own files work in linux-wallpaperengine.

A preset (project.json with "dependency" and "preset") runs the dependency's wallpaper with the preset's
properties. A property can name a file shipped with the preset, e.g. "user_image": "files/pic.jpg".
linux-wallpaperengine turns that into an absolute path inside the preset's folder, but only mounts the
dependency's folder, so the page gets nothing and the wallpaper stays blank (or white).

The engine strips the leading "/" and looks the path up inside the dependency's folder, so every such
file is copied to <dependency>/<absolute path of the file without the leading "/">. The folders created
are listed in <dependency>/.we-fix-presets so --clean removes exactly them.

Usage: we-fix-presets [--workshop DIR]... [--clean] [--dry-run] [-v]
Without --workshop the folders come from WE Manager's config (workshopPath and extraLibraryPaths).
"""
import argparse
import json
import os
import shutil
import sys
from pathlib import Path

MANIFEST = ".we-fix-presets"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "we-manager" / "config.json"


def log(message: str) -> None:
    print(message, flush=True)


def workshop_dirs_from_config() -> list[Path]:
    try:
        config = json.loads(CONFIG.read_text())
    except (OSError, ValueError):
        return []
    dirs = [config.get("workshopPath")] + list(config.get("extraLibraryPaths") or [])
    return [Path(d) for d in dirs if isinstance(d, str) and d]


def read_project(folder: Path) -> dict | None:
    try:
        with open(folder / "project.json", encoding="utf-8-sig") as f:
            project = json.load(f)
    except (OSError, ValueError):
        return None
    return project if isinstance(project, dict) else None


def preset_files(preset_dir: Path, preset: dict) -> list[Path]:
    """Files inside preset_dir that preset values name (relative paths only)."""
    found: list[Path] = []
    root = preset_dir.resolve()
    for value in preset.values():
        if not isinstance(value, str) or not value or value.startswith(("/", "http:", "https:")):
            continue
        candidate = (preset_dir / value)
        try:
            resolved = candidate.resolve()
        except OSError:
            continue
        if resolved.is_file() and resolved.is_relative_to(root):
            found.append(candidate)
    return found


def read_manifest(base: Path) -> set[str]:
    try:
        return {line for line in (base / MANIFEST).read_text().splitlines() if line}
    except OSError:
        return set()


def write_manifest(base: Path, entries: set[str], dry_run: bool) -> None:
    if dry_run:
        return
    if entries:
        (base / MANIFEST).write_text("\n".join(sorted(entries)) + "\n")
    else:
        (base / MANIFEST).unlink(missing_ok=True)


def mirror_path(base: Path, file: Path) -> Path:
    return base / str(file).lstrip("/")


def fix_workshop(workshop: Path, dry_run: bool, verbose: bool) -> int:
    copied = 0
    try:
        folders = [p for p in workshop.iterdir() if p.is_dir() and not p.name.startswith(".")]
    except OSError:
        return 0
    for preset_dir in folders:
        project = read_project(preset_dir)
        if not project or not project.get("dependency") or not isinstance(project.get("preset"), dict):
            continue
        base = workshop / str(project["dependency"])
        if not (base / "project.json").is_file():
            if verbose:
                log(f"{preset_dir.name}: base wallpaper {base.name} is not downloaded, skipped")
            continue
        files = preset_files(preset_dir, project["preset"])
        if not files:
            continue
        manifest = read_manifest(base)
        # the engine gets the path WE Manager hands it; the resolved one covers a symlinked library
        variants = {preset_dir.absolute(), preset_dir.resolve()}
        for variant in variants:
            for file in files:
                source = file.resolve()
                target = mirror_path(base, variant / file.relative_to(preset_dir))
                top = target.relative_to(base).parts[0]
                if (base / top).exists() and top not in manifest:
                    # the wallpaper ships a folder with that name itself, leave it alone
                    log(f"{preset_dir.name}: {base / top} belongs to the wallpaper, skipped")
                    continue
                manifest.add(top)
                try:
                    st = source.stat()
                    tt = target.stat()
                    if tt.st_size == st.st_size and int(tt.st_mtime) == int(st.st_mtime):
                        continue
                except OSError:
                    pass
                log(f"{preset_dir.name} ({project.get('title', '')}): {file.relative_to(preset_dir)} -> {base.name}")
                if not dry_run:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
                copied += 1
        write_manifest(base, manifest, dry_run)
    return copied


def clean_workshop(workshop: Path, dry_run: bool) -> int:
    removed = 0
    try:
        folders = [p for p in workshop.iterdir() if p.is_dir()]
    except OSError:
        return 0
    for base in folders:
        for top in read_manifest(base):
            target = base / top
            if top in ("", ".", "..") or "/" in top or not target.exists():
                continue
            log(f"remove {target}")
            if not dry_run:
                shutil.rmtree(target) if target.is_dir() and not target.is_symlink() else target.unlink()
            removed += 1
        write_manifest(base, set(), dry_run)
    return removed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--workshop", action="append", type=Path, help="workshop/content/431960 folder (repeatable)")
    parser.add_argument("--clean", action="store_true", help="remove every copy made earlier")
    parser.add_argument("--dry-run", action="store_true", help="only print what would be done")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    workshops = args.workshop or workshop_dirs_from_config()
    if not workshops:
        log(f"no workshop folder: pass --workshop or set it in WE Manager ({CONFIG})")
        return 1
    total = 0
    for workshop in workshops:
        if not workshop.is_dir():
            if args.verbose:
                log(f"{workshop} does not exist, skipped")
            continue
        total += clean_workshop(workshop, args.dry_run) if args.clean else fix_workshop(workshop, args.dry_run, args.verbose)
    if args.verbose or total:
        log(f"{'removed' if args.clean else 'copied'}: {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
