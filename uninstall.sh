#!/usr/bin/env bash
# Удаляет то, что поставил install.sh. Обои из Мастерской и сам Steam не трогает.
set -euo pipefail

EXT_UUID="linux-wallpaperengine@wallpaperenginelover.github.io"
HANABI_UUID="hanabi-extension@jeffshee.github.io"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

APP_DIR="$DATA_HOME/we-manager-app"
ENGINE_DIR="$DATA_HOME/linux-wallpaperengine-kde"
EXT_DIR="$DATA_HOME/gnome-shell/extensions/$EXT_UUID"
TOOLS_DIR="$DATA_HOME/we-gnome-installer"
STATE_FILE="$TOOLS_DIR/state"
SYSTEMD_USER_DIR="$CONFIG_HOME/systemd/user"

purge=0
assume_yes=0

usage() {
    cat <<EOF
Использование: uninstall.sh [--purge] [-y]

  --purge    удалить и настройки WE Manager (~/.config/we-manager: библиотека, плейлисты)
  -y, --yes  не спрашивать подтверждение
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --purge) purge=1 ;;
        -y|--yes) assume_yes=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
    shift
done

state_get() { [ -f "$STATE_FILE" ] && sed -n "s/^$1=//p" "$STATE_FILE" | tail -1; }

if [ "$assume_yes" = 0 ] && [ -t 0 ]; then
    read -r -p "Удалить WE Manager, движок linux-wallpaperengine и расширение GNOME? [y/N] " answer
    case "$answer" in [yYдД]*) ;; *) exit 1 ;; esac
fi

echo "==> Останавливаю WE Manager и движок"
pkill -f "^$APP_DIR/squashfs-root/we-manager" 2>/dev/null || true
pkill -f "^$ENGINE_DIR/linux-wallpaperengine" 2>/dev/null || true

echo "==> Убираю копии файлов пресетов"
if [ -x "$TOOLS_DIR/we-fix-presets" ]; then
    python3 -I "$TOOLS_DIR/we-fix-presets" --clean || true
fi

echo "==> Отключаю службы"
if command -v systemctl >/dev/null; then
    systemctl --user disable --now we-fix-presets.path we-fix-presets.service >/dev/null 2>&1 || true
    rm -f "$SYSTEMD_USER_DIR/we-fix-presets.path" "$SYSTEMD_USER_DIR/we-fix-presets.service"
    systemctl --user daemon-reload || true
fi

echo "==> Удаляю расширение GNOME"
if command -v gnome-extensions >/dev/null; then
    gnome-extensions disable "$EXT_UUID" 2>/dev/null || true
fi
if command -v gsettings >/dev/null; then
    python3 -I - "$EXT_UUID" <<'EOF' || true
import ast, subprocess, sys
uuid = sys.argv[1]
raw = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"], capture_output=True, text=True).stdout.strip()
items = ast.literal_eval(raw.removeprefix("@as ")) if raw else []
if uuid in items:
    items.remove(uuid)
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(items)], check=True)
EOF
fi
rm -rf "$EXT_DIR"

echo "==> Удаляю программы и ярлыки"
rm -rf "$APP_DIR" "$ENGINE_DIR"
rm -f "$DATA_HOME/applications/we-manager.desktop" "$CONFIG_HOME/autostart/we-manager.desktop"

if [ "$(state_get steam_link)" = 1 ] && [ -L "$HOME/.steam" ]; then
    echo "==> Удаляю ссылку ~/.steam, созданную установщиком"
    rm -f "$HOME/.steam"
fi

if [ "$(state_get hanabi_disabled)" = 1 ]; then
    echo "    Hanabi был отключён установщиком. Включить обратно: gnome-extensions enable $HANABI_UUID"
fi

if [ "$purge" = 1 ]; then
    echo "==> Удаляю настройки WE Manager"
    rm -rf "$CONFIG_HOME/we-manager"
else
    echo "    Настройки, плейлисты и библиотека WE Manager оставлены в $CONFIG_HOME/we-manager (--purge удалит)."
fi

rm -rf "$TOOLS_DIR"
echo "==> Готово. Чтобы GNOME забыл расширение полностью, войдите в систему заново."
