# Native Vinix / KekVM validation

The release ARM64 OpenGothic build rendered the Gothic II public demo's
opening world at a median **83.45 FPS** over 60 seconds after a 10-second
warmup (115 Mesa overlay samples). The window rendered at 1280×720 inside
the 2048×1536 Vinix desktop. The host was an Apple M5 Max, with four guest
vCPUs and 12 GiB guest RAM; other host compiler jobs remained running.
This validates the opening scene, rather than a complete playthrough.
Individual samples ranged from 21.57 to 135.95 FPS during host contention.
The [recorded result](venus-performance.json) includes the exact binary hashes.
An earlier release run measured 89.63 FPS before integration with the latest
kernel changes from other sessions.

The [screenshot](../../docs/screenshots/vinix-opengothic-venus.png) is QEMU's framebuffer
capture after starting a new game and sending movement input. Its overlay
identifies `Virtio-GPU Venus (Apple M5 Max)`. Rendering uses the host GPU;
Xvfb and the Vinix desktop copy the completed images for presentation.

Reproduce with the build and `--venus` commands in [README.md](README.md).
The test rejects a software renderer, native GPU failures, crashes, and
median gameplay performance below 55 FPS. It records the measured kernel,
engine and Venus library hashes in `performance.json`.

Additional checks:

- Native fence test: 1,024 measured create/poll/close cycles, alternating
  default and explicit ring-zero submission. All 18 slab classes stayed flat.
- Native Vulkan test: 32 measured instance/device/buffer/map/fence teardown
  cycles, checking all 16,384 filled words each time. All 18 slab classes
  stayed flat, with no retained allocation sites on an `ALLOC_TRACK=1` kernel.
- ARM64 and x86-64 kernel builds; private Mesa and release engine builds.
- Desktop wakeups, idle, apps and dragging; generic syscall operations,
  process churn and page-cache measurements, compared with the base kernel
  using the same V compiler. Poll retained bytes fell from 68 to 4 per test
  operation; the ARM64 stat wrapper no longer retained its 192-byte buffer.
- The allocation warning check reports 155 entries against the repository's
  allowlist, versus 156 on base `eabfebf7` with this compiler. The difference
  removes two interface conversions and two heap-promoted poll locals;
  the remaining warnings predate this change. The allowlist was not expanded.
- A separate review checked new GEM, mapping, fence descriptor and scheduler
  lifetimes, plus asynchronous X11 presentation and the checked private QEMU
  timer patch.

Audio uses the null backend. The test disables ray tracing, GI, mesh shaders
and AA, matching the launcher defaults.
