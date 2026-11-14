# quickshell-desktop

My KDE Plasma (Wayland) desktop, built with [Quickshell](https://quickshell.org):

| Folder | What it is |
|---|---|
| `taskbar/` | macOS-style top bar and dock (media chip + card, synced lyrics, Control Center, lyrics desktop widget, …). Runs as `sb-taskbar.service`. See `taskbar/DEVLOG.md` for the history and gotchas. |
| `switchboard/` | GUI that starts / stops every project in this folder as a systemd user unit (`ctl.sh`) and toggles their modules. |
| `wallpaper-dialogs/` | Makes the "Serious error occurred" boxes in the wallpaper float, tilt and cast shadows; the eye follows the cover-art colour. See its own README. |

Every folder with a `shell.qml` (or an executable `run.sh`) shows up in Switchboard.

Needs: Quickshell, `jq`, `curl`, `ffmpeg`, Python 3 with GLib bindings, and the Plasma Browser Integration add-on for browser media. The taskbar's glass look uses the `kwin-effects-glass` KWin effect.
