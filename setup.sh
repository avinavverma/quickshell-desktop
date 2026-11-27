#!/usr/bin/env bash
# setup.sh — set up this desktop (taskbar, Switchboard, wallpaper-dialogs) on a
# fresh CachyOS / Arch KDE Plasma 6 (Wayland) machine, including everything
# that lives outside the repo: packages, the Liquid Glass KWin effect, the
# genie (Magic Lamp) minimise animation and the KDE settings they need.
#
#   ./setup.sh            interactive (asks before system-wide or risky steps)
#   ./setup.sh --yes      answer "yes" to every question
#
# Safe to run again: every step checks or overwrites with the same values.
set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
YES=false; [[ "${1:-}" == "--yes" ]] && YES=true

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33m! %s\033[0m\n' "$*"; }
ask()  { $YES && return 0; local a; read -r -p "    $1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy] ]]; }

[[ $EUID -eq 0 ]] && { echo "Run this as your normal user (it uses sudo where needed)."; exit 1; }
command -v pacman >/dev/null || { echo "This script expects an Arch-based system (pacman)."; exit 1; }
[[ "${XDG_SESSION_TYPE:-}" == wayland && "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] \
    || warn "Not a KDE Wayland session right now - settings will still be written, effects load next login."

# --------------------------------------------------------------------------
bold "1/8  Project location"
# Switchboard (and the units it creates) expect the projects in ~/Projects.
if [[ "$REPO" != "$HOME/Projects" ]]; then
    if [[ ! -e "$HOME/Projects" ]]; then
        ln -s "$REPO" "$HOME/Projects" && note "Linked ~/Projects -> $REPO"
    elif [[ "$(readlink -f "$HOME/Projects")" == "$REPO" ]]; then
        note "~/Projects already points here."
    else
        warn "~/Projects exists and is not this repo. Move the repo to ~/Projects (or remove ~/Projects) and re-run."
        exit 1
    fi
else
    note "Repo is at ~/Projects."
fi
P="$HOME/Projects"

# --------------------------------------------------------------------------
bold "2/8  Packages (pacman)"
PKGS=(quickshell jq curl ffmpeg python python-gobject plasma-browser-integration
      plasma-wayland-protocols wlr-protocols wayland gcc pkgconf inter-font
      git base-devel)
missing=(); for p in "${PKGS[@]}"; do pacman -Q "$p" &>/dev/null || missing+=("$p"); done
if (( ${#missing[@]} )); then
    note "Missing: ${missing[*]}"
    if ask "Install them with sudo pacman?"; then sudo pacman -S --needed "${missing[@]}" || warn "pacman failed - fix and re-run."
    else warn "Skipped - parts of the taskbar won't work without them."; fi
else
    note "All present."
fi

# --------------------------------------------------------------------------
bold "3/8  Liquid Glass KWin effect (AUR: kwin-effects-glass-git)"
if pacman -Q kwin-effects-glass-git &>/dev/null; then
    note "Installed."
else
    AUR=""; command -v paru >/dev/null && AUR=paru; [[ -z "$AUR" ]] && command -v yay >/dev/null && AUR=yay
    if [[ -z "$AUR" ]]; then
        warn "No AUR helper (paru/yay) found. Install one, then: paru -S kwin-effects-glass-git"
    elif ask "Build and install kwin-effects-glass-git with $AUR? (community AUR package; builds github.com/4v3ngR/kwin-effects-glass)"; then
        "$AUR" -S --needed kwin-effects-glass-git || warn "AUR install failed - the panels will fall back to KDE's normal blur."
    fi
fi

# --------------------------------------------------------------------------
bold "4/8  iconhelper (makes the genie aim at the dock)"
if "$P/taskbar/iconhelper/build.sh" >/dev/null; then note "Built taskbar/iconhelper/iconhelper"
else warn "Build failed (needs gcc, wayland, plasma-wayland-protocols, wlr-protocols)."; fi

mkdir -p "$HOME/.local/share/kwin/effects"
ln -sfn "$P/taskbar/kwin-effect" "$HOME/.local/share/kwin/effects/dockminimize"
note "Installed the optional 'Squash to Dock' effect (left off; Magic Lamp is used)."

# --------------------------------------------------------------------------
bold "5/8  KDE / KWin settings"
kw() { kwriteconfig6 --notify --file "$1" --group "$2" --key "$3" "$4"; }
# effects: Magic Lamp genie, Liquid Glass instead of the stock blur
kw kwinrc Plugins magiclampEnabled true
kw kwinrc Plugins squashEnabled false
kw kwinrc Plugins dockminimizeEnabled false
if pacman -Q kwin-effects-glass-git &>/dev/null; then
    kw kwinrc Plugins glassEnabled true
    kw kwinrc Plugins blurEnabled false
else
    kw kwinrc Plugins blurEnabled true
    warn "Glass not installed - keeping KDE's normal blur."
fi
# genie length (tuned for animation speed 0.25: 920 x 0.25 ~= 230 ms)
kw kwinrc Effect-magiclamp AnimationDuration 920
kw kdeglobals KDE AnimationDurationFactor 0.25
# Glass look (group name is inherited from the project it forked)
for kv in BlurStrength=6 DockBlurStrength=6 EdgeLighting=true EdgeLightingDock=false \
          RefractionBevelIntensity=10 RefractionEdgeSize=18 RefractionNormalPow=2 \
          RefractionRGBFringing=0.15 RefractionStrength=0.6 RimSpecular=false; do
    kw kwinrc Effect-blurplus "${kv%%=*}" "${kv#*=}"
done
# title-bar buttons: minimise, maximise, close on the right; keep title bars when maximised
kw kwinrc org.kde.kdecoration2 ButtonsOnLeft ""
kw kwinrc org.kde.kdecoration2 ButtonsOnRight IAX
kw kwinrc Windows BorderlessMaximizedWindows false
# Super opens KRunner (and no longer the app launcher)
kwriteconfig6 --file kglobalshortcutsrc --group services --group org.kde.krunner.desktop \
    --key _launch "$(printf 'Meta\tSearch\tAlt+Space\tAlt+F2')"
kwriteconfig6 --file kglobalshortcutsrc --group plasmashell \
    --key "activate application launcher" "Alt+F1,$(printf 'Meta\tAlt+F1'),Activate Application Launcher"
note "Written. (The Super key change takes effect after logging out and in.)"

if qdbus6 org.kde.KWin /KWin reconfigure &>/dev/null; then
    for e in blur squash; do qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$e" &>/dev/null; done
    pacman -Q kwin-effects-glass-git &>/dev/null && qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect glass &>/dev/null
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect magiclamp &>/dev/null
    note "KWin reloaded: magiclamp=$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded magiclamp 2>/dev/null) glass=$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded glass 2>/dev/null)"
fi

# --------------------------------------------------------------------------
bold "6/8  Switchboard launcher"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/switchboard.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Switchboard
Comment=Start and stop your projects
Exec=qs -n -p $P/switchboard
Icon=preferences-system
Terminal=false
Categories=Utility;
EOF
chmod +x "$P/switchboard/ctl.sh"
note "Added 'Switchboard' to the app launcher."

# --------------------------------------------------------------------------
bold "7/8  Start the taskbar (and at login)"
"$P/switchboard/ctl.sh" enable taskbar && note "taskbar: starts at login"
"$P/switchboard/ctl.sh" start taskbar && note "taskbar: running"
if ask "Also start the wallpaper dialogs at login? (only useful with the same wallpaper)"; then
    "$P/switchboard/ctl.sh" enable wallpaper-dialogs; "$P/switchboard/ctl.sh" start wallpaper-dialogs
fi

# --------------------------------------------------------------------------
bold "8/8  Plasma panel"
n=$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'print(panels().length)' 2>/dev/null || echo "?")
if [[ "$n" == "0" ]]; then
    note "No Plasma panels - nothing to do."
elif [[ "$n" == "?" ]]; then
    warn "Couldn't reach plasmashell - remove the panel yourself if you like."
elif ask "Remove KDE's own panel ($n found)? Its config is backed up first."; then
    cp ~/.config/plasma-org.kde.plasma.desktop-appletsrc ~/.config/plasma-org.kde.plasma.desktop-appletsrc.before-taskbar
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript 'panels().forEach(p => p.remove())' >/dev/null
    note "Removed. Backup: ~/.config/plasma-org.kde.plasma.desktop-appletsrc.before-taskbar"
    note "To get it back: right-click the desktop -> Add Panel -> Default Panel."
fi

# --------------------------------------------------------------------------
bold "Done. A few things only you can do:"
note "- Log out and back in once (Super -> KRunner, and a clean start for all effects)."
note "- Firefox: install KDE's 'Plasma Integration' add-on for the media progress bar:"
note "  https://addons.mozilla.org/firefox/addon/plasma-integration/"
note "- After big KDE updates, rebuild Glass if the blur disappears: paru -S kwin-effects-glass-git"
