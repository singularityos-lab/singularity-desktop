# Singularity Desktop Environment

A Wayland desktop environment built on GTK4 and the labwc compositor. It
provides the shell (panel, dock, overview, workspaces, notifications, settings,
spotlight, lock screen and greeter) and a first-party set of applications, all
sharing the [libsingularity](subprojects/libsingularity) toolkit.

## Requirements

- [Meson](https://mesonbuild.com/) >= 0.59
- [Vala](https://vala.dev/) compiler
- GTK4 >= 4.6 and gtk4-layer-shell
- libdecor (runtime, client-side window decorations for GTK and Qt apps)
- Qt 6 xdgdesktopportal platform theme plugin (runtime, so Qt apps follow the
  dark/light and accent settings via the XDG settings portal). Fedora:
  `qt6-qtbase-gui`; Arch: `qt6-base`; Debian/Ubuntu:
  `qt6-xdgdesktopportal-platformtheme`
- `appmenu-gtk-module` (runtime, optional) so third-party GTK apps publish their
  menu bar to the panel global menu. Debian/Ubuntu `appmenu-gtk3-module` (plus
  `appmenu-gtk2-module` for GTK 2), Arch `appmenu-gtk-module` (AUR); on Fedora it
  is only in COPR. First-party Singularity apps do not need it. Firefox exports
  its menu over X11 only, so its global menu shows only under XWayland
  (`MOZ_ENABLE_WAYLAND=0`), not native Wayland
- wayland-client and wayland-scanner
- libnm, upower-glib, libpulse, goa-1.0, polkit-gobject-1
- gnome-desktop-4, libsoup-3.0, json-glib-1.0, libpeas-2
- vte-2.91-gtk4, gtksourceview-5, poppler-glib
- dbusmenu-glib-0.4, atspi-2, tracker-sparql-3.0, gudev-1.0, libcrypt
- PAM (`libpam`, lock screen authentication)
- labwc (built as a subproject) and xdg-desktop-portal-singularity
- labwc statically builds its bundled wlroots (a system wlroots package is not
  required). Its DRM backend needs hwdata, libdisplay-info, libliftoff, gbm
  (Mesa), libdrm, libseat, and libudev; on Fedora hwdata's pkg-config file is in
  `hwdata-devel`

## Build & Install

```sh
meson setup build
meson compile -C build
meson install -C build
```

The project installs under the prefix passed to `meson setup --prefix` (the
distribution default is `/opt/local`; pass `--prefix=/usr` for a standard
layout). The session does not hardcode the prefix: binaries are resolved next
to the running executable and via `PATH`, and data is found through
`XDG_DATA_DIRS`.

## Configuration

Desktop preferences live in the `dev.sinty.desktop` GSettings schema (dark
mode, accent color, dock and workspace layout, developer mode, and more).

## Components

- Shell: `src/` (core managers, panel, dock, overview, sidebar/settings).
- Toolkit: `subprojects/libsingularity` (ships `libsingularity`, the GTK4 UI toolkit, and `libsingularity-system`, the headless system backends; see its README).
- Compositor: `subprojects/labwc`.
- Portals: `subprojects/xdg-desktop-portal-singularity`.
- Applications: the other `subprojects/singularity-*` repositories.

## License

GPL-3.0 - see [LICENSE](LICENSE).
