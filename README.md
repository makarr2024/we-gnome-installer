# Интерактивные обои Wallpaper Engine для Ubuntu (GNOME)

📖 **Полная инструкция:** [makarr2024.github.io/we-gnome-installer](https://makarr2024.github.io/we-gnome-installer/) — как сделать, чтобы Wallpaper Engine работал на Linux Ubuntu.

Установщик в одну команду: живые обои из Мастерской Steam на рабочем столе Ubuntu,
как в Wallpaper Engine на Windows. Сцены и веб-обои реагируют на курсор, видео
проигрывается, обои выбираются в удобном менеджере.

Ставит и настраивает:

- [WE Manager](https://github.com/WallpaperEngineLover/we_manager) — библиотека, Мастерская, плейлисты, настройки;
- [linux-wallpaperengine](https://github.com/WallpaperEngineLover/linux-wallpaperengine-kde) — движок, который рисует обои;
- расширение GNOME Shell из комплекта движка — кладёт обои под рабочий стол и передаёт движку курсор.

И чинит то, что «из коробки» не работает:

| Проблема | Что делает установщик |
|---|---|
| Steam установлен как snap — «Steam not running» во вкладке «Мастерская» | создаёт ссылку `~/.steam` → `~/snap/steam/common/.steam` |
| Пресеты с картинкой пользователя (например, к «ASCII Digital Image») показывают белый/пустой экран | служба `we-fix-presets` раскладывает файлы пресетов туда, где их ищет движок, — при входе в систему и после каждой загрузки из Мастерской |
| Расширение Hanabi рисует свои обои поверх | предлагает его отключить |
| AppImage требует FUSE (`libfuse2`) | AppImage распаковывается, FUSE не нужен |

Всё ставится в домашнюю папку, `sudo` не нужен. Скачанные файлы сверяются
с контрольными суммами SHA-256 из релизов на GitHub.

## Требования

- **Ubuntu 22.04 или новее** (или другой дистрибутив с glibc 2.35+), процессор **x86_64**;
- **GNOME** (Wayland или X11). На KDE, Sway, Hyprland движок работает сам по себе,
  но расширение GNOME и часть советов к ним не относятся;
- **Wallpaper Engine, купленный и установленный в Steam** (подойдёт обычный Steam,
  snap или flatpak). Запускать сам Wallpaper Engine не нужно — нужны его ассеты и Мастерская;
- видеокарта с OpenGL 3.3 и ~1.5 ГБ свободного места.

Проверено: Ubuntu 24.04, GNOME 46, Wayland, Steam из snap, WE Manager v0.9.6, linux-wallpaperengine v0.9.7.

## Установка

Одна команда в терминале:

```bash
curl -fsSL https://raw.githubusercontent.com/makarr2024/we-gnome-installer/main/get.sh | bash
```

С параметрами (см. ниже) — после `-s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/makarr2024/we-gnome-installer/main/get.sh | bash -s -- --disable-hanabi
```

Команда скачивает последний релиз установщика и запускает `install.sh`.
Если `curl` нет: `sudo apt install curl`.

Или вручную:

```bash
git clone https://github.com/makarr2024/we-gnome-installer.git
cd we-gnome-installer
./install.sh
```

После первой установки **выйдите из сеанса и войдите снова** — GNOME загружает новые
расширения только при входе. Без этого обои не появятся.

Параметры:

```
--manager-version TAG   версия WE Manager (по умолчанию последняя)
--engine-version TAG    версия движка (по умолчанию последняя)
--no-autostart          не запускать WE Manager при входе в систему
--disable-hanabi        отключить Hanabi без вопроса
--force                 переустановить, даже если версия совпадает
-y, --yes               не задавать вопросов
```

Обновление — запустите команду установки ещё раз: он скачает только то, что вышло новее.

## Как пользоваться

1. Откройте **WE Manager** (меню приложений). Steam должен быть запущен.
2. **«Мастерская»** → найдите обои → **«Подписаться»** (один раз — повторное нажатие отписывает и удаляет файлы).
3. Дождитесь загрузки → **«Библиотека»** → нажмите на обои → **«Воспроизвести обои»**.
4. Чтобы обои возвращались после перезагрузки: **«Плейлисты»** → создайте плейлист с ними →
   в **«Настройках»** выберите его для автозапуска.

На курсор реагируют обои типа **Scene** и **Web**; **Video** просто проигрывается.
В Мастерской есть фильтр **«Тип»**.

## Если что-то не работает

- **Обои не появились после установки** — вы не перезашли в сеанс. Проверьте:
  `gnome-extensions info linux-wallpaperengine@wallpaperenginelover.github.io` → `State: ACTIVE`.
- **«Steam not running» в Мастерской** — Steam не запущен, или окно WE Manager свёрнуто
  (к Steam он подключается только с открытым окном). Для snap-Steam должна существовать ссылка `~/.steam`.
- **Белый или пустой экран у пресета** — запустите вручную и посмотрите вывод:
  `python3 ~/.local/share/we-gnome-installer/we-fix-presets -v`.
- **Белый экран у обычных обоев** — их файлы удалены (например, после отписки). Подпишитесь заново.
- **Обои не реагируют на музыку** — они слушают звук, который играет на компьютере, а не микрофон.
  Включите музыку на ПК; реагируют только обои с поддержкой звука («Audio responsive»).
- **Сцена выглядит не так, как на Windows** — движок поддерживает не все эффекты Wallpaper Engine;
  это ограничение linux-wallpaperengine, а не установщика.

## Удаление

```bash
~/.local/share/we-gnome-installer/uninstall.sh          # программы, расширение, службы
~/.local/share/we-gnome-installer/uninstall.sh --purge  # и настройки/плейлисты WE Manager
```

Обои из Мастерской и Steam не затрагиваются. Ссылка `~/.steam` удаляется, только если её создал установщик.

## Что куда ставится

| Путь | Что |
|---|---|
| `~/.local/share/we-manager-app/` | WE Manager (распакованный AppImage) |
| `~/.local/share/linux-wallpaperengine-kde/` | движок (там же его ищет WE Manager) |
| `~/.local/share/gnome-shell/extensions/linux-wallpaperengine@wallpaperenginelover.github.io/` | расширение GNOME |
| `~/.local/share/we-gnome-installer/` | `we-fix-presets`, `uninstall.sh` |
| `~/.config/systemd/user/we-fix-presets.{service,path}` | служба исправления пресетов |
| `~/.config/autostart/we-manager.desktop` | автозапуск |
| `~/.config/we-manager/config.json` | настройки WE Manager (путь к Мастерской, язык, автозапуск) |

## Благодарности

Вся основная работа — в проектах [WE Manager](https://github.com/WallpaperEngineLover/we_manager)
и [linux-wallpaperengine](https://github.com/WallpaperEngineLover/linux-wallpaperengine-kde)
(форк [Almamu/linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine)).
Этот репозиторий только устанавливает и настраивает их. Wallpaper Engine — продукт Wallpaper Engine Team,
обои и ассеты берутся из вашей копии в Steam.

## Лицензия

© 2026 makarr2024. Все права защищены — см. [LICENSE](LICENSE).
Устанавливать и пользоваться можно свободно, в том числе на работе. Копировать, публиковать,
изменять и распространять установщик или его части без разрешения автора нельзя.
Ссылаться на этот репозиторий и команду установки — можно.

Устанавливаемые программы (WE Manager, linux-wallpaperengine) — отдельные проекты своих авторов
под своими лицензиями.
