install_data(
  'dev.sinty.desktop.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
install_data(
  'icons/hicolor/scalable/apps/emblem-singularity.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

install_data(
  'systemd/singularity-polkit-agent.service',
  'systemd/xdg-desktop-portal-singularity.service',
  install_dir: get_option('prefix') / 'lib' / 'systemd' / 'user'
)
install_data(
  'singularity.portal',
  install_dir: get_option('datadir') / 'xdg-desktop-portal' / 'portals'
)
install_data(
  'singularity-portals.conf',
  install_dir: get_option('datadir') / 'xdg-desktop-portal'
)
install_data(
  'accountsservice/com.singularity.Desktop.xml',
  install_dir: get_option('datadir') / 'accountsservice' / 'interfaces'
)
custom_target('compile_schemas',
  input: ['dev.sinty.desktop.gschema.xml'],
  output: 'gschemas.compiled',
  command: ['glib-compile-schemas', meson.current_build_dir()],
  build_by_default: true
)

# Wallpapers are installed from the singularity-wallpapers submodule (see root meson.build).
