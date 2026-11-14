# wallpaper-dialogs

Makes the "Serious error occurred" boxes in the wallpaper (`wallpaper.jpg`, a copy of
`~/Downloads/computer girl 2.jpg`) lift, tilt toward the cursor and cast a shadow on hover.

- `shell.qml`: one full-screen layer-shell window per screen on `WlrLayer.Bottom`
  (above Plasma's desktop, below windows and the taskbar). It shows the same image
  cropped like Plasma's "Scaled and Cropped", so at rest the desktop looks unchanged.
  Only the dialog rectangles take input; everything else passes through.
- `Dialog.qml`: one box, drawn as its own item that is hidden while idle (no cost).
  Spring-animated tilt (perspective `Rotation`s), 7% scale-up, lift, `RectangularShadow`, a light sheen.
- `dialogs.json`: each box's outline as a polygon (`poly`, image pixels 3840×2160) in stacking
  order, later = in front. Old `x,y,w,h` rects still load. Reloads live on save.
- `Editor.qml`: the outline editor (see below).
- `tools/detect.py`: finds the white title bars (pure Python, run on an ffmpeg-made
  960×540 gray raw). `tools/goto.sh` / `cursor_at.py`: test helpers that move the pointer with ydotool.

## Drawing outlines

Run `tools/edit.sh` (or `qs -p ~/Projects/wallpaper-dialogs ipc call editor toggle`) while the project
is running. A full-screen overlay shows the wallpaper with every outline:

- drag a corner to move it; drag an edge to add a corner; drag inside to move the whole outline
- right-click a corner to remove it; right-click inside to delete the outline
- `N` draws a new outline (click corners, click the pink first point or press Enter to close)
- `[` / `]` send back / bring forward; arrow keys nudge (Shift = 10 px)
- `S` / Enter saves to `dialogs.json` and exits; Esc exits without saving

Start/stop and "at login" from Switchboard (unit `sb-wallpaper-dialogs.service`).
If you change the KDE wallpaper, stop this, or it will keep covering the new one with this image.

## Idle float
Every box drifts and tilts a little all the time (one shared clock, a few px and ~1 degree), with a faint
shadow; boxes are drawn 2.5% larger so the flat wallpaper copy underneath never shows. Optional in
`dialogs.json`: `"float": {"enabled": true, "amount": 1.0}` (0.5 calmer, 2 floatier; `enabled: false` = static again).

## Opening the editor from Switchboard
`modules.json` gives Switchboard an "Outline editor" switch for this project. Turn it on to open the editor;
saving (S) or leaving (Esc) turns the switch back off. `tools/edit.sh` still works and keeps the switch in sync.

## Eye follows the cover art
The taskbar (`NowPlaying.qml`) writes the playing song's accent colour to `$XDG_RUNTIME_DIR/taskbar-accent`
(`#rrggbb`, or `none` when nothing plays). `EyeTint.qml` + `shaders/hueshift.frag` re-hue the eye patch of the
wallpaper (`"eye": {"rect": [x, y, w, h], "spread": 0.45}` in `dialogs.json`, image pixels; `spread` is how much of the
original colour variety survives) and fade back to the original pink when music stops.
Switch it off from Switchboard ("Eye follows cover art"). After editing `shaders/hueshift.frag`, rebuild with
`/usr/lib/qt6/bin/qsb --qt6 -o shaders/hueshift.frag.qsb shaders/hueshift.frag`.

### Painting the eye mask
Only the painted part of the eye patch is recoloured (`eye-mask.png`, alpha = where; it starts as a soft circle on the iris).
Open the paintbrush from Switchboard (switch "Eye mask painter") or `tools/paint-eye.sh`: the eye patch fills the screen,
left-drag paints, right-drag/`E` erases, wheel or `[ ]` sets the brush size, `V` shows the mask alone, `C` clears,
`R` resets to a circle, `Ctrl+Z` undoes (up to every stroke since you opened it), `Ctrl+Shift+Z` / `Ctrl+Y` redoes, `S`/Enter saves and exits, Esc exits without saving. The wallpaper updates immediately.

### Matching the cover colour exactly
Inside the painted part the wallpaper's own pink cast is removed: only its light/dark is kept and repainted in the
cover-art accent (shadows dark accent, the iris/heart = the accent, glints a bit lighter), so a red cover gives a red eye,
not pink. `"eye": {"variety": 0.0}` in `dialogs.json` blends the original colour variety back in (0 = pure accent, 1 = hue-shifted original).
