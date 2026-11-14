/*
 * iconhelper — tells KWin where each window's icon is in the custom dock, so
 * KWin's minimise effects (Magic Lamp / genie, Squash) can animate into it.
 *
 * Plasma's own taskbar does this through the org_kde_plasma_window_management
 * protocol: set_minimized_geometry(panel_surface, x, y, w, h), where x/y are
 * relative to a surface the caller owns. Quickshell can't speak that protocol,
 * so this tiny client does it: it maps an invisible 1x1 layer-shell surface at
 * the top-left corner of the screen and reports icon rects relative to it
 * (i.e. in plain screen coordinates).
 *
 * Input on stdin, one snapshot at a time (sent by windows.py):
 *     <uuid> <x> <y> <w> <h>      one line per window, screen coordinates
 *     end                         applies the snapshot; windows not in it are cleared
 *
 * Limitation: assumes the dock is on the screen whose top-left is (0, 0).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

#include "plasma-window-management-client-protocol.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#define MAX_WINDOWS 256

/* layer-shell's get_popup request references xdg_popup; we never use popups,
 * so a stub declaration is enough (avoids needing the xdg-shell protocol). */
const struct wl_interface xdg_popup_interface = { "xdg_popup", 1, 0, NULL, 0, NULL };

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct org_kde_plasma_window_management *wm;
static struct wl_surface *anchor;
static int configured;

struct entry {
    char uuid[64];
    struct org_kde_plasma_window *win;
    int seen;   /* present in the snapshot being built */
};
static struct entry entries[MAX_WINDOWS];

/* ---------- registry ---------- */

static void global_add(void *data, struct wl_registry *reg, uint32_t name,
                       const char *iface, uint32_t version) {
    (void)data;
    if (!strcmp(iface, wl_compositor_interface.name))
        compositor = wl_registry_bind(reg, name, &wl_compositor_interface, 4);
    else if (!strcmp(iface, wl_shm_interface.name))
        shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
    else if (!strcmp(iface, zwlr_layer_shell_v1_interface.name))
        layer_shell = wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, 1);
    else if (!strcmp(iface, org_kde_plasma_window_management_interface.name) && version >= 12)
        wm = wl_registry_bind(reg, name, &org_kde_plasma_window_management_interface, 12);
}
static void global_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data; (void)reg; (void)name;
}
static const struct wl_registry_listener registry_listener = { global_add, global_remove };

/* ---------- invisible anchor surface ---------- */

static void layer_configure(void *data, struct zwlr_layer_surface_v1 *ls, uint32_t serial,
                            uint32_t w, uint32_t h) {
    (void)data; (void)w; (void)h;
    zwlr_layer_surface_v1_ack_configure(ls, serial);
    configured = 1;
}
static void layer_closed(void *data, struct zwlr_layer_surface_v1 *ls) {
    (void)data; (void)ls;
    fprintf(stderr, "iconhelper: anchor surface closed\n");
    exit(1);
}
static const struct zwlr_layer_surface_v1_listener layer_listener = { layer_configure, layer_closed };

static struct wl_buffer *transparent_pixel(void) {
    int fd = memfd_create("iconhelper", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, 4) < 0) { perror("memfd"); exit(1); }
    uint32_t *px = mmap(NULL, 4, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (px == MAP_FAILED) { perror("mmap"); exit(1); }
    *px = 0x00000000;   /* fully transparent ARGB */
    munmap(px, 4);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, 4);
    struct wl_buffer *buf = wl_shm_pool_create_buffer(pool, 0, 1, 1, 4, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    return buf;
}

static void make_anchor(struct wl_display *dpy) {
    anchor = wl_compositor_create_surface(compositor);
    struct zwlr_layer_surface_v1 *ls = zwlr_layer_shell_v1_get_layer_surface(
        layer_shell, anchor, NULL, ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND, "taskbar-icon-anchor");
    zwlr_layer_surface_v1_set_anchor(ls, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT);
    zwlr_layer_surface_v1_set_size(ls, 1, 1);
    zwlr_layer_surface_v1_set_exclusive_zone(ls, -1);   /* sit at the true corner, ignoring panels */
    zwlr_layer_surface_v1_add_listener(ls, &layer_listener, NULL);

    struct wl_region *empty = wl_compositor_create_region(compositor);
    wl_surface_set_input_region(anchor, empty);          /* never takes clicks */
    wl_region_destroy(empty);

    wl_surface_commit(anchor);
    while (!configured && wl_display_dispatch(dpy) != -1) {}

    wl_surface_attach(anchor, transparent_pixel(), 0, 0);
    wl_surface_damage(anchor, 0, 0, 1, 1);
    wl_surface_commit(anchor);
}

/* ---------- windows ---------- */

static struct entry *find(const char *uuid, int create) {
    struct entry *free_slot = NULL;
    for (int i = 0; i < MAX_WINDOWS; i++) {
        if (entries[i].win && !strcmp(entries[i].uuid, uuid)) return &entries[i];
        if (!entries[i].win && !free_slot) free_slot = &entries[i];
    }
    if (!create || !free_slot) return NULL;
    snprintf(free_slot->uuid, sizeof free_slot->uuid, "%s", uuid);
    free_slot->win = org_kde_plasma_window_management_get_window_by_uuid(wm, uuid);
    return free_slot;
}

static void handle_line(char *line) {
    char uuid[64];
    int x, y, w, h;
    if (!strcmp(line, "end")) {
        for (int i = 0; i < MAX_WINDOWS; i++) {
            if (!entries[i].win) continue;
            if (!entries[i].seen) {   /* gone from the dock */
                org_kde_plasma_window_unset_minimized_geometry(entries[i].win, anchor);
                org_kde_plasma_window_destroy(entries[i].win);
                entries[i].win = NULL;
            }
            entries[i].seen = 0;
        }
        return;
    }
    if (sscanf(line, "%63s %d %d %d %d", uuid, &x, &y, &w, &h) != 5) return;
    if (x < 0 || y < 0 || w <= 0 || h <= 0) return;
    struct entry *e = find(uuid, 1);
    if (!e) return;
    e->seen = 1;
    org_kde_plasma_window_set_minimized_geometry(e->win, anchor, x, y, w, h);
}

int main(void) {
    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy) { fprintf(stderr, "iconhelper: no wayland display\n"); return 1; }
    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &registry_listener, NULL);
    wl_display_roundtrip(dpy);
    if (!compositor || !shm || !layer_shell || !wm) {
        fprintf(stderr, "iconhelper: compositor lacks a needed protocol (compositor=%d shm=%d layer_shell=%d window_management=%d)\n",
                !!compositor, !!shm, !!layer_shell, !!wm);
        return 1;
    }
    make_anchor(dpy);
    wl_display_roundtrip(dpy);

    char buf[8192];
    size_t len = 0;
    struct pollfd fds[2] = {
        { .fd = wl_display_get_fd(dpy), .events = POLLIN },
        { .fd = STDIN_FILENO, .events = POLLIN },
    };
    for (;;) {
        wl_display_dispatch_pending(dpy);
        wl_display_flush(dpy);
        if (poll(fds, 2, -1) < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (fds[0].revents & POLLIN) {
            if (wl_display_dispatch(dpy) == -1) break;
        }
        if (fds[0].revents & (POLLHUP | POLLERR)) break;
        if (fds[1].revents & (POLLIN | POLLHUP)) {
            ssize_t n = read(STDIN_FILENO, buf + len, sizeof buf - 1 - len);
            if (n <= 0) break;   /* taskbar went away */
            len += n;
            buf[len] = 0;
            char *start = buf, *nl;
            while ((nl = strchr(start, '\n'))) {
                *nl = 0;
                handle_line(start);
                start = nl + 1;
            }
            len = strlen(start);
            memmove(buf, start, len + 1);
            if (len == sizeof buf - 1) len = 0;   /* overlong garbage: drop it */
        }
    }
    return 0;
}
