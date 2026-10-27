#!/usr/bin/env python3
"""Fixes two glitches of linux-wallpaperengine's GNOME Shell extension (extension.js, version-name 3).

1. Desktop icons blink when the desktop is clicked (GNOME 47+ with DING).
   DING's window is a DESKTOP type window too, in the wallpaper's layer, and lowers itself whenever it is raised,
   so it ends up under the wallpaper. The extension lowers the wallpaper again on 'restacked', but the window actors
   follow that only on the next frame, and one frame shows the wallpaper over the icons. The patch also restacks the
   actors right away, and once more right before the frame is drawn.

2. The wallpaper is squashed in the app grid. The overview clone is stretched to the workspace preview, which is a
   wide strip there; GNOME's own background is cropped instead. The patch scales the clone to cover the preview,
   centered, inside an actor that clips to it.

Usage: patch-gnome-extension.py EXTENSION_DIR [--check]
Exit codes: 0 patched or already patched, 1 error, 2 the extension's code differs (left untouched).
"""
import sys
from pathlib import Path

MARKER = "// we-gnome-installer patch v1"

PATCHES = [
    # 1a. restacked: fix actors now and once more before redraw
    (
        """            global.display.connect('restacked', () => {
                this._pickStale = true;
                this._pruneWallpapers();
                this._hideOrphanActors();
                this._keepBelowDesktopWindows();
                this._queueState();
            }),""",
        """            global.display.connect('restacked', () => {
                this._pickStale = true;
                this._pruneWallpapers();
                this._hideOrphanActors();
                this._keepBelowDesktopWindows();
                this._queueKeepBelow();
                this._queueState();
            }),""",
    ),
    # 1b. keep the wallpaper's actor under the icons' actor in the same frame
    (
        """    _keepBelowDesktopWindows() {
        const stack = global.display.sort_windows_by_stacking(global.display.list_all_windows());

        for (const wallpaper of this._wallpapers.keys()) {
            const layer = wallpaper.get_layer();
            const index = stack.indexOf(wallpaper);
            // lowering re-emits restacked
            if (stack.slice(0, Math.max(index, 0))
                .some(window => window.get_layer() === layer && !this._wallpapers.has(window)))
                wallpaper.lower();
        }
    }""",
        f"""    {MARKER}
    _keepBelowDesktopWindows() {{
        const stack = global.display.sort_windows_by_stacking(global.display.list_all_windows());

        for (const wallpaper of this._wallpapers.keys()) {{
            const layer = wallpaper.get_layer();
            const index = stack.indexOf(wallpaper);
            const below = stack.slice(0, Math.max(index, 0))
                .filter(window => window.get_layer() === layer && !this._wallpapers.has(window));
            // lowering re-emits restacked
            if (below.length > 0)
                wallpaper.lower();
            this._lowerWallpaperActor(wallpaper);
        }}
    }}

    // the window actors follow a restack only on the next frame, which would draw the wallpaper over the icons once
    _lowerWallpaperActor(wallpaper) {{
        const actor = wallpaper.get_compositor_private();
        const parent = actor?.get_parent();
        if (!parent)
            return;
        const layer = wallpaper.get_layer();
        const children = parent.get_children();
        const own = children.indexOf(actor);
        const lowest = children.find(child => child !== actor && child.meta_window &&
            !this._wallpapers.has(child.meta_window) && child.meta_window.get_layer() === layer);
        if (lowest && children.indexOf(lowest) < own)
            parent.set_child_below_sibling(actor, lowest);
    }}

    _queueKeepBelow() {{
        if (this._keepBelowLater)
            return;
        const laters = global.compositor.get_laters();
        this._keepBelowLater = laters.add(Meta.LaterType.BEFORE_REDRAW, () => {{
            this._keepBelowLater = 0;
            if (this._wallpapers)
                this._keepBelowDesktopWindows();
            return GLib.SOURCE_REMOVE;
        }});
    }}""",
    ),
    # 1c. drop the pending later on disable
    (
        """        this._pointerIdle = this._stateIdle = 0;
""",
        """        this._pointerIdle = this._stateIdle = 0;
        if (this._keepBelowLater) {
            global.compositor.get_laters().remove(this._keepBelowLater);
            this._keepBelowLater = 0;
        }
""",
    ),
    # 2a. cover-scaled clone inside a clipping box
    (
        """        const clone = new Clutter.Clone({source, x_expand: true, y_expand: true});
        const effect = new OverviewClipEffect();
        clone.add_effect(effect);

        const group = background._backgroundGroup;
        group.add_child(clone);
        group.set_child_above_sibling(clone, null);

        const entry = {clone, effect, group, signals: [], content: null, contentSignal: 0};
        const manager = background._bgManager;
        entry.signals.push([manager, manager.connect('changed', () => {
            group.set_child_above_sibling(clone, null);
            this._updateOverviewClip(background, entry);
        })]);""",
        """        // cropped like GNOME's own background when the preview isn't the monitor's shape (the app grid's strip)
        const clone = new Clutter.Clone({source});
        const box = new Clutter.Actor({x_expand: true, y_expand: true, clip_to_allocation: true});
        box.add_child(clone);
        const effect = new OverviewClipEffect();
        box.add_effect(effect);
        const cover = () => {
            const [width, height] = box.get_size();
            const [sourceWidth, sourceHeight] = source.get_size();
            if (width <= 0 || height <= 0 || sourceWidth <= 0 || sourceHeight <= 0)
                return;
            const scale = Math.max(width / sourceWidth, height / sourceHeight);
            clone.set_scale(scale, scale);
            clone.translation_x = (width - sourceWidth * scale) / 2;
            clone.translation_y = (height - sourceHeight * scale) / 2;
        };

        const group = background._backgroundGroup;
        group.add_child(box);
        group.set_child_above_sibling(box, null);

        const entry = {clone, box, effect, group, signals: [], content: null, contentSignal: 0};
        // both go away with the box, also when the overview destroys the background first
        box.connect('notify::size', cover);
        source.connectObject('notify::size', cover, box);
        const manager = background._bgManager;
        entry.signals.push([manager, manager.connect('changed', () => {
            group.set_child_above_sibling(box, null);
            this._updateOverviewClip(background, entry);
        })]);""",
    ),
    # 2b. destroy the box with the clone
    (
        """        if (entry.contentSignal)
            entry.content.disconnect(entry.contentSignal);
        entry.clone.destroy();
    }""",
        """        if (entry.contentSignal)
            entry.content.disconnect(entry.contentSignal);
        (entry.box ?? entry.clone).destroy();
    }""",
    ),
]


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[-3], file=sys.stderr)
        return 1
    path = Path(sys.argv[1]) / "extension.js"
    check = "--check" in sys.argv[2:]
    try:
        source = path.read_text()
    except OSError as error:
        print(f"cannot read {path}: {error}", file=sys.stderr)
        return 1

    if MARKER in source:
        print("already patched")
        return 0
    missing = [i for i, (old, _new) in enumerate(PATCHES, 1) if source.count(old) != 1]
    if missing:
        print(f"the extension's code differs from the expected one (hunks {missing}), left untouched")
        return 2
    if check:
        print("can be patched")
        return 0

    for old, new in PATCHES:
        source = source.replace(old, new, 1)
    backup = path.with_name("extension.js.orig")
    if not backup.exists():
        backup.write_text(path.read_text())
    path.write_text(source)
    print("patched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
