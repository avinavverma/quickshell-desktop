/*
    Squash to Dock — based on KWin's built-in Squash effect (GPL-2.0-or-later,
    Rivo Laks, Vlad Zahorodnii).

    Squash only animates when the taskbar has told KWin where the window's icon
    is. Only Plasma's own taskbar can do that, so with the custom dock Squash
    does nothing. Instead, the taskbar's windows.py writes each dock icon's
    position into this effect's config (IconRects) and asks KWin to reload it.
    Windows are matched by class + title, then class alone; anything unknown
    goes to the dock's centre.

    Keep DOCK_* in sync with Theme.qml (gap, barHeight).
*/
"use strict";

const DOCK_GAP = 10;      // Theme.gap
const DOCK_HEIGHT = 64;   // Theme.dockHeight
const ICON = 54;          // size of a dock icon slot
const SLOWMO = 1;         // >1 slows everything down (for testing)
const MIN_MS = 400;       // shortest the stretch may run

var dockEffect = {
    duration: 0,
    iconRects: {},

    loadConfig: function () {
        // KWin scales animations by the global speed setting; on a fast setting the
        // stretch is over before you can see it, so never go below MIN_MS
        // (but still respect "animations off", where animationTime() is 0).
        const base = animationTime(450);
        dockEffect.duration = (base === 0 ? 0 : Math.max(base, MIN_MS)) * SLOWMO;
        try {
            dockEffect.iconRects = JSON.parse(effect.readConfig("IconRects", "{}"));
        } catch (e) {
            dockEffect.iconRects = {};
        }
    },

    dockIcon: function (window) {
        const r = dockEffect.iconRects[window.windowClass + "\n" + window.caption]
               || dockEffect.iconRects[window.windowClass];
        return r ? { x: r[0], y: r[1], width: r[2], height: r[3] } : null;
    },

    // Where the window should shrink to: its real taskbar icon if KWin knows it,
    // otherwise the dock at the bottom centre of its screen.
    targetRect: function (window) {
        const icon = window.iconGeometry;
        if (icon.width > 0 && icon.height > 0) {
            return icon;
        }
        const docked = dockEffect.dockIcon(window);
        if (docked) {
            return docked;
        }
        const screen = window.screen ? window.screen.geometry : effects.virtualScreenGeometry;
        return {
            x: screen.x + screen.width / 2 - ICON / 2,
            y: screen.y + screen.height - DOCK_GAP - DOCK_HEIGHT / 2 - ICON / 2,
            width: ICON,
            height: ICON,
        };
    },

    // Stretch: width and height animate separately (a negative value leaves
    // that axis alone), so the window pours out of the icon as a tall narrow
    // strip and then widens — and on minimise narrows first, then drains down.
    animations: function (window, toIcon) {
        const w = window.geometry;
        const icon = dockEffect.targetRect(window);
        const D = dockEffect.duration;
        const SKIP = -1;
        const home = { value1: 0.0, value2: 0.0 };
        const away = {   // from window centre to icon centre
            value1: icon.x + icon.width / 2 - (w.x + w.width / 2),
            value2: icon.y + icon.height / 2 - (w.y + w.height / 2),
        };
        const width  = (a, b) => ({ from: { value1: a, value2: SKIP }, to: { value1: b, value2: SKIP } });
        const height = (a, b) => ({ from: { value1: SKIP, value2: a }, to: { value1: SKIP, value2: b } });

        if (!toIcon) {   // restore: shoot up out of the icon, then widen
            return [
                Object.assign({ type: Effect.Size, duration: D * 0.55, curve: QEasingCurve.OutCubic },
                              height(icon.height, w.height)),
                Object.assign({ type: Effect.Size, duration: D, curve: QEasingCurve.InOutCubic },
                              width(icon.width, w.width)),
                { type: Effect.Translation, from: away, to: home, duration: D * 0.7, curve: QEasingCurve.OutCubic },
                { type: Effect.Opacity, from: 0.0, to: 1.0, duration: D * 0.3, curve: QEasingCurve.Linear },
            ];
        }
        // minimise: narrow first, then get pulled down into the icon
        return [
            Object.assign({ type: Effect.Size, duration: D * 0.6, curve: QEasingCurve.InOutCubic },
                          width(w.width, icon.width)),
            Object.assign({ type: Effect.Size, duration: D, curve: QEasingCurve.InCubic },
                          height(w.height, icon.height)),
            { type: Effect.Translation, from: home, to: away, duration: D, curve: QEasingCurve.InCubic },
            { type: Effect.Opacity, from: 1.0, to: 0.0, duration: D, curve: QEasingCurve.InQuint },  // stays solid, fades at the end
        ];
    },

    slotWindowMinimized: function (window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }
        if (window.unminimizeAnimation) {
            if (redirect(window.unminimizeAnimation, Effect.Backward)) {
                return;
            }
            cancel(window.unminimizeAnimation);
            delete window.unminimizeAnimation;
        }
        if (window.minimizeAnimation) {
            if (redirect(window.minimizeAnimation, Effect.Forward)) {
                return;
            }
            cancel(window.minimizeAnimation);
        }
        window.setData(Effect.WindowForceBlurRole, true);
        window.minimizeAnimation = animate({
            window: window,
            curve: QEasingCurve.InCubic,
            duration: dockEffect.duration,
            keepAlive: false,
            animations: dockEffect.animations(window, true),
        });
    },

    slotWindowUnminimized: function (window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }
        if (window.minimizeAnimation) {
            if (redirect(window.minimizeAnimation, Effect.Backward)) {
                return;
            }
            cancel(window.minimizeAnimation);
            delete window.minimizeAnimation;
        }
        if (window.unminimizeAnimation) {
            if (redirect(window.unminimizeAnimation, Effect.Forward)) {
                return;
            }
            cancel(window.unminimizeAnimation);
        }
        window.setData(Effect.WindowForceBlurRole, true);
        window.unminimizeAnimation = animate({
            window: window,
            curve: QEasingCurve.OutCubic,
            duration: dockEffect.duration,
            keepAlive: false,
            animations: dockEffect.animations(window, false),
        });
    },

    slotWindowAdded: function (window) {
        window.minimizedChanged.connect(() => {
            if (window.minimized) {
                dockEffect.slotWindowMinimized(window);
            } else {
                dockEffect.slotWindowUnminimized(window);
            }
        });
    },

    restoreForceBlurState: function (window) {
        window.setData(Effect.WindowForceBlurRole, null);
    },

    init: function () {
        dockEffect.loadConfig();
        effect.configChanged.connect(dockEffect.loadConfig);
        effect.animationEnded.connect(dockEffect.restoreForceBlurState);
        effects.windowAdded.connect(dockEffect.slotWindowAdded);
        for (const window of effects.stackingOrder) {
            dockEffect.slotWindowAdded(window);
        }
    },
};

dockEffect.init();
