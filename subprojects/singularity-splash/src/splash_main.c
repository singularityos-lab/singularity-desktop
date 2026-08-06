#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <poll.h>
#include <ctype.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

#include "loginui.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-shell-client-protocol.h"

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct xdg_wm_base *wm_base;
static struct wl_seat *seat;
static struct wl_keyboard *keyboard;

static struct xkb_context *xkb_ctx;
static struct xkb_keymap *xkb_kmap;
static struct xkb_state *xkb_st;

struct g_output {
    struct wl_output *wl_output;
    uint32_t name;
    struct wl_surface *surface;
    struct zwlr_layer_surface_v1 *layer_surface;
    uint32_t width, height;
    bool configured;
    struct g_output *next;
};
static struct g_output *outputs;

static struct wl_surface *pv_surface;
static struct xdg_surface *pv_xsurf;
static struct xdg_toplevel *pv_top;
static int pv_w = 900, pv_h = 560;
static bool pv_configured = false;

static bool preview = false;
static bool running = true;

static cairo_surface_t *logo = NULL;

static double g_alpha = 1.0;

/* ── debug overlay (Ctrl+Shift+D) ─────────────────────────────────────────── */
static bool debug_overlay = false;
#define LOG_MAX  400
#define LOG_LINE 512
static char log_lines[LOG_MAX][LOG_LINE];
static int  log_count = 0;
static int  log_head = 0;
static int  kmsg_fd = -1;

static double mono_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void kmsg_open(void) {
    kmsg_fd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
}

static void kmsg_pump(void) {
    if (kmsg_fd < 0) return;
    char buf[2048];
    ssize_t n;
    while ((n = read(kmsg_fd, buf, sizeof buf - 1)) > 0) {
        buf[n] = '\0';
        /* kmsg record: "prio,seq,ts_usec,flag[,...];message" */
        char *msg = strchr(buf, ';');
        msg = msg ? msg + 1 : buf;
        char *nl = strchr(msg, '\n');
        if (nl) *nl = '\0';
        snprintf(log_lines[log_head], LOG_LINE, "%s", msg);
        log_head = (log_head + 1) % LOG_MAX;
        if (log_count < LOG_MAX) log_count++;
    }
}

/* ── assets ─────────────────────────────────────────────────────────────── */

static bool try_logo_file(const char *name) {
    if (!name || !name[0]) return false;
    const char *tpl[] = {
        "/opt/local/share/icons/hicolor/scalable/apps/%s.svg",
        "/usr/local/share/icons/hicolor/scalable/apps/%s.svg",
        "/usr/share/icons/hicolor/scalable/apps/%s.svg",
        "/usr/share/pixmaps/%s.svg",
        "/usr/share/pixmaps/%s.png",
        "/usr/share/icons/hicolor/256x256/apps/%s.png",
        NULL
    };
    for (int i = 0; tpl[i]; i++) {
        char p[1024];
        snprintf(p, sizeof p, tpl[i], name);
        if (access(p, R_OK) == 0) { logo = loginui_load_image(p, -1, 256); if (logo) return true; }
    }
    return false;
}

static void os_release_value(const char *key, char *out, size_t n) {
    out[0] = '\0';
    FILE *f = fopen("/etc/os-release", "r");
    if (!f) return;
    char line[512];
    size_t klen = strlen(key);
    while (fgets(line, sizeof line, f)) {
        if (strncmp(line, key, klen) != 0 || line[klen] != '=') continue;
        char *v = line + klen + 1;
        while (*v == '"' || *v == '\'') v++;
        char *end = v + strlen(v);
        while (end > v && (end[-1] == '\n' || end[-1] == '"' || end[-1] == '\'' || isspace((unsigned char)end[-1]))) end--;
        *end = '\0';
        snprintf(out, n, "%s", v);
        break;
    }
    fclose(f);
}

static void load_logo(void) {
    char logo_name[128], id[128];
    os_release_value("LOGO", logo_name, sizeof logo_name);
    os_release_value("ID", id, sizeof id);
    if (try_logo_file(logo_name)) return;
    if (try_logo_file(id)) return;
    try_logo_file("emblem-singularity");
}

/* ── render ─────────────────────────────────────────────────────────────── */

static void draw_debug_overlay(cairo_t *cr, int w, int h) {
    cairo_save(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    cairo_set_source_rgba(cr, 0.02, 0.02, 0.03, 0.86);
    cairo_rectangle(cr, 0, 0, w, h);
    cairo_fill(cr);

    loginui_text(cr, "Monospace Bold 11",
                 "debug • /dev/kmsg • Ctrl+Shift+D to hide",
                 20, 24, 0, 0.55, 0.95, 0.6);

    const int line_h = 15;
    int rows = (h - 52) / line_h;
    if (rows < 1) rows = 1;
    int show = log_count < rows ? log_count : rows;
    double y = 46;
    for (int i = 0; i < show; i++) {
        int k = log_count - show + i;                     /* oldest-of-window .. newest */
        int idx = (log_head - log_count + k) % LOG_MAX;
        if (idx < 0) idx += LOG_MAX;
        loginui_text(cr, "Monospace 9", log_lines[idx], 20, y, 0, 0.85, 0.86, 0.9);
        y += line_h;
    }
    cairo_restore(cr);
}

static void render_surface(struct wl_surface *surface, int w, int h) {
    cairo_t *cr;
    struct loginui_buffer *b = loginui_create_buffer(shm, w, h, &cr);
    if (!b) return;

    cairo_push_group(cr);
    loginui_render_splash(cr, w, h, NULL, logo, mono_seconds());
    cairo_pop_group_to_source(cr);
    cairo_save(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
    cairo_paint_with_alpha(cr, g_alpha);
    cairo_restore(cr);

    if (debug_overlay) draw_debug_overlay(cr, w, h);

    cairo_destroy(cr);
    wl_surface_attach(surface, b->wl_buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, w, h);
    wl_surface_commit(surface);
}

static void render_all(void) {
    if (preview) {
        if (pv_configured) render_surface(pv_surface, pv_w, pv_h);
        return;
    }
    for (struct g_output *o = outputs; o; o = o->next)
        if (o->configured) render_surface(o->surface, (int)o->width, (int)o->height);
}

/* ── keyboard (debug chord) ─────────────────────────────────────────────── */

static void kb_keymap(void *d, struct wl_keyboard *k, uint32_t fmt, int32_t fd, uint32_t size) {
    (void)d; (void)k;
    if (fmt != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 || !xkb_ctx) { close(fd); return; }
    char *map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (map == MAP_FAILED) return;
    struct xkb_keymap *km = xkb_keymap_new_from_string(
        xkb_ctx, map, XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS);
    munmap(map, size);
    if (!km) return;
    if (xkb_st) xkb_state_unref(xkb_st);
    if (xkb_kmap) xkb_keymap_unref(xkb_kmap);
    xkb_kmap = km;
    xkb_st = xkb_state_new(km);
}
static void kb_enter(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *sf, struct wl_array *a) {
    (void)d; (void)k; (void)s; (void)sf; (void)a;
}
static void kb_leave(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *sf) {
    (void)d; (void)k; (void)s; (void)sf;
}
static void kb_key(void *d, struct wl_keyboard *k, uint32_t serial, uint32_t time,
                   uint32_t key, uint32_t state) {
    (void)d; (void)k; (void)serial; (void)time;
    if (state != WL_KEYBOARD_KEY_STATE_PRESSED || !xkb_st) return;
    xkb_keysym_t sym = xkb_state_key_get_one_sym(xkb_st, key + 8);
    bool ctrl  = xkb_state_mod_name_is_active(xkb_st, XKB_MOD_NAME_CTRL,  XKB_STATE_MODS_EFFECTIVE) > 0;
    bool shift = xkb_state_mod_name_is_active(xkb_st, XKB_MOD_NAME_SHIFT, XKB_STATE_MODS_EFFECTIVE) > 0;
    if (ctrl && shift && (sym == XKB_KEY_d || sym == XKB_KEY_D))
        debug_overlay = !debug_overlay;
}
static void kb_mods(void *d, struct wl_keyboard *k, uint32_t serial,
                    uint32_t dep, uint32_t latched, uint32_t locked, uint32_t group) {
    (void)d; (void)k; (void)serial;
    if (xkb_st) xkb_state_update_mask(xkb_st, dep, latched, locked, 0, 0, group);
}
static void kb_repeat(void *d, struct wl_keyboard *k, int32_t rate, int32_t delay) {
    (void)d; (void)k; (void)rate; (void)delay;
}
static const struct wl_keyboard_listener kb_listener = {
    .keymap = kb_keymap, .enter = kb_enter, .leave = kb_leave,
    .key = kb_key, .modifiers = kb_mods, .repeat_info = kb_repeat,
};

static void seat_caps(void *d, struct wl_seat *s, uint32_t caps) {
    (void)d;
    if ((caps & WL_SEAT_CAPABILITY_KEYBOARD) && !keyboard) {
        keyboard = wl_seat_get_keyboard(s);
        wl_keyboard_add_listener(keyboard, &kb_listener, NULL);
    }
}
static void seat_name(void *d, struct wl_seat *s, const char *n) { (void)d; (void)s; (void)n; }
static const struct wl_seat_listener seat_listener = { .capabilities = seat_caps, .name = seat_name };

/* ── layer surface ──────────────────────────────────────────────────────── */

static void layer_configure(void *data, struct zwlr_layer_surface_v1 *ls,
                            uint32_t serial, uint32_t w, uint32_t h) {
    struct g_output *o = data;
    o->width = w; o->height = h; o->configured = true;
    zwlr_layer_surface_v1_ack_configure(ls, serial);
    render_surface(o->surface, (int)w, (int)h);
}
static void layer_closed(void *data, struct zwlr_layer_surface_v1 *ls) { (void)data; (void)ls; running = false; }
static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_configure, .closed = layer_closed,
};

static void create_layer_surface(struct g_output *o) {
    if (o->layer_surface || !layer_shell) return;
    o->surface = wl_compositor_create_surface(compositor);
    o->layer_surface = zwlr_layer_shell_v1_get_layer_surface(
        layer_shell, o->surface, o->wl_output, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "splash");
    zwlr_layer_surface_v1_set_anchor(o->layer_surface,
        ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_exclusive_zone(o->layer_surface, -1);
    /* take keyboard focus so the debug chord reaches us while the splash owns the screen */
    zwlr_layer_surface_v1_set_keyboard_interactivity(o->layer_surface, 1);
    zwlr_layer_surface_v1_add_listener(o->layer_surface, &layer_surface_listener, o);
    wl_surface_commit(o->surface);
}

/* ── preview window ─────────────────────────────────────────────────────── */

static void xdg_surface_configure(void *data, struct xdg_surface *xs, uint32_t serial) {
    (void)data;
    xdg_surface_ack_configure(xs, serial);
    pv_configured = true;
    render_surface(pv_surface, pv_w, pv_h);
}
static const struct xdg_surface_listener xdg_surface_listener = { .configure = xdg_surface_configure };

static void xdg_top_configure(void *data, struct xdg_toplevel *t, int32_t w, int32_t h, struct wl_array *states) {
    (void)data; (void)t; (void)states;
    if (w > 0) pv_w = w;
    if (h > 0) pv_h = h;
}
static void xdg_top_close(void *data, struct xdg_toplevel *t) { (void)data; (void)t; running = false; }
static const struct xdg_toplevel_listener xdg_toplevel_listener = {
    .configure = xdg_top_configure, .close = xdg_top_close,
};

static void wm_base_ping(void *d, struct xdg_wm_base *b, uint32_t serial) { (void)d; xdg_wm_base_pong(b, serial); }
static const struct xdg_wm_base_listener wm_base_listener = { .ping = wm_base_ping };

static void create_preview_window(void) {
    pv_surface = wl_compositor_create_surface(compositor);
    pv_xsurf = xdg_wm_base_get_xdg_surface(wm_base, pv_surface);
    xdg_surface_add_listener(pv_xsurf, &xdg_surface_listener, NULL);
    pv_top = xdg_surface_get_toplevel(pv_xsurf);
    xdg_toplevel_add_listener(pv_top, &xdg_toplevel_listener, NULL);
    xdg_toplevel_set_title(pv_top, "Singularity Splash (preview)");
    wl_surface_commit(pv_surface);
}

/* ── registry ───────────────────────────────────────────────────────────── */

static void reg_global(void *data, struct wl_registry *reg, uint32_t name,
                       const char *iface, uint32_t version) {
    (void)data;
    if (strcmp(iface, wl_compositor_interface.name) == 0) {
        compositor = wl_registry_bind(reg, name, &wl_compositor_interface, 4);
    } else if (strcmp(iface, wl_shm_interface.name) == 0) {
        shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
    } else if (strcmp(iface, zwlr_layer_shell_v1_interface.name) == 0) {
        layer_shell = wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, version < 4 ? version : 4);
    } else if (strcmp(iface, xdg_wm_base_interface.name) == 0) {
        wm_base = wl_registry_bind(reg, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);
    } else if (strcmp(iface, wl_seat_interface.name) == 0) {
        seat = wl_registry_bind(reg, name, &wl_seat_interface, version < 5 ? version : 5);
        wl_seat_add_listener(seat, &seat_listener, NULL);
    } else if (strcmp(iface, wl_output_interface.name) == 0) {
        struct g_output *o = calloc(1, sizeof(*o));
        o->name = name;
        o->wl_output = wl_registry_bind(reg, name, &wl_output_interface, version < 3 ? version : 3);
        o->next = outputs;
        outputs = o;
        if (!preview && layer_shell) create_layer_surface(o);
    }
}
static void reg_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data; (void)reg;
    struct g_output **pp = &outputs;
    while (*pp) {
        if ((*pp)->name == name) {
            struct g_output *dead = *pp;
            *pp = dead->next;
            if (dead->layer_surface) zwlr_layer_surface_v1_destroy(dead->layer_surface);
            if (dead->surface) wl_surface_destroy(dead->surface);
            if (dead->wl_output) wl_output_destroy(dead->wl_output);
            free(dead);
            return;
        }
        pp = &(*pp)->next;
    }
}
static const struct wl_registry_listener registry_listener = { reg_global, reg_remove };

/* ── main ───────────────────────────────────────────────────────────────── */

static bool ready_flag_present(const char *path) {
    return path && access(path, F_OK) == 0;
}

int main(int argc, char **argv) {
    const double TIMEOUT_S = 30.0;
    const double FADE_S = 0.25;

    for (int i = 1; i < argc; i++)
        if (strcmp(argv[i], "--preview") == 0) preview = true;
    if (getenv("SINGULARITY_SPLASH_PREVIEW")) preview = true;

    load_logo();
    xkb_ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    kmsg_open();

    char ready_path[512] = "";
    const char *rt = getenv("XDG_RUNTIME_DIR");
    if (rt && rt[0]) snprintf(ready_path, sizeof ready_path, "%s/singularity-shell-ready", rt);

    display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "splash: cannot connect to Wayland display\n"); return 1; }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (!compositor || !shm || (!preview && !layer_shell) || (preview && !wm_base)) {
        fprintf(stderr, "splash: compositor missing required globals\n");
        return 1;
    }

    if (preview) create_preview_window();
    else for (struct g_output *o = outputs; o; o = o->next) create_layer_surface(o);
    wl_display_roundtrip(display);

    int wfd = wl_display_get_fd(display);
    double start_t = mono_seconds();
    bool fading = false;
    double fade_t0 = 0.0;

    while (running) {
        while (wl_display_prepare_read(display) != 0)
            wl_display_dispatch_pending(display);
        wl_display_flush(display);

        struct pollfd pfd = { wfd, POLLIN, 0 };
        int pr = poll(&pfd, 1, 33);
        if (pr > 0 && (pfd.revents & POLLIN)) wl_display_read_events(display);
        else wl_display_cancel_read(display);
        wl_display_dispatch_pending(display);

        kmsg_pump();

        double t = mono_seconds();
        if (!preview) {
            if (!fading && !debug_overlay &&
                (ready_flag_present(ready_path) || (t - start_t) > TIMEOUT_S)) {
                fading = true; fade_t0 = t;
            }
            if (fading) {
                double f = (t - fade_t0) / FADE_S;
                g_alpha = 1.0 - f;
                if (g_alpha <= 0.0) { g_alpha = 0.0; running = false; }
            }
        }

        render_all();
    }

    wl_display_roundtrip(display);
    return 0;
}
