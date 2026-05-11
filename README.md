# foo_vis_projectm_mac

Native macOS foobar2000 component that embeds the projectM 4 visualizer as a
Default UI element.

## Features

- projectM/MilkDrop preset rendering through libprojectM 4.
- foobar2000 PCM playback capture for audio-reactive visuals.
- Preset folder and texture folder selection.
- Previous/next preset controls.
- Shuffle and auto-rotation.
- Optional static mode with auto-rotation disabled.
- Smooth auto preset transitions.
- Fullscreen mode using the same active visualizer instance.
- Right-click context menu on the visualizer.
- Quality modes for slower Macs: Low, Medium, High, Ultra.

## Keyboard Shortcuts

Click the visualizer first so it has keyboard focus, then use:

| Shortcut | Action |
| --- | --- |
| `F` | Enter or exit fullscreen |
| `Esc` | Exit fullscreen |
| `Right Arrow` or `N` | Next preset |
| `Left Arrow` or `P` | Previous preset |
| `S` | Toggle shuffle |
| `A` | Toggle auto-rotation |
| `Q` | Cycle quality mode |

## Install

- macOS 11 or newer.
- Apple Silicon Mac. The current release is arm64-only.
- foobar2000 for macOS v2.

Download the latest release zip, unzip it, then copy
`foo_vis_projectm_mac.component` into foobar2000's user components folder:

```sh
mkdir -p "$HOME/Library/foobar2000-v2/user-components"
rm -rf "$HOME/Library/foobar2000-v2/user-components/foo_vis_projectm_mac.component"
cp -R foo_vis_projectm_mac.component \
  "$HOME/Library/foobar2000-v2/user-components/"
```

Restart foobar2000 after installing or replacing the component.

The release component is self-contained and includes the projectM runtime
library. Users do not need Xcode, the foobar2000 SDK or projectM source code to
install it.

## Presets

Presets are not bundled. Use the component's `Presets` button or right-click
menu to choose a folder containing `.milk` or `.prjm` files.

Texture packs are also not bundled. If a preset pack needs textures, use the
`Textures` button or right-click menu to choose the texture folder.

## Build From Source

Build requirements:

- Xcode or Apple Command Line Tools.
- `xcode-select` configured to an installed developer directory.
- foobar2000 SDK built in Release configuration.
- libprojectM 4 built and installed locally.

The current build script expects this repository to sit next to the SDK and the
projectM install prefix:

```text
workspace/
  foobar2000-SDK/
  projectm-install/
  foo_vis_projectm_mac/
```

`projectm-install` must contain:

```text
include/projectM-4/projectM.h
lib/libprojectM-4.4.dylib
```

First build the foobar2000 SDK sample workspace in Release mode so the required
static libraries exist in Xcode DerivedData. Then run:

```sh
./build_component.sh
```

The output bundle is:

```text
build/Release/foo_vis_projectm_mac.component
```

## Third-Party Code

This component links against libprojectM 4. projectM is distributed under the
LGPL; see the projectM project for its license and source code:

https://github.com/projectM-visualizer/projectm

The foobar2000 SDK is required to build this component but is not included in
this repository.
