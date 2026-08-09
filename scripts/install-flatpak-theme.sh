#!/bin/bash

set -e

THEME_SRC="${1:?missing GTK theme path}"
THEME_ID="org.gtk.Gtk3theme.Singularity"

if [ ! -f "$THEME_SRC/gtk-3.0/gtk.css" ]; then
    echo "ERROR: Singularity GTK 3 theme not found at $THEME_SRC" >&2
    exit 1
fi

ARCH="$(flatpak --default-arch)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
EXTENSION_DIR="$DATA_HOME/flatpak/extension/$THEME_ID/$ARCH/3.22"

mkdir -p "$EXTENSION_DIR"
cp -r "$THEME_SRC/gtk-3.0/." "$EXTENSION_DIR/"
