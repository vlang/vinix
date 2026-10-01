# OpenGothic on Vinix

The native ARM64/musl build of [OpenGothic](https://github.com/Try/OpenGothic)
runs in a movable Gothic II window in the Vinix desktop. Its Vulkan renderer
uses Mesa Lavapipe and LLVM on the CPU. Xvfb supplies the X11 window and the
existing desktop bridge forwards keyboard and pointer events. No Wine or x86
translation is involved.

Build on a host with Python 3, Git, curl, tar, CMake, Ninja, glslang and the
`aarch64-linux-musl-gcc`, `aarch64-linux-musl-g++` and
`aarch64-linux-musl-ar` cross compilers:

```sh
./build-opengothic-aarch64.sh --demo
./build-desktop-aarch64.sh
./run-desktop-aarch64.sh --no-build
```

Open **Gothic II** from the Start menu or its desktop shortcut. `--demo`
downloads the original German Gothic II demo from
[World of Gothic's authorized mirror](https://www.worldofgothic.de/dl/download_64.htm).
The installer is verified with SHA256
`380d2ae52e4e2eac3beea55e729eb7eb2ea04ffa13521cd22e9fe22fcbe96353`
and extracted by pinned REWise without executing its Windows installer.
The demo contains a limited world and classic Gothic II scripts; its data is
marked so the launcher supplies `-g2c`.

To use your own Gothic II / Night of the Raven installation, name its
directory instead:

```sh
./build-opengothic-aarch64.sh --game "/path/to/Gothic II"
```

That stages its `Data`, `_work` and `System` directories, whatever their case,
as `/usr/share/games/gothic2`; an installation of several gigabytes makes the
image that much larger. With neither option only the engine is staged: copy
those three directories to `/usr/share/games/gothic2` in the guest, and until
then the Gothic II window says the data is missing. The original game assets
are required and are not included in the source repository.

`build/opengothic/staging` contains the executable, launcher and private
runtime. The desktop builder picks up this layer automatically. Override it
with `VINIX_OPENGOTHIC_STAGING`; `VINIX_OPENGOTHIC_BUILD_DIR` changes the
engine builder's output directory. `GLSLANGVALIDATOR` selects a host shader
compiler. Optional layers and any demo assets stay in generated build output.

The engine and Vulkan headers are pinned to the commits in `build.py`, which
applies two patches to the pinned Tempest renderer. Both are needed before the
first frame of the world can be drawn on Lavapipe:

- `active-descriptors.patch` fixes the descriptor-set fallback, which Lavapipe
  takes for want of `VK_EXT_descriptor_heap`. The set layout omits inactive
  shader bindings, so descriptor updates must omit them too; the
  descriptor-heap path already has the check.
- `sampled-attachments.patch` lets a render target be sampled. Tempest asks a
  sampled format for blit support as well, which it needs only to generate the
  mipmaps of an uploaded texture. Lavapipe renders to and samples
  `R11G11B10UF` but does not blit into it, so the scene and sky targets were
  created without `VK_IMAGE_USAGE_SAMPLED_BIT`, and binding one as a texture
  crashed inside the driver.

The launcher uses a writable per-user directory for settings, logs, saves and
shader caches. Mesa, LLVM and their dependencies live under
`/opt/opengothic/lib`, leaving the X11 runtime's Mesa generation separate.
`VK_ICD_FILENAMES` can select another Vulkan ICD and `LP_NUM_THREADS` controls
the software renderer's worker count. Ray tracing, mesh shaders and AA default
to off. Additional arguments to `run-opengothic` override those defaults.
The current build uses OpenAL's null audio backend. Hardware Vulkan and audio
playback have not been qualified.

[tests/opengothic](../../tests/opengothic/README.md) boots the desktop in QEMU
and plays a new game from the keyboard.
