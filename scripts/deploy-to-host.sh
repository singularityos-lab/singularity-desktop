#!/bin/bash
# Deploy Singularity Desktop to /opt/local. Run via: make install

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$EUID" -ne 0 ]; then
    if [ -n "$container" ]; then
        exec host-spawn run0 \
            --setenv=ORIG_HOME="$HOME" \
            --setenv=ORIG_USER="$USER" \
            --setenv=container=host-spawned \
            bash "$0" "$@"
    else
        exec run0 \
            --setenv=ORIG_HOME="$HOME" \
            --setenv=ORIG_USER="$USER" \
            bash "$0" "$@"
    fi
fi

REAL_USER="${ORIG_USER:-${SUDO_USER:-$USER}}"
REAL_HOME="${ORIG_HOME:-$(getent passwd "$REAL_USER" | cut -d: -f6)}"
if [ -z "$REAL_HOME" ] || [ "$REAL_HOME" = "/" ]; then
    echo "ERROR: cannot determine the calling user's HOME (REAL_USER='$REAL_USER')" >&2
    exit 1
fi

REAL_UID="$(id -u "$REAL_USER" 2>/dev/null || echo "")"
REAL_XDG_RUNTIME_DIR="${REAL_UID:+/run/user/$REAL_UID}"

run_as_user() {
    local env_prefix=(env
        HOME="$REAL_HOME"
        XDG_RUNTIME_DIR="$REAL_XDG_RUNTIME_DIR"
        DBUS_SESSION_BUS_ADDRESS="unix:path=$REAL_XDG_RUNTIME_DIR/bus")
    if command -v runuser >/dev/null; then
        runuser -u "$REAL_USER" -- "${env_prefix[@]}" "$@"
    else
        sudo -u "$REAL_USER" "${env_prefix[@]}" "$@"
    fi
}

PREFIX="/opt/local"
OPT_BIN="$PREFIX/bin"
OPT_LIB="$PREFIX/lib"
OPT_SHARE="$PREFIX/share"
OPT_APPS="$OPT_SHARE/applications"
OPT_ICONS="$OPT_SHARE/icons"
OPT_THEMES="$OPT_SHARE/themes"
OPT_SCHEMAS="$OPT_SHARE/glib-2.0/schemas"
OPT_GIR="$OPT_SHARE/gir-1.0"
OPT_TYPELIB="$OPT_LIB/girepository-1.0"
OPT_SING="$OPT_SHARE/singularity"
OPT_PLUGINS="$OPT_SING/plugins"
OPT_WIDGETS_LIB="$OPT_LIB/singularity/widgets"
OPT_WIDGETS_SHARE="$OPT_SING/widgets"
OPT_APP_SETTINGS="$OPT_SING/app-settings"
OPT_PORTAL="$OPT_SHARE/xdg-desktop-portal/portals"
OPT_DBUS="$OPT_SHARE/dbus-1/services"
OPT_BACKGROUNDS="$OPT_SHARE/backgrounds/singularity"
BUILD="$PROJECT_DIR/build"

mkdir -p "$OPT_BIN" "$OPT_LIB" "$OPT_APPS" "$OPT_ICONS" "$OPT_THEMES" \
         "$OPT_SCHEMAS" "$OPT_GIR" "$OPT_TYPELIB" "$OPT_SING" "$OPT_PLUGINS" \
         "$OPT_APP_SETTINGS" "$OPT_PORTAL" "$OPT_DBUS" "$OPT_BACKGROUNDS" \
         "$OPT_WIDGETS_LIB" "$OPT_WIDGETS_SHARE"

acopy() {
    local src="$1" dest="$2"
    cp "$src" "$dest.new"
    mv "$dest.new" "$dest"
}

echo "Deploying Singularity to $PREFIX ..."

echo "Installing binaries..."
for bin in singularity-desktop \
           singularity-region-picker singularity-screenshot \
           singularity-polkit-agent singularity-greeter singularity-splash \
           xdg-desktop-portal-singularity singularity-screencast-chooser; do
    bin_path=$(find "$BUILD" -name "$bin" -executable -type f | head -n 1)
    if [ -n "$bin_path" ]; then
        acopy "$bin_path" "$OPT_BIN/$bin"
        echo "  $bin"
    fi
done

lockscreen_path=$(find "$BUILD" -name singularity-lockscreen -executable -type f | grep -v '\.p/' | head -n 1)
[ -n "$lockscreen_path" ] && \
    acopy "$lockscreen_path" "$OPT_BIN/singularity-lockscreen" && \
    echo "  singularity-lockscreen"

if [ -f "$BUILD/subprojects/singularity-polkit-agent/singularity-polkit-auth-helper" ]; then
    acopy "$BUILD/subprojects/singularity-polkit-agent/singularity-polkit-auth-helper" \
          "$OPT_BIN/singularity-polkit-auth-helper"
    echo "  singularity-polkit-auth-helper"
fi

APP_LIST="singularity-browser singularity-files singularity-edit singularity-calculator \
          singularity-photos singularity-store singularity-monitor singularity-write \
          singularity-videos singularity-leafs singularity-calendar singularity-music \
          singularity-dconf singularity-demo singularity-keyboard-reset \
          singularity-keyring singularity-git"

for app in $APP_LIST; do
    app_path=""
    for cand in "$BUILD/$app" \
                "$BUILD/subprojects/$app/$app" \
                "$BUILD/apps/$app/$app"; do
        [ -f "$cand" ] && { app_path="$cand"; break; }
    done
    if [ -n "$app_path" ]; then
        acopy "$app_path" "$OPT_BIN/$app"
        echo "  $app"
    fi
done

LABWC_BIN=""
for p in "$PROJECT_DIR/subprojects/labwc/build/labwc" \
         "$PROJECT_DIR/subprojects/labwc/build-user/labwc" \
         "/opt/local/bin/labwc" \
         "/usr/local/bin/labwc" \
         "/usr/bin/labwc"; do
    if [ -x "$p" ]; then LABWC_BIN="$p"; break; fi
done
if [ -n "$LABWC_BIN" ] && [ "$LABWC_BIN" != "$OPT_BIN/labwc" ]; then
    acopy "$LABWC_BIN" "$OPT_BIN/labwc"
    echo "  labwc (from $LABWC_BIN)"
fi

echo "Installing shared libraries..."
acopy "$BUILD/subprojects/libsingularity/libsingularity.so.0.1.0" \
      "$OPT_LIB/libsingularity.so.0.1.0"
ln -sf libsingularity.so.0.1.0 "$OPT_LIB/libsingularity.so.0"
ln -sf libsingularity.so.0.1.0 "$OPT_LIB/libsingularity.so"

if [ -f "$BUILD/subprojects/libsingularity/libsingularity-system.so.0.1.0" ]; then
    acopy "$BUILD/subprojects/libsingularity/libsingularity-system.so.0.1.0" \
          "$OPT_LIB/libsingularity-system.so.0.1.0"
    ln -sf libsingularity-system.so.0.1.0 "$OPT_LIB/libsingularity-system.so.0"
    ln -sf libsingularity-system.so.0.1.0 "$OPT_LIB/libsingularity-system.so"
    echo "  libsingularity-system.so.0.1.0"
fi

if [ -d "$BUILD/extra-libs" ]; then
    for lib in "$BUILD/extra-libs/"*.so*; do
        [ -f "$lib" ] && acopy "$lib" "$OPT_LIB/$(basename "$lib")"
    done
fi

echo "Installing plugins..."
for plugin_dir in "$BUILD/subprojects/singularity-plugins"/*/; do
    plugin_name="$(basename "$plugin_dir")"
    dest="$OPT_PLUGINS/$plugin_name"
    mkdir -p "$dest"
    for f in "$plugin_dir"/*.so; do
        [ -f "$f" ] && acopy "$f" "$dest/$(basename "$f")"
    done
    for f in "$plugin_dir"/*.plugin; do
        [ -f "$f" ] && cp "$f" "$dest/"
    done
    echo "  $plugin_name"
done

echo "Installing overview widgets..."
while IFS= read -r w; do
    [ -f "$w" ] && acopy "$w" "$OPT_WIDGETS_LIB/$(basename "$w")" && echo "  $(basename "$w")"
done < <(find "$BUILD" -maxdepth 3 -name 'libsingularity-*widget*.so' -type f 2>/dev/null)
for m in "$PROJECT_DIR"/subprojects/*/widget/*.widget \
         "$PROJECT_DIR"/subprojects/singularity-widgets/*/*.widget; do
    [ -f "$m" ] && cp "$m" "$OPT_WIDGETS_SHARE/" && echo "  $(basename "$m")"
done

echo "Installing GSettings schemas..."
for schema in \
    "$PROJECT_DIR/data/dev.sinty.desktop.gschema.xml" \
    "$PROJECT_DIR"/subprojects/*/data/*.gschema.xml \
    "$PROJECT_DIR"/subprojects/singularity-shell/src/lockscreen/*.gschema.xml; do
    [ -f "$schema" ] && cp "$schema" "$OPT_SCHEMAS/"
done
glib-compile-schemas "$OPT_SCHEMAS"

echo "Installing AccountsService extension..."
if mkdir -p /usr/share/accountsservice/interfaces 2>/dev/null && \
   cp "$PROJECT_DIR/data/accountsservice/com.singularity.Desktop.xml" \
      /usr/share/accountsservice/interfaces/ 2>/dev/null; then
    echo "  com.singularity.Desktop.xml"
else
    echo "  skipped (/usr is read-only; ship the extension via the OS image)"
fi

echo "Installing CSS..."
for css in style.css style.dark.css style.light.css; do
    [ -f "$PROJECT_DIR/subprojects/libsingularity/src/style/$css" ] && \
        cp "$PROJECT_DIR/subprojects/libsingularity/src/style/$css" "$OPT_SING/"
done

if [ -d "$PROJECT_DIR/subprojects/libsingularity/data/avatars" ]; then
    mkdir -p "$OPT_SING/avatars"
    cp -r "$PROJECT_DIR/subprojects/libsingularity/data/avatars/." "$OPT_SING/avatars/"
    echo "  avatars"
fi

INTER_VER="4.1"
INTER_DST="$REAL_HOME/.local/share/fonts/inter"
if [ ! -f "$INTER_DST/Inter-Regular.ttf" ]; then
    echo "Installing Inter font..."
    INTER_TMP="$(mktemp -d)"
    if curl -sL --max-time 120 -o "$INTER_TMP/inter.zip" \
        "https://github.com/rsms/inter/releases/download/v${INTER_VER}/Inter-${INTER_VER}.zip" \
        && unzip -q -o "$INTER_TMP/inter.zip" "extras/ttf/Inter-*.ttf" "LICENSE.txt" -d "$INTER_TMP"; then
        mkdir -p "$INTER_DST"
        cp "$INTER_TMP"/extras/ttf/Inter-*.ttf "$INTER_DST/"
        cp "$INTER_TMP/LICENSE.txt" "$INTER_DST/LICENSE.txt"
        mkdir -p "$REAL_HOME/.config/fontconfig/conf.d"
        cat > "$REAL_HOME/.config/fontconfig/conf.d/60-inter.conf" <<'FCEOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Inter</family></prefer>
  </alias>
</fontconfig>
FCEOF
        chown -R "$REAL_USER:" "$REAL_HOME/.local/share/fonts" "$REAL_HOME/.config/fontconfig" 2>/dev/null || true
        run_as_user fc-cache -f >/dev/null 2>&1 || true
        echo "  Inter ${INTER_VER}"
    else
        echo "  WARNING: could not fetch Inter font (offline?); skipping"
    fi
    rm -rf "$INTER_TMP"
fi

echo "Installing GIR / typelibs..."
GIR_SRC="$(find "$BUILD" -maxdepth 4 \( -name 'Singularity-1.0.gir' -o -name 'LibSingularity-1.0.gir' \) | head -n 1)"
TYPELIB_SRC="$(find "$BUILD" -maxdepth 4 \( -name 'Singularity-1.0.typelib' -o -name 'LibSingularity-1.0.typelib' \) | head -n 1)"
[ -n "$GIR_SRC" ] && cp "$GIR_SRC" "$OPT_GIR/"
if [ -n "$TYPELIB_SRC" ]; then
    cp "$TYPELIB_SRC" "$OPT_TYPELIB/"
elif [ -n "$GIR_SRC" ] && command -v g-ir-compiler >/dev/null; then
    g-ir-compiler "$GIR_SRC" --output="$OPT_TYPELIB/$(basename "$GIR_SRC" .gir).typelib"
fi

echo "Installing .desktop files..."
[ -f "$PROJECT_DIR/subprojects/singularity-leafs/data/dev.sinty.leafs.desktop" ] || {
    echo "ERROR: subprojects/singularity-leafs is missing dev.sinty.leafs.desktop. Run: git submodule update --init --recursive" >&2
    exit 1
}
find "$PROJECT_DIR" -name "*.desktop" -type f | while read -r desktop; do
    [[ "$desktop" == *"test"* ]] && continue
    sed -E "s|^Exec=([a-z].*)$|Exec=$OPT_BIN/\1|" "$desktop" > "$OPT_APPS/$(basename "$desktop")"
done
update-desktop-database "$OPT_APPS" 2>/dev/null || true

echo "Installing icons..."
[ -d "$PROJECT_DIR/data/icons/hicolor" ] && cp -r "$PROJECT_DIR/data/icons/hicolor/." "$OPT_ICONS/hicolor/"
for app_icons in "$PROJECT_DIR/apps/"*/data/icons/hicolor "$PROJECT_DIR/subprojects/"*/data/icons/hicolor; do
    [ -d "$app_icons" ] && cp -r "$app_icons/." "$OPT_ICONS/hicolor/"
done
SCALABLE="$OPT_ICONS/hicolor/scalable/apps"
mkdir -p "$SCALABLE"
for icon_svg in "$PROJECT_DIR/apps/"*/data/icons/dev.sinty.*.svg "$PROJECT_DIR/subprojects/"*/data/icons/dev.sinty.*.svg; do
    [ -f "$icon_svg" ] && cp "$icon_svg" "$SCALABLE/"
done
if [ -d "$PROJECT_DIR/subprojects/singularity-themes/Singularity" ]; then
    cp -r "$PROJECT_DIR/subprojects/singularity-themes/Singularity" "$OPT_ICONS/"
fi
[ -f "$OPT_ICONS/hicolor/index.theme" ] || cp /usr/share/icons/hicolor/index.theme "$OPT_ICONS/hicolor/" 2>/dev/null || true
gtk-update-icon-cache -f "$OPT_ICONS/hicolor" 2>/dev/null || true
[ -d "$OPT_ICONS/Singularity" ] && gtk-update-icon-cache -f "$OPT_ICONS/Singularity" 2>/dev/null || true

echo "Installing themes..."
for theme_dir in "$PROJECT_DIR/subprojects/singularity-themes/themes"/*/; do
    [ "$(basename "$theme_dir")" = "SingularityExample" ] && continue
    [ -d "$theme_dir" ] && cp -r "$theme_dir" "$OPT_THEMES/" && echo "  $(basename "$theme_dir")"
done
# The full Singularity GTK theme for third-party apps is built from the Orchis
# widget skeleton recoloured with libsingularity tokens. The CSS is generated
# by sassc at build time (lives in the build dir); the widget assets and
# index.theme are static source. Assemble the complete theme tree here.
SING_GTK_THEME="$OPT_THEMES/Singularity"
SING_GTK_SRC="$PROJECT_DIR/subprojects/libsingularity/data/gtk-theme"
SING_GTK_BUILD="$BUILD/subprojects/libsingularity/data/gtk-theme/gtk"
if [ -f "$SING_GTK_BUILD/3.0/gtk.css" ]; then
    for ver in 3.0 4.0; do
        dir="$SING_GTK_THEME/gtk-$ver"
        mkdir -p "$dir/assets"
        cp "$SING_GTK_BUILD/$ver/gtk.css"      "$dir/gtk.css"
        cp "$SING_GTK_BUILD/$ver/gtk-dark.css" "$dir/gtk-dark.css"
        cp -r "$SING_GTK_SRC/gtk/assets/." "$dir/assets/"
        cp -r "$SING_GTK_SRC/gtk/scalable"  "$dir/assets/"
    done
    cp "$SING_GTK_SRC/index.theme" "$SING_GTK_THEME/index.theme"
    echo "  Singularity GTK theme"

    if command -v flatpak >/dev/null; then
        echo "Installing Flatpak GTK theme..."
        run_as_user "$PROJECT_DIR/scripts/install-flatpak-theme.sh" "$SING_GTK_THEME"
    fi
fi

echo "Installing wallpapers..."
WP_DIR="$PROJECT_DIR/subprojects/singularity-wallpapers"
for wp in "$WP_DIR/"*.svg "$WP_DIR/"*.png; do
    [ -f "$wp" ] && cp "$wp" "$OPT_BACKGROUNDS/"
done

echo "Installing app settings JSON..."
for j in "$PROJECT_DIR"/subprojects/*/data/*.json; do
    [ -f "$j" ] && cp "$j" "$OPT_APP_SETTINGS/"
done

echo "Installing portal files / D-Bus services..."
cat > "$OPT_PORTAL/singularity.portal" <<EOF
[portal]
DBusName=org.freedesktop.impl.portal.desktop.singularity
Interfaces=org.freedesktop.impl.portal.Screenshot;org.freedesktop.impl.portal.Settings;org.freedesktop.impl.portal.FileChooser;org.freedesktop.impl.portal.Notification;org.freedesktop.impl.portal.Inhibit;org.freedesktop.impl.portal.Access;org.freedesktop.impl.portal.Account;org.freedesktop.impl.portal.Email;org.freedesktop.impl.portal.Lockdown;org.freedesktop.impl.portal.Wallpaper;org.freedesktop.impl.portal.AppChooser;org.freedesktop.impl.portal.Print;org.freedesktop.impl.portal.DynamicLauncher;org.freedesktop.impl.portal.ScreenCast
UseIn=Singularity
EOF

SYS_DBUS=""
for d in /usr/share/dbus-1/services /usr/local/share/dbus-1/services; do
    if mkdir -p "$d" 2>/dev/null && [ -w "$d" ]; then
        SYS_DBUS="$d"
        break
    fi
done
if [ -z "$SYS_DBUS" ]; then
    SYS_DBUS="$OPT_DBUS"
    echo "  Note: no writable system dbus-1/services dir; using $SYS_DBUS"
    echo "  (the portal still starts in-session from its systemd user unit; only"
    echo "   D-Bus auto-activation outside the session would miss it here)"
else
    echo "  D-Bus activation services -> $SYS_DBUS"
fi

cat > "$SYS_DBUS/org.freedesktop.impl.portal.desktop.singularity.service" <<EOF
[D-BUS Service]
Name=org.freedesktop.impl.portal.desktop.singularity
Exec=$OPT_BIN/singularity-portal
SystemdService=xdg-desktop-portal-singularity.service
EOF

cat > "$SYS_DBUS/io.github.mirkobrombin.ush.Portal.service" <<EOF
[D-BUS Service]
Name=io.github.mirkobrombin.ush.Portal
Exec=$OPT_BIN/singularity-portal
SystemdService=xdg-desktop-portal-singularity.service
EOF

cat > "$OPT_BIN/singularity-portal" <<'SPORTAL'
#!/bin/bash
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
export GDK_BACKEND=wayland
export GSK_RENDERER=gl
export GTK_A11Y=none
export XDG_CURRENT_DESKTOP=Singularity
export LD_LIBRARY_PATH="/opt/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GSETTINGS_SCHEMA_DIR="/opt/local/share/glib-2.0/schemas${GSETTINGS_SCHEMA_DIR:+:$GSETTINGS_SCHEMA_DIR}"
export XDG_DATA_DIRS="/opt/local/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
# Preload gtk4-layer-shell before libwayland-client or layer-shell init fails here.
for ls in /usr/lib/x86_64-linux-gnu/libgtk4-layer-shell.so.0 \
          /usr/lib64/libgtk4-layer-shell.so.0 \
          /usr/lib/libgtk4-layer-shell.so.0; do
    if [ -e "$ls" ]; then
        export LD_PRELOAD="$ls${LD_PRELOAD:+:$LD_PRELOAD}"
        break
    fi
done
for c in /opt/local/bin /opt/bin /usr/local/bin /usr/bin; do
    if [ -x "$c/xdg-desktop-portal-singularity" ]; then
        exec "$c/xdg-desktop-portal-singularity"
    fi
done
exit 1
SPORTAL
chmod +x "$OPT_BIN/singularity-portal"

echo "Installing session scripts..."
SESSION_SRC="$PROJECT_DIR/subprojects/singularity-session"
for s in singularity-desktop-session singularity-labwc-session; do
    acopy "$SESSION_SRC/src/$s" "$OPT_BIN/$s"
    chmod +x "$OPT_BIN/$s"
    echo "  $s"
done

echo "Registering the desktop session..."
SESSION_ENTRY="[Desktop Entry]
Name=Singularity
Comment=Singularity Desktop Environment
Exec=$OPT_BIN/singularity-labwc-session
TryExec=$OPT_BIN/singularity-desktop
Type=Application
DesktopNames=Singularity"
if mkdir -p /usr/share/wayland-sessions 2>/dev/null && \
   printf '%s\n' "$SESSION_ENTRY" > /usr/share/wayland-sessions/singularity.desktop 2>/dev/null; then
    echo "  /usr/share/wayland-sessions/singularity.desktop"
else
    mkdir -p "$OPT_SHARE/wayland-sessions"
    printf '%s\n' "$SESSION_ENTRY" > "$OPT_SHARE/wayland-sessions/singularity.desktop"
    echo "  $OPT_SHARE/wayland-sessions/singularity.desktop (/usr is read-only)"
    if mkdir -p /etc/systemd/system/gdm.service.d 2>/dev/null; then
        printf '%s\n' "[Service]" \
            "Environment=\"XDG_DATA_DIRS=/var/lib/flatpak/exports/share:$OPT_SHARE:/usr/local/share:/usr/share\"" \
            > /etc/systemd/system/gdm.service.d/singularity-session.conf
        echo "  GDM XDG_DATA_DIRS override"
        command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload 2>/dev/null || true
    fi
fi

echo "Installing per-user config for $REAL_USER..."

run_as_user mkdir -p "$REAL_HOME/.config/labwc"
install -o "$REAL_USER" -g "$REAL_USER" -m 0644 \
    "$SESSION_SRC/config/labwc/themerc" "$REAL_HOME/.config/labwc/themerc"

PORTALS_CONF_DIR="$REAL_HOME/.config/xdg-desktop-portal"
run_as_user mkdir -p "$PORTALS_CONF_DIR"
cat > "$PORTALS_CONF_DIR/singularity-portals.conf" <<EOF
[preferred]
default=singularity;gtk
org.freedesktop.impl.portal.Screenshot=singularity
org.freedesktop.impl.portal.Settings=singularity
org.freedesktop.impl.portal.FileChooser=singularity
org.freedesktop.impl.portal.AppChooser=singularity
org.freedesktop.impl.portal.OpenURI=singularity
org.freedesktop.impl.portal.ScreenCast=singularity
EOF
chown "$REAL_USER:$REAL_USER" "$PORTALS_CONF_DIR/singularity-portals.conf"

ETC_USER_DIR="/etc/systemd/user"
mkdir -p "$ETC_USER_DIR"

run_as_user systemctl --user stop singularity-polkit-agent.service 2>/dev/null || true
run_as_user systemctl --user disable singularity-polkit-agent.service 2>/dev/null || true
rm -f "$REAL_HOME/.config/systemd/user/singularity-polkit-agent.service"
rm -f "$REAL_HOME/.config/systemd/user/singularity-keyring.service" \
      "$REAL_HOME/.config/systemd/user/xdg-desktop-portal-singularity.service"

cat > "$ETC_USER_DIR/singularity-keyring.service" <<EOF
[Unit]
Description=Singularity Keyring (Secret Service)
Documentation=https://specifications.freedesktop.org/secret-service/
PartOf=graphical-session.target

[Service]
Type=dbus
BusName=org.freedesktop.secrets
ExecStart=$OPT_BIN/singularity-keyring
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF

cat > "$ETC_USER_DIR/xdg-desktop-portal-singularity.service" <<EOF
[Unit]
Description=Singularity XDG Desktop Portal
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=dbus
BusName=org.freedesktop.impl.portal.desktop.singularity
Environment=WAYLAND_DISPLAY=wayland-0
Environment=GDK_BACKEND=wayland
Environment=GSK_RENDERER=gl
Environment=GTK_A11Y=none
Environment=XDG_CURRENT_DESKTOP=Singularity
Environment=LD_LIBRARY_PATH=/opt/local/lib
ExecStart=$OPT_BIN/singularity-portal
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF

cat > "$ETC_USER_DIR/singularity-session.target" <<EOF
[Unit]
Description=Singularity session
BindsTo=graphical-session.target
Before=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
EOF

systemctl --global enable singularity-keyring.service xdg-desktop-portal-singularity.service 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true
run_as_user systemctl --user daemon-reload 2>/dev/null || true
run_as_user systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true

LEGACY="$REAL_HOME/.local/singularity"
if [ -d "$LEGACY" ]; then
    echo "Cleaning up legacy install at $LEGACY ..."
    rm -rf "$LEGACY"
fi
# Stale per-user D-Bus service / portal files from old installs shadow the
# system ones (the home XDG dir wins), and their Exec points at the removed
# legacy tree, so the portal backend fails to activate and Settings falls back
# to another backend (wrong accent, wrong file chooser). Drop them.
STALE_DBUS="$REAL_HOME/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.singularity.service"
STALE_PORTAL="$REAL_HOME/.local/share/xdg-desktop-portal/portals/singularity.portal"
for stale in "$STALE_DBUS" "$STALE_PORTAL"; do
    if [ -f "$stale" ]; then
        echo "Removing stale per-user portal file $stale ..."
        rm -f "$stale"
    fi
done

# A Singularity theme under ~/.local/share/themes shadows the one we install to
# /opt (XDG_DATA_HOME wins over XDG_DATA_DIRS). The full Singularity theme now
# ships from /opt only; drop any per-user copy so the fresh one is picked up.
STALE_THEME="$REAL_HOME/.local/share/themes/Singularity"
if [ -d "$STALE_THEME" ]; then
    echo "Removing stale per-user theme $STALE_THEME ..."
    rm -rf "$STALE_THEME"
fi

echo ""
echo "Deploy complete."
echo ""
echo "Active binary: $OPT_BIN/singularity-desktop"
echo "Active libsingularity: $OPT_LIB/libsingularity.so.0.1.0"
echo ""
echo "Restart the session (logout/login) so the new binary is picked up."
