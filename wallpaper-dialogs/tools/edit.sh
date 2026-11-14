#!/usr/bin/env bash
# Toggle the outline editor (wallpaper-dialogs must be running).
exec qs -p "$(dirname "$(readlink -f "$0")")/.." ipc call editor toggle
