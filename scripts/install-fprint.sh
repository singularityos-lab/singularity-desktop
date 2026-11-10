#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PREFIX="/opt/local"
MODE="install"
DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        *) echo "usage: install-fprint.sh [--prefix DIR] [--dry-run] [--uninstall]" >&2; exit 2 ;;
    esac
done

FPRINT_LIB="$PREFIX/lib/fprint"
HELPER="$PREFIX/libexec/singularity-fprint-driver"
POLICY="/usr/share/polkit-1/actions/dev.sinty.fprint-driver.policy"
DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN="$DROPIN_DIR/singularity-fprint.conf"
DRIVERS_DIR="/var/lib/singularity/fprint"
LIBFPRINT_STAGE="$PROJECT_DIR/subprojects/libfprint/build/stage/usr/lib/x86_64-linux-gnu"
GUSB_STAGE="$PROJECT_DIR/subprojects/libgusb/stage/lib"

run() {
    if [ "$DRY_RUN" = 1 ]; then
        echo "  would run: $*"
    else
        "$@"
    fi
}

write_file() {
    if [ "$DRY_RUN" = 1 ]; then
        echo "  would write $1:"
        sed 's/^/    /'
    else
        cat > "$1"
    fi
}

acopy() {
    run cp "$1" "$2.new"
    run mv "$2.new" "$2"
}

find_fprintd() {
    local f
    for f in /usr/libexec/fprintd /usr/lib/fprintd/fprintd /usr/lib/x86_64-linux-gnu/fprintd/fprintd; do
        [ -x "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}

has_fprintd_unit() {
    command -v systemctl >/dev/null 2>&1 && systemctl cat fprintd.service >/dev/null 2>&1
}

restart_fprintd() {
    has_fprintd_unit || return 0
    run systemctl daemon-reload
    run systemctl try-restart fprintd.service
}

uninstall() {
    echo "Removing the Singularity fingerprint integration..."
    [ -f "$DROPIN" ] && run rm -f "$DROPIN" && echo "  $DROPIN"
    restart_fprintd
    [ -f "$POLICY" ] && run rm -f "$POLICY" && echo "  $POLICY"
    [ -f "$HELPER" ] && run rm -f "$HELPER" && echo "  $HELPER"
    local f
    for f in "$FPRINT_LIB"/libfprint-2.so.2 "$FPRINT_LIB"/libfprint-2.so.2.0.0 \
             "$FPRINT_LIB"/libfprint-2-tod.so.1 "$FPRINT_LIB"/libgusb.so.2 "$FPRINT_LIB"/libgusb.so.2.0.10; do
        if [ -e "$f" ] || [ -L "$f" ]; then
            run rm -f "$f"
            echo "  $f"
        fi
    done
    echo "fprintd now uses the system libfprint again."
    echo "Installed vendor drivers stay in $DRIVERS_DIR; remove them from Settings > Users first if you no longer want them."
}

install() {
    if [ ! -f "$LIBFPRINT_STAGE/libfprint-2.so.2.0.0" ] || [ ! -f "$GUSB_STAGE/libgusb.so.2.0.10" ]; then
        echo "  libfprint-TOD is not built; skipping the fingerprint driver integration"
        return 0
    fi

    run mkdir -p "$FPRINT_LIB"
    acopy "$LIBFPRINT_STAGE/libfprint-2.so.2.0.0" "$FPRINT_LIB/libfprint-2.so.2.0.0"
    run ln -sf libfprint-2.so.2.0.0 "$FPRINT_LIB/libfprint-2.so.2"
    acopy "$LIBFPRINT_STAGE/libfprint-2-tod.so.1" "$FPRINT_LIB/libfprint-2-tod.so.1"
    acopy "$GUSB_STAGE/libgusb.so.2.0.10" "$FPRINT_LIB/libgusb.so.2.0.10"
    run ln -sf libgusb.so.2.0.10 "$FPRINT_LIB/libgusb.so.2"
    echo "  libfprint-TOD installed to $FPRINT_LIB"

    local fprintd check_lib="$FPRINT_LIB"
    [ "$DRY_RUN" = 1 ] && check_lib="$LIBFPRINT_STAGE:$GUSB_STAGE"
    if ! fprintd=$(find_fprintd) || ! has_fprintd_unit; then
        echo "  fprintd is not installed; the fprintd override is skipped"
        return 0
    fi
    if LD_LIBRARY_PATH="$check_lib" ldd "$fprintd" 2>&1 | grep -q "not found"; then
        echo "  WARNING: $fprintd does not resolve against $FPRINT_LIB; the fprintd override is skipped" >&2
        return 0
    fi

    run mkdir -p "$DROPIN_DIR"
    write_file "$DROPIN" <<EOF
[Service]
Environment=LD_LIBRARY_PATH=$FPRINT_LIB
ExtensionDirectories=-$DRIVERS_DIR/singularity-fprint-drivers
EOF
    echo "  fprintd override $DROPIN"
    restart_fprintd
}

if [ "$MODE" = uninstall ]; then
    uninstall
else
    echo "Installing the fingerprint driver integration..."
    install
fi
