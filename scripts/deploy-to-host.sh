#!/bin/bash
# Deploy Singularity Desktop to /opt/local. Run via: make install

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DRY_RUN=0
TEST_ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --root) TEST_ROOT="$2"; shift 2 ;;
        *) echo "usage: deploy-to-host.sh [--dry-run] [--root DIR]" >&2; exit 2 ;;
    esac
done
TEST_ROOT="${TEST_ROOT:-$DEPLOY_ROOT}"

if [ -n "$TEST_ROOT" ]; then
    mkdir -p "$TEST_ROOT"
    TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
    case "$TEST_ROOT" in
        /|/opt|/opt/*|/usr|/usr/*|/etc|/etc/*|/run/host|/run/host/*|"$HOME"|/home|/root)
            echo "ERROR: --root must be a scratch directory, not $TEST_ROOT" >&2; exit 1 ;;
    esac
    if [ "$EUID" -eq 0 ]; then
        echo "ERROR: --root is a test install; run it as a normal user" >&2
        exit 1
    fi
    DEPLOY_PREFIX="$TEST_ROOT/opt/local"
    ORIG_USER="$USER"
    ORIG_HOME="$TEST_ROOT/home/$USER"
    mkdir -p "$ORIG_HOME"
fi

if [ "$EUID" -ne 0 ] && [ "$DRY_RUN" -eq 0 ] && [ -z "$TEST_ROOT" ]; then
    if [ -n "$container" ]; then
        exec host-spawn sh "$(dirname "$(readlink -f "$0")")/run0-tty.sh" \
            --setenv=ORIG_HOME="$HOME" \
            --setenv=ORIG_USER="$USER" \
            --setenv=APPS="${APPS:-all}" \
            --setenv=DEPLOY_PREFIX="${DEPLOY_PREFIX:-/opt/local}" \
            --setenv=SIT_STAGE="${SIT_STAGE:-}" \
            --setenv=ONLY_APPS="${ONLY_APPS:-}" \
            --setenv=container=host-spawned \
            bash "$0" "$@"
    else
        exec sh "$(dirname "$(readlink -f "$0")")/run0-tty.sh" \
            --setenv=ORIG_HOME="$HOME" \
            --setenv=ORIG_USER="$USER" \
            --setenv=APPS="${APPS:-all}" \
            --setenv=DEPLOY_PREFIX="${DEPLOY_PREFIX:-/opt/local}" \
            --setenv=SIT_STAGE="${SIT_STAGE:-}" \
            --setenv=ONLY_APPS="${ONLY_APPS:-}" \
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

SYSROOT="$TEST_ROOT"

host_only() {
    if [ -n "$TEST_ROOT" ]; then
        echo "  (test root) skipped: $*"
        return 0
    fi
    "$@"
}

run_as_user() {
    if [ -n "$TEST_ROOT" ]; then
        env -u DBUS_SESSION_BUS_ADDRESS -u WAYLAND_DISPLAY -u DISPLAY -u XDG_RUNTIME_DIR \
            HOME="$REAL_HOME" "$@"
        return
    fi
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

PREFIX="${DEPLOY_PREFIX:-/opt/local}"
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
OPT_SEARCH_PROVIDERS="$OPT_SING/search-providers"
OPT_FILES_ACTIONS="$OPT_SING/files-actions"
OPT_PORTAL="$OPT_SHARE/xdg-desktop-portal/portals"
OPT_DBUS="$OPT_SHARE/dbus-1/services"
OPT_BACKGROUNDS="$OPT_SHARE/backgrounds/singularity"
BUILD="$PROJECT_DIR/build"

install_build_files() {
    local extra=()
    [ "$DRY_RUN" -eq 1 ] && extra+=(--dry-run)
    APP_DBUS_SERVICES_FILE="$(mktemp)"
    python3 "$PROJECT_DIR/scripts/deploy-installed.py" \
        --info "$BUILD/meson-info" \
        --prefix "$PREFIX" \
        --sysroot "$SYSROOT" \
        --skip "$SKIPPED_APPS" \
        --only "${ONLY_APPS:-}" \
        --dbus-list "$APP_DBUS_SERVICES_FILE" \
        ${DEPLOY_MANIFEST:+--manifest "$DEPLOY_MANIFEST"} \
        "${extra[@]}"
    APP_DBUS_SERVICES="$(cat "$APP_DBUS_SERVICES_FILE")"
    rm -f "$APP_DBUS_SERVICES_FILE"
    if [ "$DRY_RUN" -eq 1 ]; then
        while IFS= read -r f; do
            echo "  widget module: $f -> $OPT_WIDGETS_LIB/"
        done < <(find "$BUILD" -maxdepth 3 -name 'libsingularity-*widget*.so' -type f 2>/dev/null)
        for f in "$PROJECT_DIR"/subprojects/*/widget/*.widget \
                 "$PROJECT_DIR"/subprojects/singularity-widgets/*/*.widget; do
            [ -f "$f" ] && echo "  widget manifest: $f -> $OPT_WIDGETS_SHARE/"
        done
    fi
    return 0
}

if [ "$DRY_RUN" -eq 1 ]; then
    case "${APPS:-all}" in
        essential) APP_TIER_LIMIT=0 ;;
        core) APP_TIER_LIMIT=1 ;;
        *) APP_TIER_LIMIT=2 ;;
    esac
    SKIPPED_APPS=""
    while read -r app tier; do
        [ -n "$app" ] || continue
        case "$tier" in essential) rank=0 ;; core) rank=1 ;; *) rank=2 ;; esac
        [ "$rank" -le "$APP_TIER_LIMIT" ] || SKIPPED_APPS="$SKIPPED_APPS $app"
    done < <(cat "$PROJECT_DIR/apps.txt" "$PROJECT_DIR/apps.local.txt" 2>/dev/null)
    echo "Dry run: every file the build installs and where a deploy to $PREFIX puts it"
    install_build_files
    exit 0
fi

mkdir -p "$OPT_BIN" "$OPT_LIB" "$OPT_APPS" "$OPT_ICONS" "$OPT_THEMES" \
         "$OPT_SCHEMAS" "$OPT_GIR" "$OPT_TYPELIB" "$OPT_SING" "$OPT_PLUGINS" \
         "$OPT_APP_SETTINGS" "$OPT_PORTAL" "$OPT_DBUS" "$OPT_BACKGROUNDS" \
         "$OPT_WIDGETS_LIB" "$OPT_WIDGETS_SHARE" "$OPT_SEARCH_PROVIDERS" "$OPT_FILES_ACTIONS"

if [ -n "${ONLY_APPS:-}" ]; then
    SKIPPED_APPS=""
    echo "Installing only: $ONLY_APPS"
    install_build_files
    glib-compile-schemas "$OPT_SCHEMAS"
    update-desktop-database "$OPT_APPS" 2>/dev/null || true
    gtk-update-icon-cache -f "$OPT_ICONS/hicolor" 2>/dev/null || true
    host_only run_as_user gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
    exit 0
fi

acopy() {
    local src="$1" dest="$2"
    cp "$src" "$dest.new"
    sync "$dest.new"
    mv "$dest.new" "$dest"
}

SNAPSHOT="$PREFIX/.previous-deploy"
SNAPSHOT_DIRS="bin lib libexec share/singularity/plugins"

runtime_problems() {
    local f out
    for f in "$OPT_BIN"/* "$PREFIX"/libexec/* "$OPT_LIB"/*.so* "$OPT_LIB"/singularity/widgets/*.so "$OPT_LIB"/fprint/*.so* "$OPT_PLUGINS"/*/*.so; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        [ "$(head -c 4 "$f" 2>/dev/null | tail -c 3)" = "ELF" ] || continue
        relocate=""
        case "$f" in "$OPT_LIB"/*.so*) relocate="-r" ;; esac
        out=$(LD_LIBRARY_PATH="$OPT_LIB/fprint:$OPT_LIB" ldd $relocate "$f" 2>&1 | grep -E "not found|undefined symbol" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*(\/.*)$//' | sort -u)
        [ -n "$out" ] && printf '%s\n' "$out" | sed "s|^|$(basename "$f"): |"
    done
    if [ -x "$OPT_BIN/labwc" ] && ! env -i PATH=/usr/bin:/bin LD_LIBRARY_PATH="$OPT_LIB" "$OPT_BIN/labwc" --version >/dev/null 2>&1; then
        echo "labwc: does not start"
    fi
}

take_snapshot() {
    rm -rf "$SNAPSHOT"
    mkdir -p "$SNAPSHOT"
    local d
    for d in $SNAPSHOT_DIRS; do
        [ -d "$PREFIX/$d" ] || continue
        mkdir -p "$(dirname "$SNAPSHOT/$d")"
        cp -a "$PREFIX/$d" "$SNAPSHOT/$d"
    done
    runtime_problems | sort -u > "$SNAPSHOT/problems-before"
}

restore_snapshot() {
    local d
    for d in $SNAPSHOT_DIRS; do
        [ -d "$SNAPSHOT/$d" ] || continue
        rm -rf "$PREFIX/$d.failed"
        [ -d "$PREFIX/$d" ] && mv "$PREFIX/$d" "$PREFIX/$d.failed"
        cp -a "$SNAPSHOT/$d" "$PREFIX/$d"
    done
}

check_runtime() {
    local after new
    after=$(runtime_problems | sort -u)
    new=$(comm -13 "$SNAPSHOT/problems-before" <(printf '%s\n' "$after" | sed '/^$/d'))
    if [ -z "$new" ]; then
        echo "Runtime check passed: every installed binary and library resolves on this system."
        return 0
    fi
    echo "" >&2
    echo "ERROR: the new build does not run on this system:" >&2
    printf '%s\n' "$new" | sed 's/^/  /' >&2
    echo "" >&2
    echo "Restoring the previous binaries and libraries so the next boot still reaches the greeter." >&2
    restore_snapshot
    echo "Restored. The rejected install is kept in $PREFIX/{bin,lib,libexec,share/singularity/plugins}.failed for inspection." >&2
    exit 1
}

echo "Deploying Singularity to $PREFIX ..."
take_snapshot

echo "Installing binaries..."
for bin in singularity-desktop \
           singularity-region-picker singularity-screenshot singularity-recorder \
           singularity-hand-control singularity-gesture-lab \
           singularity-greeter singularity-splash; do
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

case "${APPS:-all}" in
    essential) APP_TIER_LIMIT=0 ;;
    core) APP_TIER_LIMIT=1 ;;
    all) APP_TIER_LIMIT=2 ;;
    *) echo "ERROR: APPS must be all, core or essential (got '$APPS')" >&2; exit 1 ;;
esac
APP_LIST="singularity-browser singularity-dconf singularity-keyboard-reset singularity-keyring"
SKIPPED_APPS=""
while read -r app tier; do
    [ -n "$app" ] || continue
    case "$tier" in essential) rank=0 ;; core) rank=1 ;; *) rank=2 ;; esac
    if [ "$rank" -le "$APP_TIER_LIMIT" ]; then
        APP_LIST="$APP_LIST $app"
    else
        SKIPPED_APPS="$SKIPPED_APPS $app"
    fi
done < <(cat "$PROJECT_DIR/apps.txt" "$PROJECT_DIR/apps.local.txt" 2>/dev/null)

is_skipped_path() {
    local app
    for app in $SKIPPED_APPS; do
        [[ "$1" == "$PROJECT_DIR/subprojects/$app/"* ]] && return 0
    done
    return 1
}

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
RETIRED_APPS="singularity-markdown singularity-decoder"
for app in $RETIRED_APPS; do
    id="dev.sinty.${app#singularity-}"
    if [ -e "$OPT_BIN/$app" ] || [ -e "$OPT_APPS/$id.desktop" ]; then
        rm -f "$OPT_BIN/$app" "$OPT_APPS/$id.desktop" "$OPT_ICONS/hicolor/scalable/apps/$id.svg"
        echo "  $app removed (retired)"
    fi
done
for app in $SKIPPED_APPS; do
    if [ -e "$OPT_BIN/$app" ]; then
        rm -f "$OPT_BIN/$app"
        echo "  $app removed (APPS=${APPS:-all})"
    fi
done

echo "Installing everything the build installs..."
install_build_files

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
LIBINPUT_LIB=$(find "$PROJECT_DIR/subprojects/libinput/build" -maxdepth 1 -type f -name "libinput.so.10.*" 2>/dev/null | head -1)
if [ -n "$LIBINPUT_LIB" ]; then
    acopy "$LIBINPUT_LIB" "$OPT_LIB/$(basename "$LIBINPUT_LIB")"
    ln -sf "$(basename "$LIBINPUT_LIB")" "$OPT_LIB/libinput.so.10"
    echo "  $(basename "$LIBINPUT_LIB")"
fi
acopy "$BUILD/subprojects/libsingularity/libsingularity.so.0.1.0" \
      "$OPT_LIB/libsingularity.so.0.1.0"
ln -sf libsingularity.so.0.1.0 "$OPT_LIB/libsingularity.so.0"
ln -sf libsingularity.so.0.1.0 "$OPT_LIB/libsingularity.so"

if [ -f "$BUILD/subprojects/libsingularity/libsingularity-system.so.1.0.0" ]; then
    acopy "$BUILD/subprojects/libsingularity/libsingularity-system.so.1.0.0" \
          "$OPT_LIB/libsingularity-system.so.1.0.0"
    ln -sf libsingularity-system.so.1.0.0 "$OPT_LIB/libsingularity-system.so.1"
    ln -sf libsingularity-system.so.1.0.0 "$OPT_LIB/libsingularity-system.so"
    echo "  libsingularity-system.so.1.0.0"
fi

SIT_LIB="$(find "${SIT_STAGE:-/nonexistent}" -path '*/lib/libgtk-4.so.1.*' -type f 2>/dev/null | head -n 1)"
if [ -n "$SIT_LIB" ]; then
    SIT_ROOT="$(dirname "$(dirname "$SIT_LIB")")"
    acopy "$SIT_LIB" "$OPT_LIB/$(basename "$SIT_LIB")"
    ln -sf "$(basename "$SIT_LIB")" "$OPT_LIB/libgtk-4.so.1"
    if [ -d "$SIT_ROOT/lib/gtk-4.0" ]; then
        rm -rf "$OPT_LIB/gtk-4.0"
        cp -a "$SIT_ROOT/lib/gtk-4.0" "$OPT_LIB/gtk-4.0"
    fi
    SIT_IMMODULES="$OPT_LIB/gtk-4.0/4.0.0/immodules"
    for m in "$SYSROOT"/usr/lib/*/gtk-4.0/4.0.0/immodules/*.so "$SYSROOT"/usr/lib64/gtk-4.0/4.0.0/immodules/*.so; do
        [ -f "$m" ] || continue
        mkdir -p "$SIT_IMMODULES"
        [ -e "$SIT_IMMODULES/$(basename "$m")" ] || ln -sf "${m#$SYSROOT}" "$SIT_IMMODULES/$(basename "$m")"
    done
    for schema in "$SIT_ROOT"/share/glib-2.0/schemas/org.gtk.gtk4.*.gschema.xml; do
        [ -f "$schema" ] && cp "$schema" "$OPT_SCHEMAS/"
    done
    if [ -d "$SIT_ROOT/share/locale" ]; then
        while IFS= read -r mo; do
            rel="${mo#$SIT_ROOT/share/locale/}"
            mkdir -p "$OPT_SHARE/locale/$(dirname "$rel")"
            cp "$mo" "$OPT_SHARE/locale/$rel"
        done < <(find "$SIT_ROOT/share/locale" -name 'gtk40*.mo' -type f)
    fi
    echo "  $(basename "$SIT_LIB") (SIT)"
fi

GESTURE_LIB="$BUILD/subprojects/singularity-gestures/libsingularity-gesture.so.0.1.0"
if [ -f "$GESTURE_LIB" ]; then
    acopy "$GESTURE_LIB" "$OPT_LIB/libsingularity-gesture.so.0.1.0"
    ln -sf libsingularity-gesture.so.0.1.0 "$OPT_LIB/libsingularity-gesture.so.0"
    ln -sf libsingularity-gesture.so.0.1.0 "$OPT_LIB/libsingularity-gesture.so"
    echo "  libsingularity-gesture.so.0.1.0"
fi

GESTURE_RUNTIME="$PROJECT_DIR/subprojects/singularity-gestures/runtime"
if [ -d "$GESTURE_RUNTIME" ]; then
    mkdir -p "$OPT_SING/gestures/runtime"
    for asset in libmediapipe.so hand_landmarker.task face_landmarker.task \
                 libonnxruntime.so mobileone_s0_gaze.onnx; do
        [ -f "$GESTURE_RUNTIME/$asset" ] && \
            acopy "$GESTURE_RUNTIME/$asset" "$OPT_SING/gestures/runtime/$asset"
    done
    echo "  gesture runtime"
fi

if [ -d "$BUILD/extra-libs" ]; then
    for lib in "$BUILD/extra-libs/"*.so*; do
        [ -f "$lib" ] && acopy "$lib" "$OPT_LIB/$(basename "$lib")"
    done
fi

bash "$PROJECT_DIR/scripts/install-fprint.sh" --prefix "$PREFIX" ${TEST_ROOT:+--dry-run} || echo "  WARNING: the fingerprint driver integration was not installed" >&2

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
if [ ! -f "$INTER_DST/Inter-Regular.ttf" ] && [ -z "$TEST_ROOT" ]; then
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
find "$PROJECT_DIR" -path "$BUILD" -prune -o -name "*.desktop" -type f -print | while read -r desktop; do
    [[ "$desktop" == *"test"* ]] && continue
    if is_skipped_path "$desktop"; then
        rm -f "$OPT_APPS/$(basename "$desktop")"
        continue
    fi
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
    is_skipped_path "$icon_svg" && continue
    [ -f "$icon_svg" ] && cp "$icon_svg" "$SCALABLE/"
done
if [ -d "$PROJECT_DIR/subprojects/singularity-themes/Singularity" ]; then
    cp -r "$PROJECT_DIR/subprojects/singularity-themes/Singularity" "$OPT_ICONS/"
    rm -rf "$OPT_ICONS/Singularity/cursors"
    cp -r "$PROJECT_DIR/subprojects/singularity-themes/cursors/Singularity/cursors" "$OPT_ICONS/Singularity/"
    python3 "$PROJECT_DIR/subprojects/singularity-themes/tools/accent-icons.py" "$OPT_ICONS/Singularity" "$OPT_ICONS" \
        && echo "  accent folder variants" || echo "  warning: accent folder variants not generated"
    for variant in "$OPT_ICONS"/Singularity-*/; do
        [ -f "$variant/index.theme" ] && grep -q '^Hidden=true' "$variant/index.theme" && gtk-update-icon-cache -f "$variant" 2>/dev/null || true
    done
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
        host_only run_as_user "$PROJECT_DIR/scripts/install-flatpak-theme.sh" "$SING_GTK_THEME"
    fi
fi

echo "Installing wallpapers..."
WP_DIR="$PROJECT_DIR/subprojects/singularity-wallpapers"
for wp in "$WP_DIR/"*.svg "$WP_DIR/"*.png; do
    [ -f "$wp" ] && cp "$wp" "$OPT_BACKGROUNDS/"
done
for sample in waves aurora; do
    rm -f "$OPT_BACKGROUNDS/dynamic/$sample/"*.svg "$OPT_BACKGROUNDS/dynamic/$sample/"*.dynamic.json
    rmdir "$OPT_BACKGROUNDS/dynamic/$sample" 2>/dev/null || true
done
rmdir "$OPT_BACKGROUNDS/dynamic" 2>/dev/null || true

echo "Installing app settings JSON..."
for j in "$PROJECT_DIR"/subprojects/*/data/*.json; do
    [ -f "$j" ] && cp "$j" "$OPT_APP_SETTINGS/"
done

if [ -d "$OPT_SHARE/mime/packages" ] && command -v update-mime-database >/dev/null; then
    update-mime-database "$OPT_SHARE/mime" >/dev/null 2>&1 && echo "  MIME database"
fi

echo "Installing portal files / D-Bus services..."
cp "$PROJECT_DIR/data/singularity.portal" "$OPT_PORTAL/singularity.portal"

SYS_DBUS=""
for d in "$SYSROOT/usr/share/dbus-1/services" "$SYSROOT/usr/local/share/dbus-1/services"; do
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

cat > "$SYS_DBUS/dev.sinty.ush.Portal.service" <<EOF
[D-BUS Service]
Name=dev.sinty.ush.Portal
Exec=$OPT_BIN/singularity-portal
SystemdService=xdg-desktop-portal-singularity.service
EOF

cat > "$OPT_DBUS/org.freedesktop.secrets.service" <<EOF
[D-BUS Service]
Name=org.freedesktop.secrets
Exec=$OPT_BIN/singularity-keyring
EOF

sed "s|@PREFIX@|$PREFIX|g" > "$OPT_BIN/singularity-portal" <<'SPORTAL'
#!/bin/bash
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
export GDK_BACKEND=wayland
export GSK_RENDERER=gl
export GTK_A11Y=none
export XDG_CURRENT_DESKTOP=Singularity
export LD_LIBRARY_PATH="@PREFIX@/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GSETTINGS_SCHEMA_DIR="@PREFIX@/share/glib-2.0/schemas${GSETTINGS_SCHEMA_DIR:+:$GSETTINGS_SCHEMA_DIR}"
export XDG_DATA_DIRS="@PREFIX@/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
# Preload gtk4-layer-shell before libwayland-client or layer-shell init fails here.
for ls in /usr/lib/x86_64-linux-gnu/libgtk4-layer-shell.so.0 \
          /usr/lib64/libgtk4-layer-shell.so.0 \
          /usr/lib/libgtk4-layer-shell.so.0; do
    if [ -e "$ls" ]; then
        export LD_PRELOAD="$ls${LD_PRELOAD:+:$LD_PRELOAD}"
        break
    fi
done
for c in @PREFIX@/libexec @PREFIX@/bin /opt/bin /usr/local/libexec /usr/local/bin /usr/libexec /usr/bin; do
    if [ -x "$c/xdg-desktop-portal-singularity" ]; then
        exec "$c/xdg-desktop-portal-singularity"
    fi
done
exit 1
SPORTAL
chmod +x "$OPT_BIN/singularity-portal"

echo "Checking session scripts..."
SESSION_SRC="$PROJECT_DIR/subprojects/singularity-session"
for s in singularity-desktop-session singularity-labwc-session; do
    if [ ! -x "$OPT_BIN/$s" ]; then
        echo "ERROR: $OPT_BIN/$s was not installed from the build; run make compile first" >&2
        exit 1
    fi
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
if mkdir -p "$SYSROOT/usr/share/wayland-sessions" 2>/dev/null && \
   printf '%s\n' "$SESSION_ENTRY" > "$SYSROOT/usr/share/wayland-sessions/singularity.desktop" 2>/dev/null; then
    echo "  $SYSROOT/usr/share/wayland-sessions/singularity.desktop"
else
    mkdir -p "$OPT_SHARE/wayland-sessions"
    printf '%s\n' "$SESSION_ENTRY" > "$OPT_SHARE/wayland-sessions/singularity.desktop"
    echo "  $OPT_SHARE/wayland-sessions/singularity.desktop (/usr is read-only)"
    if mkdir -p "$SYSROOT/etc/systemd/system/gdm.service.d" 2>/dev/null; then
        printf '%s\n' "[Service]" \
            "Environment=\"XDG_DATA_DIRS=/var/lib/flatpak/exports/share:$OPT_SHARE:/usr/local/share:/usr/share\"" \
            > "$SYSROOT/etc/systemd/system/gdm.service.d/singularity-session.conf"
        echo "  GDM XDG_DATA_DIRS override"
        command -v systemctl >/dev/null 2>&1 && host_only systemctl daemon-reload 2>/dev/null || true
    fi
fi

host_only modprobe i2c-dev 2>/dev/null || true
if command -v udevadm >/dev/null 2>&1; then
    host_only udevadm control --reload 2>/dev/null || true
    host_only udevadm trigger --subsystem-match=i2c-dev 2>/dev/null || true
fi
echo "  external display brightness (DDC/CI) access"

echo "Installing per-user config for $REAL_USER..."

run_as_user mkdir -p "$REAL_HOME/.config/labwc"
OWNER_ARGS=(-o "$REAL_USER" -g "$REAL_USER")
[ -n "$TEST_ROOT" ] && OWNER_ARGS=()
install "${OWNER_ARGS[@]}" -m 0644 \
    "$SESSION_SRC/config/labwc/themerc" "$REAL_HOME/.config/labwc/themerc"

if command -v python3 >/dev/null 2>&1; then
    run_as_user python3 "$SESSION_SRC/scripts/migrate-labwc-rc.py" \
        "$SESSION_SRC/config/labwc/rc.xml" \
        "$REAL_HOME/.config/labwc/rc.xml" \
        --state "$REAL_HOME/.local/state/singularity/labwc-keybinds" \
        2>&1 | sed 's/^/  /'
fi

PORTALS_CONF_DIR="$REAL_HOME/.config/xdg-desktop-portal"
run_as_user mkdir -p "$PORTALS_CONF_DIR"
{
    cat "$PROJECT_DIR/data/singularity-portals.conf"
    echo
    for iface in Screenshot Settings FileChooser AppChooser OpenURI ScreenCast; do
        grep -q "^org.freedesktop.impl.portal.$iface=" "$PROJECT_DIR/data/singularity-portals.conf" || \
            echo "org.freedesktop.impl.portal.$iface=singularity"
    done
} | sed '/^$/d' > "$PORTALS_CONF_DIR/singularity-portals.conf"
host_only chown "$REAL_USER:$REAL_USER" "$PORTALS_CONF_DIR/singularity-portals.conf"

ETC_USER_DIR="$SYSROOT/etc/systemd/user"
mkdir -p "$ETC_USER_DIR"

host_only run_as_user systemctl --user stop singularity-polkit-agent.service 2>/dev/null || true
host_only run_as_user systemctl --user disable singularity-polkit-agent.service 2>/dev/null || true
host_only run_as_user systemctl --user stop singularity-keyring.service 2>/dev/null || true
host_only run_as_user systemctl --user disable singularity-keyring.service 2>/dev/null || true
host_only systemctl --global disable singularity-keyring.service 2>/dev/null || true
rm -f "$REAL_HOME/.config/systemd/user/singularity-polkit-agent.service"
rm -f "$REAL_HOME/.config/systemd/user/singularity-keyring.service" \
      "$REAL_HOME/.config/systemd/user/xdg-desktop-portal-singularity.service"
rm -f "$ETC_USER_DIR/singularity-keyring.service"

USER_DBUS_DIR="$REAL_HOME/.local/share/dbus-1/services"
run_as_user mkdir -p "$USER_DBUS_DIR"
run_as_user cp "$OPT_DBUS/org.freedesktop.secrets.service" \
    "$USER_DBUS_DIR/org.freedesktop.secrets.service"
for name in $APP_DBUS_SERVICES; do
    [ -f "$OPT_DBUS/$name" ] && run_as_user cp "$OPT_DBUS/$name" "$USER_DBUS_DIR/$name"
done
if [ -z "$TEST_ROOT" ]; then
    run_as_user gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 && \
        echo "  session bus reloaded its service files"
    accounts_pid=$(run_as_user gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.GetConnectionUnixProcessID \
        dev.sinty.Accounts 2>/dev/null | sed -nE 's/.*uint32 ([0-9]+).*/\1/p')
    if [ -n "$accounts_pid" ] && [ "$accounts_pid" -gt 1 ]; then
        kill "$accounts_pid" 2>/dev/null && echo "  restarted singularity-accounts (starts again on next use)"
    fi
fi

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
Environment=LD_LIBRARY_PATH=$OPT_LIB
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

host_only systemctl --global enable xdg-desktop-portal-singularity.service 2>/dev/null || true
host_only systemctl daemon-reload 2>/dev/null || true
host_only gdbus call --system --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
host_only run_as_user systemctl --user daemon-reload 2>/dev/null || true
host_only run_as_user systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true

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

check_runtime

echo ""
echo "Deploy complete."
echo ""
echo "Active binary: $OPT_BIN/singularity-desktop"
echo "Active libsingularity: $OPT_LIB/libsingularity.so.0.1.0"
echo ""
echo "Restart the session (logout/login) so the new binary is picked up."
