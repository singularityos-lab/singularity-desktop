project('singularity-desktop', ['vala', 'c'],
  version: '0.1.0',
  default_options: ['buildtype=release', 'strip=true'],
)

gnome = import('gnome')
i18n = import('i18n')
fs = import('fs')
subdir('data')
subdir('po')

subproject('libsingularity')
subproject('singularity-loginui')

gestures = get_option('gestures')
gesture_runtime_ready = true
foreach runtime_file : [
  'subprojects/singularity-gestures/runtime/libmediapipe.so',
  'subprojects/singularity-gestures/runtime/hand_landmarker.task',
  'subprojects/singularity-gestures/runtime/face_landmarker.task',
  'subprojects/singularity-gestures/runtime/libonnxruntime.so',
  'subprojects/singularity-gestures/runtime/mobileone_s0_gaze.onnx',
  'subprojects/singularity-gestures/runtime/include/onnxruntime_c_api.h',
  'subprojects/singularity-gestures/runtime/include/onnxruntime_ep_c_api.h',
]
  if not fs.is_file(runtime_file)
    gesture_runtime_ready = false
  endif
endforeach
if gestures.enabled() and not gesture_runtime_ready
  error('Gesture runtime is missing. Run make gesture-runtime before configuring.')
endif
if gestures.enabled() or (gestures.auto() and gesture_runtime_ready)
  subproject('singularity-gestures')
endif

subproject('xdg-desktop-portal-singularity')
subproject('singularity-polkit-agent')
subproject('singularity-shell')

subproject('singularity-files')
subproject('singularity-calculator')
subproject('singularity-clock')
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
