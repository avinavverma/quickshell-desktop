#!/usr/bin/env bash
# Open (or close) the eye-mask paintbrush. wallpaper-dialogs must be running.
exec qs -p "$(dirname "$0")/.." ipc call eyepaint toggle
