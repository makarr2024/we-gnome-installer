"""Self-test of lib/we-fix-presets.py on a fake workshop folder."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

FIXER = Path(__file__).resolve().parent.parent / "lib" / "we-fix-presets.py"


def run(*args: str) -> str:
    return subprocess.run([sys.executable, "-I", str(FIXER), *args], check=True, capture_output=True, text=True).stdout


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        workshop = Path(tmp) / "workshop content" / "431960"
        base = workshop / "100"
        preset = workshop / "200"
        (base).mkdir(parents=True)
        (base / "project.json").write_text(json.dumps({"type": "web", "file": "index.html"}))
        (preset / "files").mkdir(parents=True)
        (preset / "files" / "Картинка (1).jpg").write_bytes(b"jpeg")
        (preset / "project.json").write_text(json.dumps({
            "title": "Preset", "dependency": "100",
            "preset": {"user_image": "files/Картинка (1).jpg", "escape": "../../../etc/passwd", "n": 3},
        }, ensure_ascii=False))

        run("--workshop", str(workshop))
        mirrored = base / str(preset / "files" / "Картинка (1).jpg").lstrip("/")
        assert mirrored.read_bytes() == b"jpeg", "preset file was not mirrored"
        assert (base / ".we-fix-presets").read_text().split() == [str(workshop).lstrip("/").split("/")[0]]

        assert run("--workshop", str(workshop)) == "", "second run must copy nothing"

        run("--workshop", str(workshop), "--clean")
        assert not mirrored.exists() and not (base / ".we-fix-presets").exists(), "--clean left files"
        assert (base / "project.json").exists() and (preset / "files").exists(), "--clean removed wallpaper files"
    print("ok")


if __name__ == "__main__":
    main()
