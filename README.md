# foo_vis_projectm_mac

Native macOS foobar2000 component that embeds the projectM 4 visualizer as a
Default UI element.

## Features

- projectM/MilkDrop preset rendering through libprojectM 4.
- foobar2000 PCM playback capture for audio-reactive visuals.
- Preset folder and texture folder selection.
- Previous/next preset controls.
- Manual startup mode so projectM does not consume CPU/GPU until enabled.
- Startup behavior preference: manual startup or start automatically.
- Runtime `On` switch to enable/disable rendering and audio capture.
- Shuffle and auto-rotation.
- Optional static mode with auto-rotation disabled.
- Smooth auto preset transitions.
- Fullscreen mode using the same active visualizer instance.
- Double-click the visualizer to enter or exit fullscreen.
- Cursor auto-hides after 2 seconds of inactivity in fullscreen.
- Right-click context menu on the visualizer.
- Quality modes for slower Macs: Low, Medium, High, Ultra. Quality changes mesh
  complexity while keeping the visualizer scaled to the full pane.

## Using In A Layout

After installing and restarting foobar2000, add the element named
`projectM Visualisation` to your Default UI layout.

Example layout snippet:

```text
splitter horizontal style=thin
 splitter vertical style=thin
  tabs position=top
   playlist-picker tab-name="Playlists"
   albumlist tab-name="Library"
   projectM Visualisation tab-name="Visualizer"
  playlist
 playback-controls
```

You can also use the short element name:

```text
projectM tab-name="Visualizer"
```

## Keyboard Shortcuts

Click the visualizer first so it has keyboard focus, then use:

| Shortcut | Action |
| --- | --- |
| `F` | Enter or exit fullscreen |
| `Esc` | Exit fullscreen |
| Double-click | Enter or exit fullscreen |
| `Right Arrow` or `N` | Next preset |
| `Left Arrow` or `P` | Previous preset |
| `S` | Toggle shuffle |
| `A` | Toggle auto-rotation |
| `Q` | Cycle quality mode |
| `V` | Toggle visualizer on/off |

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

## Startup and Resource Use

The visualizer defaults to manual startup. In this mode the component stays idle
until you turn it on with the `On` switch, the right-click menu, or the `V`
keyboard shortcut.

To change this behavior, open foobar2000 Preferences and go to:

```text
Display > Visualisations > projectM Visualisation
```

There you can choose whether projectM starts automatically when foobar2000
starts.

Turning the visualizer off stops audio capture, stops the display link and
destroys the active projectM instance. Turning it back on recreates projectM and
reloads the saved preset/texture state.

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
