#!/usr/bin/env bash
# setup.sh — set up this whole desktop on a fresh CachyOS / Arch KDE Plasma 6
# (Wayland) machine: the projects (taskbar, Switchboard, wallpaper-dialogs) AND
# everything that lives outside the repo — packages, the Liquid Glass KWin
# effect, the genie (Magic Lamp) minimise animation, KDE/KWin settings, the
# look (icon pack, colours, cursor, wallpaper), touchpad-gesture permissions,
# keyd key swaps and the Firefox media add-on.
#
#   ./setup.sh            interactive (asks before system-wide or optional steps)
#   ./setup.sh --yes      take the default answer to every question
#
# Safe to run again: every step checks first or rewrites the same values.
set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
YES=false; [[ "${1:-}" == "--yes" ]] && YES=true

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33m! %s\033[0m\n' "$*"; }
ask()    { $YES && return 0; local a; read -r -p "    $1 [Y/n] " a; [[ -z "$a" || "$a" =~ ^[Yy] ]]; }   # default yes
ask_no() { $YES && return 1; local a; read -r -p "    $1 [y/N] " a; [[ "$a" =~ ^[Yy] ]]; }                # default no
kw() { kwriteconfig6 --notify --file "$1" --group "$2" --key "$3" "$4"; }
NEED_RELOGIN=false

[[ $EUID -eq 0 ]] && { echo "Run this as your normal user (it uses sudo where needed)."; exit 1; }
command -v pacman >/dev/null || { echo "This script expects an Arch-based system (pacman)."; exit 1; }
[[ "${XDG_SESSION_TYPE:-}" == wayland && "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] \
    || warn "Not a KDE Wayland session right now - settings are still written; effects load at next login."

# ==========================================================================
bold "1/12  Project location"
# Switchboard (and the systemd units it creates) expect the projects in ~/Projects.
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

# ==========================================================================
bold "2/12  Packages (pacman)"
PKGS=(quickshell qt6-tools jq curl ffmpeg python python-gobject plasma-browser-integration
      plasma-wayland-protocols wlr-protocols wayland gcc pkgconf inter-font
      git base-devel xz)
missing=(); for p in "${PKGS[@]}"; do pacman -Q "$p" &>/dev/null || missing+=("$p"); done
if (( ${#missing[@]} )); then
    note "Missing: ${missing[*]}"
    if ask "Install them with sudo pacman?"; then sudo pacman -S --needed "${missing[@]}" || warn "pacman failed - fix and re-run."
    else warn "Skipped - parts of the taskbar won't work without them."; fi
else
    note "All present."
fi

# ==========================================================================
bold "3/12  Liquid Glass KWin effect (AUR: kwin-effects-glass-git)"
if pacman -Q kwin-effects-glass-git &>/dev/null; then
    note "Installed."
else
    AUR=""; command -v paru >/dev/null && AUR=paru; [[ -z "$AUR" ]] && command -v yay >/dev/null && AUR=yay
    if [[ -z "$AUR" ]]; then
        warn "No AUR helper (paru/yay) found. Install one, then: paru -S kwin-effects-glass-git"
    elif ask "Build and install kwin-effects-glass-git with $AUR? (community AUR package; builds github.com/4v3ngR/kwin-effects-glass)"; then
        "$AUR" -S --needed kwin-effects-glass-git || warn "AUR install failed - the panels fall back to KDE's normal blur."
    fi
fi

# ==========================================================================
bold "4/12  iconhelper (makes the genie aim at the dock)"
if "$P/taskbar/iconhelper/build.sh" >/dev/null; then note "Built taskbar/iconhelper/iconhelper"
else warn "Build failed (needs gcc, wayland, plasma-wayland-protocols, wlr-protocols)."; fi
mkdir -p "$HOME/.local/share/kwin/effects"
ln -sfn "$P/taskbar/kwin-effect" "$HOME/.local/share/kwin/effects/dockminimize"
note "Installed the optional 'Squash to Dock' effect (left off; Magic Lamp is used)."

# ==========================================================================
bold "5/12  KDE / KWin behaviour"
# effects: Magic Lamp genie; Liquid Glass instead of the stock blur
kw kwinrc Plugins magiclampEnabled true
kw kwinrc Plugins squashEnabled false
kw kwinrc Plugins dockminimizeEnabled false
if pacman -Q kwin-effects-glass-git &>/dev/null; then
    kw kwinrc Plugins glassEnabled true;  kw kwinrc Plugins blurEnabled false
else
    kw kwinrc Plugins blurEnabled true;   warn "Glass not installed - keeping KDE's normal blur."
fi
# genie length (tuned for animation speed 0.25: 920 x 0.25 ~= 230 ms)
kw kwinrc Effect-magiclamp AnimationDuration 920
kw kdeglobals KDE AnimationDurationFactor 0.25
# Glass look (the group name is inherited from the project it forked)
for kv in BlurStrength=6 DockBlurStrength=6 EdgeLighting=true EdgeLightingDock=false \
          RefractionBevelIntensity=10 RefractionEdgeSize=18 RefractionNormalPow=2 \
          RefractionRGBFringing=0.15 RefractionStrength=0.6 RimSpecular=false; do
    kw kwinrc Effect-blurplus "${kv%%=*}" "${kv#*=}"
done
# title bars: Breeze, minimise / maximise / close on the right, kept when maximised
kw kwinrc org.kde.kdecoration2 library org.kde.breeze
kw kwinrc org.kde.kdecoration2 theme Breeze
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

# ==========================================================================
bold "6/12  Look: icon pack, colours, cursor, wallpaper"
ICONS="Mkos-Big-Sur-Night"
if [[ ! -d "$HOME/.local/share/icons/$ICONS" ]]; then
    mkdir -p "$HOME/.local/share/icons"
    tar -xJf "$P/assets/icons/$ICONS.tar.xz" -C "$HOME/.local/share/icons" && note "Unpacked the $ICONS icon pack."
fi
/usr/lib/plasma-changeicons "$ICONS" &>/dev/null || kw kdeglobals Icons Theme "$ICONS"
note "Icons: $ICONS"
plasma-apply-colorscheme BreezeDark &>/dev/null; note "Colours: Breeze Dark"
plasma-apply-cursortheme breeze_cursors &>/dev/null; note "Cursor: Breeze"
# Wallpaper: the usual one, or the image the floating dialogs belong to.
WALL="$P/assets/wallpaper.jpg"; DIALOGS=false
if ask_no "Use the floating 3D dialogs wallpaper (wallpaper-dialogs) instead of your usual one?"; then
    WALL="$P/wallpaper-dialogs/wallpaper.jpg"; DIALOGS=true
fi
plasma-apply-wallpaperimage "$WALL" &>/dev/null && note "Wallpaper: ${WALL#$P/}" || warn "Couldn't set the wallpaper (plasmashell not running?)."

# ==========================================================================
bold "7/12  Touchpad gestures (four-finger tap, left-edge media)"
# They read the touchpad directly and the edge one creates a virtual touchpad,
# so they need the 'input' group and write access to /dev/uinput.
if id -nG | tr ' ' '\n' | grep -qx input; then
    note "You're in the 'input' group."
elif ask "Add you to the 'input' group? (sudo; lets the gesture helpers read the touchpad)"; then
    sudo usermod -aG input "$USER" && { note "Added - takes effect after logging out and in."; NEED_RELOGIN=true; }
fi
RULE=/etc/udev/rules.d/80-taskbar-uinput.rules
if [[ ! -f "$RULE" ]]; then
    if ask "Give the 'input' group access to /dev/uinput? (sudo; one udev rule + load the uinput module at boot)"; then
        echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' | sudo tee "$RULE" >/dev/null
        echo uinput | sudo tee /etc/modules-load.d/taskbar-uinput.conf >/dev/null
        sudo modprobe uinput; sudo udevadm control --reload; sudo udevadm trigger --name-match=uinput
        note "Done: $RULE"
    fi
else
    note "uinput rule already in place."
fi

# ==========================================================================
bold "8/12  keyd key swaps (Right Alt <-> Super, PrtScr <-> Insert)"
note "Made for the original laptop's keyboard - skip it if this keyboard is different."
if ask_no "Install keyd with these swaps? (sudo)"; then
    pacman -Q keyd &>/dev/null || sudo pacman -S --needed keyd
    sudo mkdir -p /etc/keyd
    [[ -f /etc/keyd/default.conf ]] && ! cmp -s /etc/keyd/default.conf "$P/assets/keyd/default.conf" \
        && sudo cp /etc/keyd/default.conf "/etc/keyd/default.conf.bak-$(date +%s)" && note "Backed up the existing keyd config."
    sudo cp "$P/assets/keyd/default.conf" /etc/keyd/default.conf
    sudo systemctl enable --now keyd && sudo keyd reload &>/dev/null
    note "keyd running with the swaps."
fi

# ==========================================================================
bold "9/12  Firefox media add-on (Plasma Integration)"
POL=/etc/firefox/policies/policies.json
if [[ -f "$POL" ]]; then
    grep -q 'plasma-browser-integration@kde.org' "$POL" && note "Already set up by policy." \
        || note "A Firefox policy file already exists - add the add-on yourself: https://addons.mozilla.org/firefox/addon/plasma-integration/"
elif ask "Have Firefox install KDE's Plasma Integration add-on automatically? (sudo; a Firefox policy file - needed for the media progress bar)"; then
    sudo mkdir -p /etc/firefox/policies
    sudo tee "$POL" >/dev/null <<'EOF'
{
  "policies": {
    "ExtensionSettings": {
      "plasma-browser-integration@kde.org": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/plasma-integration/latest.xpi"
      }
    }
  }
}
EOF
    note "Done - Firefox installs it on its next start."
fi

# ==========================================================================
bold "10/12  Switchboard launcher"
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

# ==========================================================================
bold "11/12  Start the taskbar (and at login)"
# The taskbar's own behaviour - dock auto-hide (slides up at the bottom edge,
# stays up while the desktop is visible), modules, pins in taskbar/dock.json -
# is all in the repo, so it comes along with the clone.
"$P/switchboard/ctl.sh" enable taskbar && note "taskbar: starts at login"
"$P/switchboard/ctl.sh" start taskbar && note "taskbar: running"
if $DIALOGS; then
    "$P/switchboard/ctl.sh" enable wallpaper-dialogs; "$P/switchboard/ctl.sh" start wallpaper-dialogs
    note "wallpaper-dialogs: running and starts at login"
fi

# ==========================================================================
bold "12/12  KDE's own panel"
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

# ==========================================================================
bold "Done."
note "- Log out and back in once (Super -> KRunner$($NEED_RELOGIN && echo ', input group for the gestures'), clean start for all effects)."
note "- After big KDE updates, rebuild Glass if the blur disappears: paru -S kwin-effects-glass-git"
