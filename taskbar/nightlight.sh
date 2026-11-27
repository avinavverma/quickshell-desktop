#!/bin/sh
# Turn KWin's Night Light on (constant, all day) or off:   nightlight.sh on|off
# KWin only re-reads these settings when it is *notified* of a change (kwriteconfig6 --notify),
# and kwriteconfig6 sends nothing if the value in the file is already the same - which happens
# when the file and KWin disagree. So a value that is already there is first flipped and then set.
set_key() {   # key value other-value
    if [ "$(kreadconfig6 --file kwinrc --group NightColor --key "$1")" = "$2" ]; then
        kwriteconfig6 --notify --file kwinrc --group NightColor --key "$1" "$3"
    fi
    kwriteconfig6 --notify --file kwinrc --group NightColor --key "$1" "$2"
}
case "$1" in
    on)  set_key Mode Constant Automatic; set_key Active true false ;;
    off) set_key Active false true ;;
    *)   echo "usage: $0 on|off" >&2; exit 1 ;;
esac
