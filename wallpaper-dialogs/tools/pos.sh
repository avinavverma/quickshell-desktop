#!/usr/bin/env bash
# Testing helper: print the pointer position "x y" via a KWin script (exact, unlike cursor_at.py).
S=${TMPDIR:-/tmp}/pos_$$.js
echo 'print("CP|" + Math.round(workspace.cursorPos.x) + "|" + Math.round(workspace.cursorPos.y));' > $S
id=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript $S wdpos$$)
qdbus6 org.kde.KWin /Scripting/Script$id org.kde.kwin.Script.run >/dev/null
sleep 0.25
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript wdpos$$ >/dev/null
rm -f $S
journalctl --user --since "-3s" -o cat | grep -a "CP|" | tail -1 | awk -F'|' '{print $2, $3}'
