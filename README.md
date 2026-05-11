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
- Keyboard shortcuts:
  - `F` or `Esc`: enter/exit fullscreen
  - `Right Arrow` or `N`: next preset
  - `Left Arrow` or `P`: previous preset
  - `S`: toggle shuffle
  - `A`: toggle auto-rotation
  - `Q`: cycle quality
- Right-click context menu on the visualizer.
- Quality modes for slower Macs: Low, Medium, High, Ultra.

## Requirements

- macOS 11 or newer.
- Apple Silicon Mac. The current build script produces an arm64-only bundle.
- Xcode with command line tools selected.
- foobar2000 for macOS v2.
- foobar2000 SDK built in Release configuration.
- libprojectM 4 built and installed locally.

## Expected Local Layout

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

## Build

First build the foobar2000 SDK sample workspace in Release mode so the required
static libraries exist in Xcode DerivedData. Then run:

```sh
./build_component.sh
```

The output bundle is:

```text
build/Release/foo_vis_projectm_mac.component
```

## Install

Copy the built component into foobar2000's user components folder:

```sh
rm -rf "$HOME/Library/foobar2000-v2/user-components/foo_vis_projectm_mac.component"
cp -R build/Release/foo_vis_projectm_mac.component \
  "$HOME/Library/foobar2000-v2/user-components/"
```

Restart foobar2000 after replacing the component.

## Presets

Presets are not bundled. Use the component's `Presets` button or right-click
menu to choose a folder containing `.milk` or `.prjm` files.

## Third-Party Code

This component links against libprojectM 4. projectM is distributed under the
LGPL; see the projectM project for its license and source code:

https://github.com/projectM-visualizer/projectm

The foobar2000 SDK is required to build this component but is not included in
this repository.
