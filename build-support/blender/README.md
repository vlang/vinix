# Native Blender backend

This directory adds a `WITH_GHOST_VINIX` backend to Blender 4.3. It does not
open an X11 or Wayland connection. GHOST renders into a surfaceless EGL pbuffer,
publishes completed XRGB8888 frames through a two-buffer shared mapping, and
reads Vinix compositor input records from standard input.

The 48-byte `VSF1` surface header contains dimensions, format, active-buffer,
reader-buffer, sequence, and buffer-size fields followed by two equally sized
pixel buffers. The compositor claims the active buffer while presenting it;
the producer drops a frame instead of overwriting a claimed buffer. Input uses
24-byte `VNI1` records followed by an optional keyboard payload. Pointer
records carry left, middle, and right button identities or a signed wheel
delta; keyboard records carry their UTF-8 byte count and payload.

Build on Alpine 3.21/aarch64 with:

```sh
./build-blender-native-aarch64.sh
```

The desktop image automatically stages
`build-aarch64-blender-native/staging/usr/libexec/vinix-blender-native` when it
is present. Blender's ordinary Alpine package is still installed on demand for
its shared data and runtime libraries, and remains usable for background jobs.
