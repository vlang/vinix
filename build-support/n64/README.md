# Native Nintendo 64 core

The build pins [paraLLEl-N64](https://github.com/libretro/parallel-n64) revision
`ef73c7e6fa356262f88e05f85cdfad092f8f90e0`, archive SHA-256
`0be08e52bb9a759253b802a546a699dc5cc8e2799f9234e45e64550b09ffc396`.
It compiles the Mupen64Plus R4300 interpreter, CXD4 RSP interpreter and
Angrylion RDP/VI software renderer into `libvinix_n64.a`. OpenGL, Vulkan,
JIT compilation and renderer worker threads are disabled. The upstream ROM
database and PIF boot HLE are included; no console BIOS or proprietary game
data is needed by the emulator itself.

Run `python3 build-support/n64/build.py` for ARM64 musl; the app builder is
`scripts/build-n64-aarch64.sh`. `--host --output=build/n64-host` builds an
archive suitable for a native host smoke test.

The adapter permits one core per process because upstream hardware and
libretro state are global. It owns paths and the core lifecycle, validates
complete cartridge headers before replacing content, converts `.z64`, `.v64`
and `.n64` byte orders, maps digital/analog controls and forwards XRGB8888
video and stereo PCM at the game's actual sample rate. Save data uses the
upstream 296,960-byte layout: EEPROM, four controller paks, SRAM and Flash RAM.
SRAM begins at byte 133,120. Its words retain the emulator's little-endian
host order. Writes use a private temporary file, `fsync` and atomic rename.
Reset constructs a new power-on machine between frames and retains live save
memory. Core callbacks borrow pixels/samples only for the callback duration.

The build patches select the upstream compact 76 MiB memory map, avoid
clearing unused 64DD storage, remove GPU headers from the software build,
adapt optional sparse-file calls, correct interpreter-only ARM64 frame yields
and reset execution state between cartridges. CPU/RSP interpretation is
bounded to 16 million instructions per frame. The build also includes zlib
1.3.1 revision `51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf`, archive SHA-256
`d9e270d46252734aa49770fbc544125391617956266f220bd63216c834f3a522`.
The patched source lives under the build
directory; its archive, patch-producing build script, adapter, app and
homebrew sources are staged with the executable under
`/usr/share/vinix/n64/source`. This first port is experimental. Performance
and commercial-game compatibility have not been established. 64DD,
Transfer Paks, multiple controllers and accelerated rendering are not exposed.

See `THIRD-PARTY-NOTICES` and the accompanying license files before
redistributing this optional payload.
