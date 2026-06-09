#!/bin/bash
# Set up the Singularity greeter on top of greetd. Run via: make install-greeter

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
    if [ -n "$container" ]; then
        exec host-spawn run0 bash "$0" "$@"
    else
        exec run0 bash "$0" "$@"
    fi
fi

if [ -x /opt/local/bin/labwc ]; then
    PREFIX="/opt/local"
elif [ -x /usr/local/bin/labwc ]; then
    PREFIX="/usr/local"
else
    PREFIX="/usr"
fi
BIN="$PREFIX/bin"

if [ ! -x "$BIN/singularity-greeter" ]; then
    echo "ERROR: $BIN/singularity-greeter not found. Run 'make install' first." >&2
    exit 1
fi

GREETD_DIR="/etc/greetd"
mkdir -p "$GREETD_DIR"

cat > "$GREETD_DIR/greeter-session" <<EOF
#!/bin/bash
export PATH="$BIN:\$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export GSETTINGS_SCHEMA_DIR="$PREFIX/share/glib-2.0/schemas"
export XDG_DATA_DIRS="$PREFIX/share:/usr/local/share:/usr/share"
export GI_TYPELIB_PATH="$PREFIX/lib/girepository-1.0\${GI_TYPELIB_PATH:+:\$GI_TYPELIB_PATH}"
export GDK_BACKEND=wayland
export GSK_RENDERER=gl
export GTK_A11Y=none
for ls in /usr/lib/x86_64-linux-gnu/libgtk4-layer-shell.so.0 \\
          /usr/lib64/libgtk4-layer-shell.so.0 \\
          /usr/lib/libgtk4-layer-shell.so.0; do
    if [ -e "\$ls" ]; then
        export LD_PRELOAD="\$ls\${LD_PRELOAD:+:\$LD_PRELOAD}"
        break
    fi
done
exec "$BIN/singularity-greeter"
EOF
chmod +x "$GREETD_DIR/greeter-session"

cat > "$GREETD_DIR/start-greeter" <<EOF
#!/bin/bash
for drv in /sys/class/drm/card[0-9]*/device/driver; do
    [ -e "\$drv" ] || continue
    case "\$(basename "\$(readlink -f "\$drv")")" in
        virtio*|qxl|vmwgfx|bochs-drm|cirrus|vboxvideo|simpledrm)
            export WLR_NO_HARDWARE_CURSORS="\${WLR_NO_HARDWARE_CURSORS:-1}"
            break ;;
    esac
done
exec "$BIN/labwc" -s "$GREETD_DIR/greeter-session"
EOF
chmod +x "$GREETD_DIR/start-greeter"

cat > "$GREETD_DIR/config.toml" <<EOF
[terminal]
vt = 1

[default_session]
command = "$GREETD_DIR/start-greeter"
user = "greetd"
EOF

if id greetd >/dev/null 2>&1; then
    usermod -aG video,render,input greetd 2>/dev/null || true
fi

if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
    chcon -t bin_t "$GREETD_DIR/start-greeter" "$GREETD_DIR/greeter-session" 2>/dev/null || true
fi

echo "Singularity greeter configured for greetd in $GREETD_DIR."
echo
echo "To enable it as your login manager:"
echo "  1. Install greetd if it is not already (package 'greetd')."
echo "  2. Disable your current display manager, e.g. 'systemctl disable gdm'."
echo "  3. Enable greetd: 'systemctl enable greetd'."
echo "  4. Reboot."
