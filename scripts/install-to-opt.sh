#!/bin/bash
# Install Singularity Desktop to /opt/local. Run via: make install-opt

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="$PROJECT_DIR/build"
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
OPT_PORTAL="$OPT_SHARE/xdg-desktop-portal/portals"
OPT_DBUS="$OPT_SHARE/dbus-1/services"
OPT_BACKGROUNDS="$OPT_SHARE/backgrounds/singularity"

echo "Installing Singularity Desktop to $PREFIX ..."

mkdir -p "$OPT_BIN" "$OPT_LIB" "$OPT_APPS" "$OPT_ICONS" "$OPT_THEMES" \
         "$OPT_SCHEMAS" "$OPT_GIR" "$OPT_TYPELIB" "$OPT_SING" \
         "$OPT_PORTAL" "$OPT_DBUS" "$OPT_BACKGROUNDS"

echo "Installing binaries..."
for bin in singularity-desktop singularity-region-picker singularity-screenshot singularity-recorder \
           singularity-polkit-agent singularity-greeter xdg-desktop-portal-singularity; do
    bin_path=$(find "$BUILD" -name "$bin" -executable -type f | head -n 1)
    [ -n "$bin_path" ] && cp "$bin_path" "$OPT_BIN/" && strip --strip-unneeded "$OPT_BIN/$bin" && echo "  $bin"
done

echo "Installing application binaries..."
APP_LIST="singularity-browser singularity-files singularity-edit singularity-calculator \
          singularity-photos singularity-store singularity-monitor singularity-write \
          singularity-videos singularity-leafs singularity-calendar singularity-music \
          singularity-dconf"

for app in $APP_LIST; do
    app_path=$(find "$BUILD" -name "$app" -executable -type f | head -n 1)
    if [ -n "$app_path" ]; then
        cp "$app_path" "$OPT_BIN/"
        strip --strip-unneeded "$OPT_BIN/$app"
        echo "  $app"
    else
        echo "  WARNING: $app not found in build directory!"
    fi
done

lockscreen_path=$(find "$BUILD" -name singularity-lockscreen -executable -type f | grep -v '\.p/' | head -n 1)
[ -n "$lockscreen_path" ] && cp "$lockscreen_path" "$OPT_BIN/" && strip --strip-unneeded "$OPT_BIN/singularity-lockscreen" && echo "  singularity-lockscreen"

echo "Searching for labwc..."
LABWC_BIN=""
for p in "$PROJECT_DIR/subprojects/labwc/build/labwc" \
         "$PROJECT_DIR/subprojects/labwc/build-user/labwc" \
         "$HOME/.local/singularity/bin/labwc" \
         "/opt/local/bin/labwc" \
         "/usr/local/bin/labwc" \
         "/usr/bin/labwc"; do
    if [ -f "$p" ]; then LABWC_BIN="$p"; echo "  Found labwc at: $p"; break; fi
done

if [ -n "$LABWC_BIN" ]; then
    cp "$LABWC_BIN" "$OPT_BIN/labwc" && echo "  Installed labwc to $OPT_BIN/labwc"
else
    echo "WARNING: labwc not found!"
fi

echo "Installing shared libraries..."
cp "$BUILD/subprojects/libsingularity/libsingularity.so.0.1.0" "$OPT_LIB/"
strip --strip-unneeded "$OPT_LIB/libsingularity.so.0.1.0"
ln -sf libsingularity.so.0.1.0 "$OPT_LIB/libsingularity.so.0"
ln -sf libsingularity.so.0.1.0 "$OPT_LIB/libsingularity.so"

if [ -f "$BUILD/subprojects/libsingularity/libsingularity-system.so.1.0.0" ]; then
    cp "$BUILD/subprojects/libsingularity/libsingularity-system.so.1.0.0" "$OPT_LIB/"
    strip --strip-unneeded "$OPT_LIB/libsingularity-system.so.1.0.0"
    ln -sf libsingularity-system.so.1.0.0 "$OPT_LIB/libsingularity-system.so.1"
    ln -sf libsingularity-system.so.1.0.0 "$OPT_LIB/libsingularity-system.so"
    echo "  libsingularity-system.so.1.0.0"
fi

if [ -d "$BUILD/extra-libs" ]; then
    echo "Installing bundled runtime libraries..."
    for lib in "$BUILD/extra-libs/"*.so*; do
        [ -f "$lib" ] && cp "$lib" "$OPT_LIB/" && echo "  $(basename "$lib")"
    done
fi

echo "Installing session scripts..."
SESSION_SRC="$PROJECT_DIR/subprojects/singularity-session"
for s in singularity-desktop-session singularity-labwc-session; do
    cp "$SESSION_SRC/src/$s" "$OPT_BIN/$s"
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

echo "Installing GSettings schemas..."
for schema in \
    "$PROJECT_DIR/data/dev.sinty.desktop.gschema.xml" \
    "$PROJECT_DIR"/subprojects/*/data/*.gschema.xml \
    "$PROJECT_DIR"/subprojects/singularity-shell/src/lockscreen/*.gschema.xml; do
    [ -f "$schema" ] && cp "$schema" "$OPT_SCHEMAS/" && echo "  $(basename "$schema")"
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

echo "Installing .desktop files..."
[ -f "$PROJECT_DIR/subprojects/singularity-leafs/data/dev.sinty.leafs.desktop" ] || {
    echo "ERROR: subprojects/singularity-leafs is missing dev.sinty.leafs.desktop. Run: git submodule update --init --recursive" >&2
    exit 1
}
find "$PROJECT_DIR" -name "*.desktop" -type f | while read -r desktop; do
    [[ "$desktop" == *"test"* ]] && continue
    [[ "$desktop" == *"test/"* ]] && continue
    filename=$(basename "$desktop")
    sed -E "s|^Exec=([a-z].*)$|Exec=$OPT_BIN/\1|" "$desktop" > "$OPT_APPS/$filename"
done
[ -f "$OPT_APPS/dev.sinty.leafs.desktop" ] || {
    echo "ERROR: dev.sinty.leafs.desktop was not installed to $OPT_APPS" >&2
    exit 1
}
run0 update-desktop-database "$OPT_APPS" 2>/dev/null || true

echo "Installing icons..."
if [ -d "$PROJECT_DIR/data/icons/hicolor" ]; then
    cp -r "$PROJECT_DIR/data/icons/hicolor/." "$OPT_ICONS/hicolor/"
fi
for app_icons in "$PROJECT_DIR/apps/"*/data/icons/hicolor "$PROJECT_DIR/subprojects/"*/data/icons/hicolor; do
    [ -d "$app_icons" ] && cp -r "$app_icons/." "$OPT_ICONS/hicolor/"
done
SCALABLE="$OPT_ICONS/hicolor/scalable/apps"
mkdir -p "$SCALABLE"
for icon_svg in "$PROJECT_DIR/apps/"*/data/icons/dev.sinty.*.svg "$PROJECT_DIR/subprojects/"*/data/icons/dev.sinty.*.svg; do
    [ -f "$icon_svg" ] && cp "$icon_svg" "$SCALABLE/"
done
if [ ! -f "$OPT_ICONS/hicolor/index.theme" ]; then
    cp /usr/share/icons/hicolor/index.theme "$OPT_ICONS/hicolor/" 2>/dev/null || true
fi
run0 gtk-update-icon-cache -f "$OPT_ICONS/hicolor" 2>/dev/null || true

if [ -d "$PROJECT_DIR/subprojects/singularity-themes/Singularity" ]; then
    cp -r "$PROJECT_DIR/subprojects/singularity-themes/Singularity" "$OPT_ICONS/"
fi

echo "Installing GTK themes..."
for theme_dir in "$PROJECT_DIR/subprojects/singularity-themes/themes"/*/; do
    theme_name=$(basename "$theme_dir")
    [ "$theme_name" = "SingularityExample" ] && continue
    cp -r "$theme_dir" "$OPT_THEMES/"
    echo "  $theme_name"
done

echo "Installing wallpapers..."
WP_DIR="$PROJECT_DIR/subprojects/singularity-wallpapers"
for wp in "$WP_DIR/"*.svg "$WP_DIR/"*.png; do
    [ -f "$wp" ] && cp "$wp" "$OPT_BACKGROUNDS/" && echo "  $(basename "$wp")"
done

echo "Installing CSS..."
cp "$PROJECT_DIR/subprojects/libsingularity/src/style/style.css" "$OPT_SING/" 2>/dev/null || true
cp "$PROJECT_DIR/subprojects/libsingularity/src/style/style.dark.css" "$OPT_SING/" 2>/dev/null || true
cp "$PROJECT_DIR/subprojects/libsingularity/src/style/style.light.css" "$OPT_SING/" 2>/dev/null || true

OPT_PLUGINS="$OPT_SING/plugins"
mkdir -p "$OPT_PLUGINS"
for plugin_dir in "$BUILD/subprojects/singularity-plugins"/*/; do
    plugin_name="$(basename "$plugin_dir")"
    dest="$OPT_PLUGINS/$plugin_name"
    mkdir -p "$dest"
    cp "$plugin_dir"/*.so "$dest/" 2>/dev/null || true
    cp "$BUILD/subprojects/singularity-plugins/$plugin_name"/*.plugin "$dest/" 2>/dev/null || true
    echo "  plugin: $plugin_name"
done

echo "Installing GObject typelibs..."
GIR_SRC="$(find "$BUILD" -maxdepth 4 \( -name 'Singularity-1.0.gir' -o -name 'LibSingularity-1.0.gir' \) | head -n 1)"
TYPELIB_SRC="$(find "$BUILD" -maxdepth 4 \( -name 'Singularity-1.0.typelib' -o -name 'LibSingularity-1.0.typelib' \) | head -n 1)"
[ -n "$GIR_SRC" ] && cp "$GIR_SRC" "$OPT_GIR/" && echo "  $(basename "$GIR_SRC")"
if [ -n "$TYPELIB_SRC" ]; then
    cp "$TYPELIB_SRC" "$OPT_TYPELIB/" && echo "  $(basename "$TYPELIB_SRC")"
elif [ -n "$GIR_SRC" ] && command -v g-ir-compiler &>/dev/null; then
    TYPELIB_NAME="$(basename "$GIR_SRC" .gir).typelib"
    g-ir-compiler "$GIR_SRC" --output="$OPT_TYPELIB/$TYPELIB_NAME"
    echo "  $TYPELIB_NAME (compiled)"
fi

echo "Installing portal files..."
[ -f "$PROJECT_DIR/data/singularity.portal" ] && cp "$PROJECT_DIR/data/singularity.portal" "$OPT_PORTAL/"
cat > "$OPT_PORTAL/singularity.portal" << 'PORTAL'
[portal]
DBusName=dev.sinty.Portal
Interfaces=org.freedesktop.impl.portal.Screenshot;org.freedesktop.impl.portal.Settings;org.freedesktop.impl.portal.FileChooser;org.freedesktop.impl.portal.Notification;org.freedesktop.impl.portal.Inhibit;org.freedesktop.impl.portal.Access;org.freedesktop.impl.portal.Account;org.freedesktop.impl.portal.Email;org.freedesktop.impl.portal.Lockdown;org.freedesktop.impl.portal.Wallpaper;org.freedesktop.impl.portal.AppChooser;org.freedesktop.impl.portal.Print;org.freedesktop.impl.portal.DynamicLauncher;org.freedesktop.impl.portal.ScreenCast
UseIn=Singularity
PORTAL

cat > "$OPT_DBUS/dev.sinty.Portal.service" << EOF
[D-BUS Service]
Name=dev.sinty.Portal
Exec=/opt/local/bin/singularity-portal
EOF

cat > "$OPT_BIN/singularity-portal" << 'SPORTAL'
#!/bin/bash
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
export GDK_BACKEND=wayland
export GSK_RENDERER=gl
export XDG_CURRENT_DESKTOP=Singularity
export LD_LIBRARY_PATH="/opt/local/lib:$HOME/.local/singularity/lib:/usr/local/lib:/usr/lib"

for candidate in /opt/local/bin /opt/bin /usr/local/bin $HOME/.local/singularity/bin /usr/bin; do
    if [ -x "$candidate/xdg-desktop-portal-singularity" ]; then
        exec "$candidate/xdg-desktop-portal-singularity"
    fi
done
exit 1
SPORTAL
chmod +x "$OPT_BIN/singularity-portal"

echo ""
echo "Install to $PREFIX complete."
echo ""
echo "To start Singularity Desktop:"
echo "  $OPT_BIN/singularity-labwc-session"
