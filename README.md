# Singularity Desktop Environment

A Wayland desktop environment built on GTK4 and the labwc compositor. It
provides the shell (panel, dock, overview, workspaces, notifications, settings,
spotlight, lock screen and greeter) and a first-party set of applications, all
sharing the [libsingularity](subprojects/libsingularity) toolkit.

## Requirements

`make prepare-deps` detects the distribution (Debian/Ubuntu, Fedora, openSUSE, Arch)
and installs every build and runtime dependency listed below with the system
package manager; `bash scripts/prepare-deps.sh --dry-run` prints the command
instead of running it.

`make install-app <app>` rebuilds and deploys a single app (for example `make install-app messages`), together with libsingularity, without rebuilding the rest of the desktop.

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
- libnm, upower-glib, libpulse, polkit-gobject-1, libsecret-1
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

For development, `make install` builds everything and deploys it to
`/opt/local` on the host.
`bash scripts/deploy-to-host.sh --dry-run` lists every installed file and
where it goes; `bash scripts/deploy-to-host.sh --root DIR` runs a full deploy
as a normal user into a scratch directory without touching the system.

### Build options

Meson options, passed to `meson setup` or `meson configure` as `-D<name>=<value>`:

| Option | Values | Default | Effect |
| --- | --- | --- | --- |
| `apps` | `all`, `core`, `essential` | `all` | Which bundled apps are built and installed |
| `gestures` | `enabled`, `disabled`, `auto` | `auto` | Hand and gaze gesture controls |
| `installer` | `true`, `false` | `false` | Build the Sinty OS installer |
| `singularity-accounts:oauth_clients_file` | path | `/etc/singularity/oauth-clients.json` | OAuth client file read when the build is configured and built into the online accounts service; a missing file builds with no clients |

The Google and Microsoft OAuth clients for online accounts come from the file named by `oauth_clients_file`, in the JSON format described in [the online accounts documentation](subprojects/libsingularity/docs/online-accounts.md). Put your registered clients there before configuring; changing the file makes the next build reconfigure. Without it, Google and Microsoft browser sign-in stays off unless a client file is installed.

Each bundled app belongs to one tier, listed in [`apps.txt`](apps.txt):

- `essential`: the apps the desktop needs to be usable (Files, Edit, Leafs,
  Store, System Monitor, Disks, Help)
- `core`: the standard desktop apps (Calculator, Clock, Photos, Music,
  Calendar and the rest)
- `extra`: everything else (Write, Spreadsheet, Git, Radio, Podcasts, and more)

`apps=all` builds every tier, `apps=core` skips `extra`, and `apps=essential`
builds only `essential`. The shell, greeter, session and other system
components are always built.

`make` variables, passed as `make install NAME=value`:

| Variable | Effect |
| --- | --- |
| `SKIP_EXTRA=1` | Skip the `extra` apps (same as `APPS=core`) |
| `SKIP_NONESSENTIAL=1` | Install only the `essential` apps (same as `APPS=essential`) |
| `APPS=all\|core\|essential` | Set the `apps` option directly |
| `GESTURES=enabled\|disabled` | Set the `gestures` option; `disabled` also skips downloading the gesture runtime. Default `enabled` |
| `DEPLOY_PREFIX=DIR` | Deploy prefix, default `/opt/local`. The build is configured with it (`libdir=lib`), so the paths compiled into the binaries match the deployed files |

When an install uses a narrower tier than the previous one, the skipped apps
and their launchers are removed from `/opt/local`.

## Fingerprint reader drivers

`make install` also builds [libfprint-TOD](https://gitlab.freedesktop.org/3v1n0/libfprint/-/tree/tod)
(libfprint with every open driver plus a plugin interface for manufacturer
drivers) and a matching libgusb, and installs them to `/opt/local/lib/fprint`.
This needs the libusb-1.0 and json-glib development files. A drop-in at
`/etc/systemd/system/fprintd.service.d/singularity-fprint.conf` makes the
system fprintd load this libfprint; nothing under `/usr` is replaced.

libfprint-TOD loads plugins from two directories:

| Directory | Owner |
| --- | --- |
| `/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1` | Plugins shipped by the distribution |
| `/var/lib/singularity/fprint/tod-1` | Plugins installed from Settings |

Some manufacturer plugins look for their support library at a fixed path under
`/usr/lib`. Those libraries are kept in
`/var/lib/singularity/fprint/singularity-fprint-drivers`, which fprintd sees as
a system extension overlaid on `/usr` (`ExtensionDirectories=`), so read-only
systems keep working.

When a reader needs a manufacturer driver that Singularity knows about,
Settings > Users offers to install it. The driver is proprietary and is never
shipped with Singularity: the `sinty-desktopd` service downloads it from the
manufacturer's or distribution's own URL, checks it against a pinned SHA-256,
and only extracts the listed files. It accepts only the device IDs in its
built-in catalog.

To remove the integration and go back to the system libfprint:

```sh
run0 bash scripts/install-fprint.sh --uninstall
```

`--dry-run` shows what an install or uninstall would change.

## Configuration

Desktop preferences live in the `dev.sinty.desktop` GSettings schema (dark
mode, accent color, dock and workspace layout, developer mode, and more).

## Components

- Shell: `src/` (core managers, panel, dock, overview, sidebar/settings).
- Toolkit: `subprojects/libsingularity` (ships `libsingularity`, the GTK4 UI toolkit, and `libsingularity-system`, the headless system backends; see its README).
- Compositor: `subprojects/labwc`.
- Gesture control: `subprojects/singularity-gestures` (hand and gaze tracking,
  calibration lab, and desktop controller).
- Portals: `subprojects/xdg-desktop-portal-singularity`.
- Applications: the other `subprojects/singularity-*` repositories.

## Use of Generative AI
Some maintainers might use generative AI tools as assistants while working in Singularity Desktop, in the spirit of Open Source, I want to be transparent about how, specifically:

- Code comments and documentation
- Boilerplate and repetitive code
- Issue triage (spotting duplicates, outdated reports, grouping similar issues)

Tools vary between contributors (currently mostly Claude and Codex): each AI-assisted commit states the tool and model used in its `Assisted-by` trailer.

### What we don't use it for
Architecture, complex logic, the security and sandboxing model and user experience are designed and written by the maintainers, manually.

### Human review
Every line of generated code, documentation and comments are reviewed by a maintainer before it is merged.

Also, starting from the 10th Sep 2026, the following commit pattern must be used for contributions made with or helped with the AI:

```plain
feat: add support for X

Assisted-by: <tool>:<model-version>
AI-Scope: what the AI generated in this commit, and the prompt used (or a short summary of it)
```

Trivial completions (single lines, renames, formatting) don't need to be marked.

Not following this layout will lead to a closed Pull Request.

Coding agents must also follow [AGENTS.md](AGENTS.md) before changing files,
creating commits, or opening pull requests.

## License

GPL-3.0 - see [LICENSE](LICENSE).
