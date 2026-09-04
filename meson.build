project('singularity-desktop', ['vala', 'c'],
  version: '0.1.0',
  default_options: ['buildtype=release', 'strip=true'],
)

gnome = import('gnome')
i18n = import('i18n')
subdir('data')
subdir('po')

subproject('libsingularity')
subproject('singularity-loginui')
subproject('singularity-gestures')

subproject('xdg-desktop-portal-singularity')
subproject('singularity-polkit-agent')
subproject('singularity-shell')

subproject('singularity-files')
subproject('singularity-calculator')
subproject('singularity-greeter')
subproject('singularity-splash')
subproject('singularity-leafs')
if get_option('installer')
  subproject('singularity-installer')
endif
# singularity-browser: archived until feature-complete
# subproject('singularity-browser')
subproject('singularity-edit')
subproject('singularity-git')
subproject('singularity-demo')
subproject('singularity-videos')
subproject('singularity-music')
subproject('singularity-store')
subproject('singularity-photos')
subproject('singularity-monitor')
subproject('singularity-write')
subproject('singularity-calendar')

# Built-in widgets (clock, calculator) live in the singularity-widgets submodule.
subproject('singularity-widgets')

# Wallpapers live in the singularity-wallpapers submodule (installs its own data).
subproject('singularity-wallpapers')

# GTK and icon themes live in the singularity-themes submodule.
subproject('singularity-themes')

# App icons (hicolor) stay in the meta repo.
install_subdir('data/icons/hicolor',
  install_dir: get_option('datadir') / 'icons',
  strip_directory: false)

subproject('singularity-plugins')
subproject('singularity-keyring')
subproject('singularity-session')
