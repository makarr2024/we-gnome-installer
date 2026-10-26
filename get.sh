#!/usr/bin/env bash
# Быстрая установка одной командой:
#
#   curl -fsSL https://raw.githubusercontent.com/makarr2024/we-gnome-installer/main/get.sh | bash
#
# Параметры install.sh передаются после "-s --":
#
#   curl -fsSL https://raw.githubusercontent.com/makarr2024/we-gnome-installer/main/get.sh | bash -s -- --disable-hanabi
#
# Скачивает последний релиз установщика во временную папку и запускает install.sh.
# WE_INSTALLER_REF=main — взять ветку вместо релиза; WE_INSTALLER_URL — свой архив (.tar.gz).

# всё внутри функции: если загрузка оборвётся, bash не выполнит половину скрипта
main() {
    set -euo pipefail

    local repo="makarr2024/we-gnome-installer"
    local ref="${WE_INSTALLER_REF:-}"
    local url="${WE_INSTALLER_URL:-}"

    command -v curl >/dev/null || { echo "Нужен curl: sudo apt install curl" >&2; exit 1; }
    command -v tar >/dev/null || { echo "Нужен tar: sudo apt install tar" >&2; exit 1; }

    if [ -z "$url" ]; then
        if [ -z "$ref" ]; then
            ref="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
                | sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p' | head -1 || true)"
            ref="${ref:-main}"
        fi
        url="https://github.com/$repo/archive/$ref.tar.gz"
    fi

    WE_INSTALLER_TMP="$(mktemp -d "${TMPDIR:-/tmp}/we-gnome-installer.XXXXXX")"
    trap 'rm -rf "${WE_INSTALLER_TMP:-}"' EXIT
    local tmp="$WE_INSTALLER_TMP"

    echo "==> Загрузка установщика${ref:+ ($ref)}"
    curl -fsSL --retry 3 "$url" | tar -xz -C "$tmp" --strip-components=1
    [ -x "$tmp/install.sh" ] || { echo "В архиве нет install.sh: $url" >&2; exit 1; }

    # stdin занят самим скриптом из curl, вопросы установщика читаем с терминала
    if [ -t 1 ] && { : < /dev/tty; } 2>/dev/null; then
        "$tmp/install.sh" "$@" < /dev/tty
    else
        "$tmp/install.sh" --yes "$@"
    fi
}

main "$@"
