FROM ubuntu:26.04 AS vetro-source

ARG VETRO_SHA256=b653a4b1b75a31a8a00a5d12b11eaafa3f22d6cf2b3417efde68a113b4c60700

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    curl --fail --location --output /usr/local/bin/vetro \
      https://github.com/singularityos-lab/vetro/releases/download/v1.0.0/vetro-linux-amd64 && \
    echo "${VETRO_SHA256}  /usr/local/bin/vetro" | sha256sum --check - && \
    chmod 0755 /usr/local/bin/vetro

FROM ghcr.io/containerpak/gtk-sdk:main AS builder

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      gettext \
      git \
      gobject-introspection \
      libatspi2.0-dev \
      libcairo2-dev \
      libcmocka-dev \
      libdbusmenu-glib-dev \
      libdisplay-info-dev \
      libdrm-dev \
      libfontconfig-dev \
      libgcrypt20-dev \
      libgdk-pixbuf-2.0-dev \
      libgee-0.8-dev \
      libgl-dev \
      libgles-dev \
      libgoa-1.0-dev \
      libgstreamer-plugins-base1.0-dev \
      libgstreamer1.0-dev \
      libgtk-4-dev \
      libgtk4-layer-shell-dev \
      libgtksourceview-5-dev \
      libgudev-1.0-dev \
      libinput-dev \
      libjson-glib-dev \
      libliftoff-dev \
      libnm-dev \
      libpam0g-dev \
      libpeas-2-dev \
      libpipewire-0.3-dev \
      libpixman-1-dev \
      libpng-dev \
      libpolkit-agent-1-dev \
      libpoppler-glib-dev \
      libpulse-dev \
      librsvg2-dev \
      libseat-dev \
      libsecret-1-dev \
      libsfdo-dev \
      libsodium-dev \
      libsoup-3.0-dev \
      libsystemd-dev \
      libtracker-sparql-3.0-dev \
      libupower-glib-dev \
      libvte-2.91-gtk4-dev \
      libwayland-dev \
      libwebkitgtk-6.0-dev \
      libxcb-composite0-dev \
      libxcb-dri3-dev \
      libxcb-ewmh-dev \
      libxcb-icccm4-dev \
      libxcb-present-dev \
      libxcb-render-util0-dev \
      libxcb-res0-dev \
      libxcb-xfixes0-dev \
      libxcb-xinput-dev \
      libxkbcommon-dev \
      libxml2-dev \
      meson \
      ninja-build \
      pkg-config \
      sassc \
      scdoc \
      valac \
      wayland-protocols \
      xwayland

WORKDIR /source
COPY --from=vetro-source /usr/local/bin/vetro /usr/local/bin/vetro
COPY . .

RUN meson setup build \
      --prefix=/opt/singularity \
      --libdir=lib \
      --buildtype=release \
      -Dinstaller=false && \
    meson compile -C build && \
    meson setup subprojects/labwc/build subprojects/labwc \
      --prefix=/opt/singularity \
      --libdir=lib \
      --buildtype=release \
      -Dxwayland=enabled \
      --force-fallback-for=wlroots-0.20 && \
    meson compile -C subprojects/labwc/build && \
    DESTDIR=/stage meson install -C build && \
    DESTDIR=/stage meson install -C subprojects/labwc/build && \
    glib-compile-schemas /stage/opt/singularity/share/glib-2.0/schemas

COPY cpak/singularity-cpak-headless-session /stage/opt/singularity/bin/singularity-cpak-headless-session
COPY cpak/singularity-cpak-session /stage/opt/singularity/bin/singularity-cpak-session

FROM scratch AS desktop

COPY --from=builder /stage/ /

LABEL org.opencontainers.image.source="https://github.com/singularityos-lab/singularity-desktop"
