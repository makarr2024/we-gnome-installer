#!/usr/bin/env bash
# Устанавливает WE Manager + linux-wallpaperengine + расширение GNOME Shell
# для интерактивных обоев Wallpaper Engine на Ubuntu / GNOME (Wayland и X11).
#
# Всё ставится в домашнюю папку, root не нужен.
set -euo pipefail

INSTALLER_VERSION="1.1.0"

MANAGER_REPO="WallpaperEngineLover/we_manager"
ENGINE_REPO="WallpaperEngineLover/linux-wallpaperengine-kde"
ENGINE_ASSET="linux-wallpaperengine-generic-portable-x86_64.tar.gz"
EXT_UUID="linux-wallpaperengine@wallpaperenginelover.github.io"
HANABI_UUID="hanabi-extension@jeffshee.github.io"
WE_APP_ID="431960"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

APP_DIR="$DATA_HOME/we-manager-app"
ENGINE_DIR="$DATA_HOME/linux-wallpaperengine-kde"
EXT_DIR="$DATA_HOME/gnome-shell/extensions/$EXT_UUID"
TOOLS_DIR="$DATA_HOME/we-gnome-installer"
MANAGER_CONFIG_DIR="$CONFIG_HOME/we-manager"
SYSTEMD_USER_DIR="$CONFIG_HOME/systemd/user"
STATE_FILE="$TOOLS_DIR/state"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

manager_tag="latest"
engine_tag="latest"
want_autostart=1
want_disable_hanabi=0
force=0
assume_yes=0

# ---------------------------------------------------------------- вывод

if [ -t 1 ]; then
    c_bold=$'\e[1m'; c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_red=$'\e[31m'; c_reset=$'\e[0m'
else
    c_bold=""; c_green=""; c_yellow=""; c_red=""; c_reset=""
fi
step() { printf '%s==>%s %s\n' "$c_bold$c_green" "$c_reset" "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s!!%s  %s\n' "$c_bold$c_yellow" "$c_reset" "$*" >&2; }
die()  { printf '%sОшибка:%s %s\n' "$c_bold$c_red" "$c_reset" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Установщик интерактивных обоев Wallpaper Engine для GNOME, версия $INSTALLER_VERSION

Использование: ./install.sh [параметры]

  --manager-version TAG   версия WE Manager (по умолчанию latest), например v0.9.6
  --engine-version TAG    версия linux-wallpaperengine (по умолчанию latest)
  --no-autostart          не запускать WE Manager при входе в систему
  --disable-hanabi        отключить расширение Hanabi, если оно стоит (конфликтует)
  --force                 скачать и переустановить, даже если версия совпадает
  -y, --yes               не задавать вопросов
  -h, --help              эта справка

Удаление: ./uninstall.sh
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --manager-version) manager_tag="${2:?нужна версия}"; shift ;;
        --engine-version)  engine_tag="${2:?нужна версия}"; shift ;;
        --no-autostart)    want_autostart=0 ;;
        --disable-hanabi)  want_disable_hanabi=1 ;;
        --force)           force=1 ;;
        -y|--yes)          assume_yes=1 ;;
        -h|--help)         usage; exit 0 ;;
        *) usage >&2; die "неизвестный параметр: $1" ;;
    esac
    shift
done

confirm() {
    [ "$assume_yes" = 1 ] && return 0
    [ -t 0 ] || return 0
    local answer
    read -r -p "$1 [Y/n] " answer
    case "$answer" in [nNнН]*) return 1 ;; *) return 0 ;; esac
}

# ---------------------------------------------------------------- проверки

check_system() {
    step "Проверка системы"
    [ "$(id -u)" != 0 ] || die "не запускайте установщик от root — всё ставится в домашнюю папку."
    [ "$(uname -m)" = x86_64 ] || die "поддерживается только x86_64."

    local cmd
    for cmd in curl tar sha256sum python3; do
        command -v "$cmd" >/dev/null || die "не найдена команда '$cmd'. Установите: sudo apt install $cmd"
    done

    local glibc
    glibc="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' || true)"
    if [ -n "$glibc" ] && ! python3 -c "import sys; sys.exit(0 if tuple(map(int,'$glibc'.split('.'))) >= (2,35) else 1)"; then
        die "нужна glibc 2.35+ (Ubuntu 22.04 и новее), у вас $glibc."
    fi

    if ! command -v gnome-shell >/dev/null; then
        warn "GNOME Shell не найден. Установщик рассчитан на GNOME; на других окружениях часть шагов будет пропущена."
    else
        info "$(gnome-shell --version)"
    fi
    info "Сеанс: ${XDG_SESSION_TYPE:-неизвестно}, окружение: ${XDG_CURRENT_DESKTOP:-неизвестно}"

    # распаковка движка и менеджера: ~1.2 ГБ с запасом на время установки
    local free_kb
    free_kb="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
    if [ "${free_kb:-0}" -lt 1500000 ]; then
        warn "Свободно меньше 1.5 ГБ ($((free_kb / 1024)) МБ). Установке может не хватить места."
        confirm "Продолжить?" || exit 1
    fi
}

# ---------------------------------------------------------------- Steam

steam_root=""
workshop_dir=""

# Папки, в которых может лежать Steam: обычный, snap и flatpak
steam_candidates() {
    printf '%s\n' \
        "$HOME/.steam/steam" \
        "$HOME/.local/share/Steam" \
        "$HOME/snap/steam/common/.local/share/Steam" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
}

find_steam() {
    step "Поиск Steam и Wallpaper Engine"
    local root lib
    while IFS= read -r root; do
        [ -d "$root/steamapps" ] || continue
        steam_root="$(readlink -f "$root")"
        # Wallpaper Engine может стоять в другой библиотеке Steam
        while IFS= read -r lib; do
            if [ -d "$lib/steamapps/common/wallpaper_engine" ] || [ -d "$lib/steamapps/workshop/content/$WE_APP_ID" ]; then
                workshop_dir="$lib/steamapps/workshop/content/$WE_APP_ID"
                break 2
            fi
        done < <(python3 -I "$SRC_DIR/lib/steam_libraries.py" "$root")
    done < <(steam_candidates)

    if [ -z "$steam_root" ]; then
        warn "Steam не найден. Установите Steam и Wallpaper Engine, затем укажите папку Мастерской в настройках WE Manager."
        return
    fi
    info "Steam: $steam_root"
    if [ -n "$workshop_dir" ]; then
        info "Мастерская Wallpaper Engine: $workshop_dir"
    else
        warn "Wallpaper Engine в Steam не найден. Купите/установите его в Steam — без его ассетов сцены не запустятся."
    fi
}

# Snap-версия Steam держит ~/.steam внутри ~/snap/steam/common, а Steamworks
# (через него WE Manager работает с Мастерской) ищет ~/.steam/sdk64/steamclient.so.
fix_snap_steam() {
    local snap_dot="$HOME/snap/steam/common/.steam"
    [ -d "$snap_dot" ] || return 0
    if [ -e "$HOME/.steam" ] || [ -L "$HOME/.steam" ]; then
        if [ "$(readlink -f "$HOME/.steam")" != "$(readlink -f "$snap_dot")" ] && [ ! -e "$HOME/.steam/sdk64/steamclient.so" ]; then
            warn "$HOME/.steam существует, но в нём нет steamclient.so — Мастерская в WE Manager может не работать."
        fi
        return 0
    fi
    step "Snap-версия Steam: создаю ссылку ~/.steam -> $snap_dot"
    ln -s "$snap_dot" "$HOME/.steam"
    state_set steam_link 1
}

# ---------------------------------------------------------------- состояние

state_set() {
    mkdir -p "$TOOLS_DIR"
    touch "$STATE_FILE"
    grep -v "^$1=" "$STATE_FILE" > "$STATE_FILE.tmp" || true
    printf '%s=%s\n' "$1" "$2" >> "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# ---------------------------------------------------------------- загрузка

WORK_DIR=""
cleanup() { [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# release_info REPO TAG ASSET_REGEX -> "tag<TAB>name<TAB>url<TAB>size<TAB>sha256"
release_info() {
    local repo="$1" tag="$2" pattern="$3" url
    if [ "$tag" = latest ]; then
        url="https://api.github.com/repos/$repo/releases/latest"
    else
        url="https://api.github.com/repos/$repo/releases/tags/$tag"
    fi
    curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "$url" \
        | python3 -I "$SRC_DIR/lib/release_asset.py" "$pattern"
}

installed_tag() {
    [ -f "$1/.release" ] || return 0
    python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tag",""))' "$1/.release" 2>/dev/null || true
}

# download URL FILE SIZE SHA256
download_verified() {
    local url="$1" file="$2" size="$3" sha="$4"
    info "Загрузка $(basename "$file") ($((size / 1048576)) МБ)..."
    curl -fL --retry 3 --progress-bar -o "$file" "$url"
    [ "$(stat -c %s "$file")" = "$size" ] || die "размер $(basename "$file") не совпал с релизом."
    if [ -n "$sha" ]; then
        echo "$sha  $file" | sha256sum -c --quiet - || die "контрольная сумма $(basename "$file") не совпала — файл повреждён или подменён."
        info "Контрольная сумма SHA-256 совпала."
    else
        warn "В релизе нет контрольной суммы, проверен только размер."
    fi
}

stop_manager() {
    local pids
    pids="$(pgrep -f "^$APP_DIR/squashfs-root/we-manager" || true)"
    if [ -n "$pids" ]; then
        info "Останавливаю запущенный WE Manager..."
        # shellcheck disable=SC2086
        kill $pids 2>/dev/null || true
        sleep 2
    fi
}

install_manager() {
    step "WE Manager"
    local line tag name url size sha current
    line="$(release_info "$MANAGER_REPO" "$manager_tag" '^WE-Manager-.*\.AppImage$')" \
        || die "не удалось получить релиз WE Manager с GitHub."
    IFS=$'\t' read -r tag name url size sha <<< "$line"
    current="$(installed_tag "$APP_DIR")"
    if [ "$force" = 0 ] && [ "$current" = "$tag" ] && [ -x "$APP_DIR/squashfs-root/we-manager" ]; then
        info "Уже установлена версия $tag."
        return
    fi
    info "Версия: $tag${current:+ (сейчас $current)}"

    download_verified "$url" "$WORK_DIR/$name" "$size" "$sha"
    chmod +x "$WORK_DIR/$name"
    # распаковываем AppImage: так не нужен FUSE (libfuse2), и запуск быстрее
    (cd "$WORK_DIR" && "./$name" --appimage-extract >/dev/null) || die "не удалось распаковать AppImage."

    stop_manager
    mkdir -p "$APP_DIR"
    rm -rf "$APP_DIR/squashfs-root.old"
    [ -d "$APP_DIR/squashfs-root" ] && mv "$APP_DIR/squashfs-root" "$APP_DIR/squashfs-root.old"
    mv "$WORK_DIR/squashfs-root" "$APP_DIR/squashfs-root"
    rm -rf "$APP_DIR/squashfs-root.old" "$APP_DIR/WE-Manager.AppImage"
    printf '{"tag":"%s","asset":"%s"}\n' "$tag" "$name" > "$APP_DIR/.release"
    rm -f "$WORK_DIR/$name"
    info "Установлено в $APP_DIR"
}

install_engine() {
    step "Движок linux-wallpaperengine"
    local line tag name url size sha current staging
    line="$(release_info "$ENGINE_REPO" "$engine_tag" "^${ENGINE_ASSET//./\\.}\$")" \
        || die "не удалось получить релиз linux-wallpaperengine с GitHub."
    IFS=$'\t' read -r tag name url size sha <<< "$line"
    current="$(installed_tag "$ENGINE_DIR")"
    if [ "$force" = 0 ] && [ "$current" = "$tag" ] && [ -x "$ENGINE_DIR/linux-wallpaperengine" ]; then
        info "Уже установлена версия $tag."
        return
    fi
    info "Версия: $tag${current:+ (сейчас $current)}"

    download_verified "$url" "$WORK_DIR/$name" "$size" "$sha"
    staging="$ENGINE_DIR.new"
    rm -rf "$staging"
    mkdir -p "$staging"
    info "Распаковка..."
    tar -xzf "$WORK_DIR/$name" -C "$staging" --strip-components=1
    rm -f "$WORK_DIR/$name"
    # формат .release совпадает с тем, что пишет сам WE Manager
    printf '{"tag":"%s","asset":"%s"}\n' "$tag" "$name" > "$staging/.release"

    # запущенные движки держат свои файлы открытыми, им это не мешает
    rm -rf "$ENGINE_DIR.old"
    [ -d "$ENGINE_DIR" ] && mv "$ENGINE_DIR" "$ENGINE_DIR.old"
    mv "$staging" "$ENGINE_DIR"
    rm -rf "$ENGINE_DIR.old"

    if "$ENGINE_DIR/linux-wallpaperengine" --check-libraries 2>/dev/null | grep -q 'not found'; then
        warn "Движку не хватает системных библиотек:"
        "$ENGINE_DIR/linux-wallpaperengine" --check-libraries 2>/dev/null | grep 'not found' | sort -u | sed 's/^/      /' >&2
    fi
    info "Установлено в $ENGINE_DIR"
}

# ---------------------------------------------------------------- GNOME

gsettings_list_add() {
    local key="$1" uuid="$2"
    python3 -I - "$key" "$uuid" <<'EOF'
import ast, subprocess, sys
key, uuid = sys.argv[1], sys.argv[2]
raw = subprocess.run(["gsettings", "get", "org.gnome.shell", key], capture_output=True, text=True).stdout.strip()
raw = raw.removeprefix("@as ")
items = ast.literal_eval(raw) if raw else []
if uuid not in items:
    items.append(uuid)
    subprocess.run(["gsettings", "set", "org.gnome.shell", key, str(items)], check=True)
EOF
}

gsettings_list_remove() {
    local key="$1" uuid="$2"
    python3 -I - "$key" "$uuid" <<'EOF'
import ast, subprocess, sys
key, uuid = sys.argv[1], sys.argv[2]
raw = subprocess.run(["gsettings", "get", "org.gnome.shell", key], capture_output=True, text=True).stdout.strip()
raw = raw.removeprefix("@as ")
items = ast.literal_eval(raw) if raw else []
if uuid in items:
    items.remove(uuid)
    subprocess.run(["gsettings", "set", "org.gnome.shell", key, str(items)], check=True)
EOF
}

relogin_needed=0

extension_version() {
    [ -f "$1/metadata.json" ] || return 0
    python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version-name",""))' "$1/metadata.json" 2>/dev/null || true
}

install_gnome_extension() {
    command -v gnome-shell >/dev/null || return 0
    step "Расширение GNOME Shell"
    local bundled="$ENGINE_DIR/gnome-shell-extension/$EXT_UUID"
    [ -f "$bundled/metadata.json" ] || die "в сборке движка нет расширения GNOME ($bundled)."

    local was_known=0 old_version="" new_version
    gnome-extensions info "$EXT_UUID" >/dev/null 2>&1 && was_known=1
    old_version="$(extension_version "$EXT_DIR")"
    new_version="$(extension_version "$bundled")"
    if [ "$was_known" = 1 ] && [ -n "$old_version" ] && [ "$old_version" = "$new_version" ] && [ "$force" = 0 ]; then
        info "Уже установлена версия $new_version."
        gsettings_list_add enabled-extensions "$EXT_UUID"
        patch_gnome_extension
        return
    fi

    rm -rf "$EXT_DIR.new"
    mkdir -p "$(dirname "$EXT_DIR")"
    cp -r "$bundled" "$EXT_DIR.new"
    [ -f "$EXT_DIR.new/linux-wallpaperengine-gnome-helper" ] && chmod 755 "$EXT_DIR.new/linux-wallpaperengine-gnome-helper"
    rm -rf "$EXT_DIR"
    mv "$EXT_DIR.new" "$EXT_DIR"

    gsettings_list_remove disabled-extensions "$EXT_UUID"
    gsettings_list_add enabled-extensions "$EXT_UUID"
    if [ "$(gsettings get org.gnome.shell disable-user-extensions)" = true ]; then
        gsettings set org.gnome.shell disable-user-extensions false
        info "Включены пользовательские расширения GNOME."
    fi
    gnome-extensions enable "$EXT_UUID" 2>/dev/null || true

    if [ "$was_known" = 0 ]; then
        relogin_needed=1
        info "Установлено. GNOME подхватит его после повторного входа в систему."
    else
        info "Обновлено до версии $new_version. Она заработает после повторного входа в систему."
        relogin_needed=1
    fi
    patch_gnome_extension
}

# Моргание значков при клике по рабочему столу и сплющенные обои в списке приложений —
# см. lib/patch-gnome-extension.py. Код расширения другой версии не трогаем.
patch_gnome_extension() {
    local result
    result="$(python3 -I "$SRC_DIR/lib/patch-gnome-extension.py" "$EXT_DIR" 2>&1)" || true
    case "$result" in
        patched)
            info "Исправления расширения применены (значки не моргают, обои в обзоре не сплющены)."
            relogin_needed=1 ;;
        "already patched") ;;
        *) warn "Исправления расширения не применены: $result" ;;
    esac
}

handle_hanabi() {
    command -v gnome-extensions >/dev/null || return 0
    gnome-extensions list --enabled 2>/dev/null | grep -qxF "$HANABI_UUID" || return 0
    if [ "$want_disable_hanabi" = 1 ] || confirm "Найдено расширение Hanabi — оно рисует свои обои поверх. Отключить его?"; then
        gnome-extensions disable "$HANABI_UUID" 2>/dev/null || gsettings_list_remove enabled-extensions "$HANABI_UUID"
        state_set hanabi_disabled 1
        step "Hanabi отключён (включить обратно: gnome-extensions enable $HANABI_UUID)"
    else
        warn "Hanabi оставлен включённым — обои двух программ будут мешать друг другу."
    fi
}

# ---------------------------------------------------------------- настройка

install_tools() {
    step "Исправление пресетов и автозапуск"
    mkdir -p "$TOOLS_DIR"
    install -m 755 "$SRC_DIR/lib/we-fix-presets.py" "$TOOLS_DIR/we-fix-presets"
    install -m 755 "$SRC_DIR/lib/patch-gnome-extension.py" "$TOOLS_DIR/patch-gnome-extension"
    install -m 644 "$SRC_DIR/lib/steam_libraries.py" "$TOOLS_DIR/steam_libraries.py"
    install -m 755 "$SRC_DIR/uninstall.sh" "$TOOLS_DIR/uninstall.sh"
    state_set installer_version "$INSTALLER_VERSION"
}

desktop_entries() {
    local apps="$DATA_HOME/applications"
    mkdir -p "$apps"
    cat > "$apps/we-manager.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=WE Manager
Comment=Менеджер интерактивных обоев Wallpaper Engine
Exec=$APP_DIR/squashfs-root/AppRun
Icon=$APP_DIR/squashfs-root/we-manager.png
Terminal=false
Categories=Utility;
StartupWMClass=we-manager
EOF
    if command -v update-desktop-database >/dev/null; then
        update-desktop-database "$apps" 2>/dev/null || true
    fi

    local autostart="$CONFIG_HOME/autostart/we-manager.desktop"
    if [ "$want_autostart" = 1 ]; then
        mkdir -p "$(dirname "$autostart")"
        # строка Exec ровно такая, какую пишет сам WE Manager, иначе он её перезапишет
        cat > "$autostart" <<EOF
[Desktop Entry]
Type=Application
Name=WE Manager
Exec=$APP_DIR/squashfs-root/we-manager --no-sandbox --minimized
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=10
EOF
        info "WE Manager будет запускаться свёрнутым в трей при входе в систему."
    else
        rm -f "$autostart"
    fi
}

configure_manager() {
    mkdir -p "$MANAGER_CONFIG_DIR"
    python3 -I - "$MANAGER_CONFIG_DIR/config.json" "$workshop_dir" "$want_autostart" "${LANG:-}" <<'EOF'
import json, sys, pathlib
path, workshop, autostart, lang = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3] == "1", sys.argv[4]
config = {}
if path.exists():
    try:
        config = json.loads(path.read_text())
    except ValueError:
        path.rename(path.with_suffix(".json.bak"))
if workshop and not config.get("workshopPath"):
    config["workshopPath"] = workshop
if "language" not in config and lang.startswith("ru"):
    config["language"] = "ru"
config["trayEnabled"] = True if autostart else config.get("trayEnabled", True)
config["autostartEnabled"] = autostart
config["autostartMinimized"] = True if autostart else config.get("autostartMinimized", False)
path.write_text(json.dumps(config, ensure_ascii=False, indent="\t"))
EOF
    info "Настройки WE Manager: $MANAGER_CONFIG_DIR/config.json"
}

# Движок ищет файлы пресетов (картинки, видео пользователя) в папке базовых обоев,
# а не в папке пресета. Служба раскладывает копии туда, где он их ищет:
# при входе в систему и каждый раз, когда Steam скачивает обои.
systemd_units() {
    command -v systemctl >/dev/null || { warn "systemd не найден, пресеты придётся чинить вручную: $TOOLS_DIR/we-fix-presets"; return; }
    mkdir -p "$SYSTEMD_USER_DIR"
    cat > "$SYSTEMD_USER_DIR/we-fix-presets.service" <<EOF
[Unit]
Description=Раскладывает файлы пресетов Wallpaper Engine для linux-wallpaperengine

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/python3 -I $TOOLS_DIR/we-fix-presets
# WE Manager может переустановить расширение из комплекта движка — патч накладывается снова
ExecStartPost=-/usr/bin/python3 -I $TOOLS_DIR/patch-gnome-extension $EXT_DIR

[Install]
WantedBy=default.target
EOF
    if [ -n "$workshop_dir" ]; then
        mkdir -p "$workshop_dir"
        cat > "$SYSTEMD_USER_DIR/we-fix-presets.path" <<EOF
[Unit]
Description=Следит за новыми обоями из Мастерской Wallpaper Engine

[Path]
PathChanged=$workshop_dir
Unit=we-fix-presets.service

[Install]
WantedBy=default.target
EOF
    fi
    systemctl --user daemon-reload
    systemctl --user enable --now we-fix-presets.service >/dev/null 2>&1 || warn "не удалось включить we-fix-presets.service"
    if [ -n "$workshop_dir" ]; then
        systemctl --user enable --now we-fix-presets.path >/dev/null 2>&1 || warn "не удалось включить we-fix-presets.path"
    fi
    info "Служба we-fix-presets включена."
}

start_manager() {
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 0
    pgrep -f "^$APP_DIR/squashfs-root/we-manager" >/dev/null && return 0
    (cd "$APP_DIR/squashfs-root" && exec setsid -f ./AppRun >/dev/null 2>&1 < /dev/null) || true
}

# ---------------------------------------------------------------- main

main() {
    printf '%sУстановщик интерактивных обоев Wallpaper Engine для GNOME %s%s\n\n' "$c_bold" "$INSTALLER_VERSION" "$c_reset"
    check_system
    mkdir -p "$CACHE_HOME"
    WORK_DIR="$(mktemp -d "$CACHE_HOME/we-gnome-installer.XXXXXX")"

    find_steam
    fix_snap_steam
    install_manager
    install_engine
    install_gnome_extension
    handle_hanabi
    install_tools
    configure_manager
    desktop_entries
    systemd_units

    echo
    step "Готово"
    if [ "$relogin_needed" = 1 ] && [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
        printf '\n    %sВыйдите из сеанса и войдите снова%s — без этого GNOME не загрузит расширение,\n' "$c_bold" "$c_reset"
        info "и обои не появятся на рабочем столе."
    fi
    info "Дальше: откройте WE Manager → «Мастерская» → «Подписаться» → «Библиотека» → «Воспроизвести обои»."
    info "Чтобы обои возвращались после перезагрузки, добавьте их в плейлист и выберите его"
    info "для автозапуска в настройках WE Manager."
    info "Удаление: $TOOLS_DIR/uninstall.sh"
    start_manager
}

main
