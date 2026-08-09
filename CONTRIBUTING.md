# Contributing to Singularity Desktop

Thanks for your interest in contributing! This guide gets you from zero to running
a development build as fast as possible.

---

## Quick Start

```bash
# 1. Clone with submodules
git clone --recurse-submodules https://github.com/singularityos-lab/singularity-desktop
cd singularity-desktop

# 2. Install dependencies (Fedora / Silverblue)
sudo dnf install -y \
  vala meson ninja-build \
  gtk4-devel libadwaita-devel \
  gtk4-layer-shell-devel \
  wayland-devel wayland-protocols-devel \
  vte291-gtk4-devel \
  gtksourceview5-devel \
  gstreamer1-devel gstreamer1-plugins-base-devel \
  gstreamer1-plugins-good pipewire-gstreamer \
  libpulse-devel \
  polkit-devel \
  json-glib-devel \
  libpeas2-devel \
  pipewire-devel

# 2b. ...or install dependencies (Debian / Ubuntu)
sudo apt install -y \
  build-essential gettext gobject-introspection gstreamer1.0-pipewire \
  gstreamer1.0-plugins-good hwdata libadwaita-1-dev libatspi2.0-dev \
  libcairo2-dev libcmocka-dev libcrypt-dev libdbusmenu-glib-dev libdisplay-info-dev \
  libdrm-dev libfontconfig-dev libgcrypt20-dev libgdk-pixbuf-2.0-dev \
  libgee-0.8-dev libgirepository-1.0-dev libglib2.0-bin libglib2.0-dev \
  libgoa-1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev \
  libgtk-4-dev libgtk4-layer-shell-dev libgtksourceview-5-dev libgudev-1.0-dev \
  libinput-dev libjson-glib-dev libliftoff-dev libnm-dev libpam0g-dev \
  libpango1.0-dev libpeas-2-dev libpipewire-0.3-dev libpixman-1-dev \
  libpng-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev libpoppler-glib-dev \
  libpulse-dev librsvg2-dev libseat-dev libsecret-1-dev libsodium-dev \
  libsoup-3.0-dev libsystemd-dev libtracker-sparql-3.0-dev libupower-glib-dev \
  libvte-2.91-gtk4-dev libwayland-dev libwebkitgtk-6.0-dev libxcb-composite0-dev \
  libxcb-dri3-dev libxcb-errors-dev libxcb-ewmh-dev libxcb-icccm4-dev \
  libxcb-present-dev libxcb-render0-dev libxcb-res0-dev libxcb-xfixes0-dev \
  libxcb1-dev libxkbcommon-dev libxml2-dev meson ninja-build pkg-config \
  sassc scdoc valac wayland-protocols xwayland

# 3. Build
meson setup build
ninja -C build

# 4. Deploy to your local user prefix
bash scripts/deploy-to-host.sh

# 5. Run (inside a labwc/Wayland session)
singularity-desktop
```

Optional runtime: install `appmenu-gtk-module` (Debian/Ubuntu
`appmenu-gtk3-module`, Arch AUR `appmenu-gtk-module`, Fedora via COPR) so
third-party GTK apps publish their menu bar to the panel global menu. First-party
apps do not need it. Firefox only exports its menu over X11, so its global menu
shows only under XWayland (`MOZ_ENABLE_WAYLAND=0`).

---

## Architecture support

Singularity builds and runs on both **x86_64** and **aarch64 (arm64)**. The aarch64
build needs no source changes and no architecture guards — the C Wayland bindings, the
Vala shell, `libsingularity`, the portal and the bundled labwc/wlroots all compile as-is.

Verified on the CIX Sky1 (CD8180) SoC in an `ubuntu:26.04` aarch64 container:

```
Host machine cpu family: aarch64
Host machine cpu: aarch64
C compiler: gcc 15.2.0
Vala compiler: valac 0.56.18
Meson: 1.10.1
```

---

## Building vetro (UI transpiler host tool)

`subprojects/singularity-calculator`, `singularity-calendar` and `singularity-demo`
transpile their `.vetro` UI files to `.ui` at build time via `find_program('vetro')`.
That lookup is mandatory, so if your distribution has no `vetro` package the build fails
at `meson setup`. Build it from source (needs Go 1.24+) and put it on `PATH` first:

```bash
git clone https://github.com/singularityos-lab/vetro
cd vetro && go build -o vetro .
install -Dm755 vetro ~/.local/bin/vetro   # ensure ~/.local/bin is on PATH
```

---

## Branching

| Branch | Purpose |
|--------|---------|
| `main` | Stable, always builds |
| `feat/<name>` | New features |
| `fix/<name>` | Bug fixes |
| `refactor/<name>` | Refactors (no behaviour change) |

Open a PR against `main`. Keep PRs focused - one feature or fix per PR.

---

## Code Style

Language: **Vala** (GTK4, no Adwaita dependency in core shell).

- 4-space indentation, no tabs
- Class names: `PascalCase`
- Methods/fields: `snake_case`
- Signals: `snake_case` (e.g. `monitors_changed`)
- Private fields: `_snake_case` (underscore prefix)
- Never use `var` when the type is not obvious from the right-hand side
- Prefer `GLib.Subprocess.newv()` over `sh -c` for subprocess spawning
- Never use `Gtk.MessageDialog` - use inline `Gtk.InfoBar` or a custom `SettingsPage`
- Timers (`Timeout.add`, `Idle.add`) must store their ID and cancel in `dispose()`
- Keep files focused: one primary class per `.vala` file, named after the class (e.g. `ScreenshotPortal` -> `screenshot.vala`). Redundant suffixes in the filename (like `_portal` or `_manager`) should be avoided.

### Widget Guidelines

- New reusable widgets go in `subprojects/libsingularity/src/widgets/`
- Shell-only widgets (need GtkLayerShell) go in `subprojects/libsingularity/src/shell/`
- App-specific widgets stay in the app's own directory
- Follow the `PreferencesGroup` / `SwitchRow` / `ActionRow` pattern for settings UI
- Settings pages must be **inline** (no modals). Use `SettingsView.open_subpage()` for detail pages

### Where system logic goes

Headless system backends (D-Bus, sysfs, hardware managers with no GTK) live in
`libsingularity-system` (`subprojects/libsingularity/src/system/`), not in the
shell. They expose GObject properties and signals; the shell and apps wire them
to the UI. A backend must not `using Gtk` or reference shell-only symbols
(`SystemMonitor`, `AppSystem`, the `wayland_*` C bindings); if it does, it stays
in the shell until that coupling is removed. `libsingularity-system` is built
only with `-Dsystem=true` (the default), so apps that need only the UI toolkit
build with `-Dlibsingularity:system=false` and avoid the heavy deps (libpulse,
upower, gudev).

---

## Architecture Overview

```
singularity-desktop/
├── src/
│   ├── core/           # Shell core: app_system, display_manager, shortcuts...
│   ├── components/
│   │   ├── dock/       # Dock (GTK Layer Shell)
│   │   ├── panel/      # Top panel
│   │   └── sidebar/    # Settings sidebar + pages
│   ├── apps/           # Bundled apps (edit, files, terminal, write...)
│   ├── wayland/        # C Wayland protocol bindings
│   └── portal/         # xdg-desktop-portal implementation
├── subprojects/
│   └── libsingularity/ # Shared libraries:
│       ├── src/ui/     #   libsingularity      (GTK4 UI toolkit)
│       └── src/system/ #   libsingularity-system (headless system backends)
└── docs/               # Architecture and feature plans
```

---

## Testing

There is no automated test suite yet (Vala/GTK4 UI testing is hard). Please:

1. **Build cleanly** - `ninja -C build` must produce zero errors and zero warnings
2. **Deploy and run** - `bash scripts/deploy-to-host.sh`, restart the shell
3. **Test your change** manually - cover the happy path and obvious edge cases
4. **Check for timer leaks** - if you add a `Timeout.add`, make sure the ID is cancelled in `dispose()`

---

## Commit messages

Commits follow Conventional Commits:

```
<type>: <subject>
```

`<type>` is one of `feat`, `fix`, `chore`, `docs`, `build`, `ci`, `refactor`, `perf`, `style`, `test`, `revert`. Keep `<subject>` short, lowercase and in English. An optional scope is allowed: `<type>(<scope>): <subject>`.

When a commit closes an issue, use `<type>[closes #ID]: <issue title>`, for example:

```
fix[closes #2]: Discord doesn't open on Singularity desktop
```

Do not add co-author or attribution trailers.


## Reporting Bugs

Open a GitHub Issue with:
- OS and compositor version
- Steps to reproduce
- Expected vs actual behaviour
- `journalctl --user -u singularity-desktop -n 100` output

---

## Getting Help

- Open a Discussion on GitHub for questions
- Tag `@singularityos-lab/core` for review requests
