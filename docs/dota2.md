# Dota 2 bring-up

The launcher runs Valve's **Linux x86-64** executable through Vinix's native
QEMU user-mode translator. It uses a private Debian glibc/Vulkan runtime;
the Alpine musl runtime used by Wine cannot load these binaries. Proton is
not needed for the Linux client.

This is a bring-up path. Passing the Vulkan or file-access probes does not
establish that Dota 2 launches, renders its menu, or supports online matches.
The game probe saves the actual guest framebuffer for inspection.

## Build the runtime and desktop

```sh
./build-steam-aarch64.sh
./build-dota2-aarch64.sh
./build-desktop-aarch64.sh --compact-initramfs --with-dota2
```

The Dota layer contains the launcher, libraries and its patched native
translator. The shared Wine translator staging is unchanged. Supply the full
Linux game installation separately at `/usr/share/games/dota2`, including its `game/`
directory, or set `VINIX_DOTA2_DIR`. Run `run-dota2` on an X11 display or open
**Dota 2** on the desktop. The default window is 1280 by 720; game arguments
are passed through. `VINIX_DOTA2_ROOT` selects another private runtime.

The game also needs Valve's actual Linux Steam client libraries, normally
installed by Steam under `$HOME/.steam/sdk64`, and its `ubuntu12_64/gldriverquery`
helper. The runtime layer supplies their distro dependencies and public TLS
trust bundle; it does not contain a Steam account or Valve's client binaries.
The desktop normally uses `/root` as its home. `VINIX_DOTA2_STEAMCLIENT` selects
another actual Linux64 `steamclient.so`; keep its matching `libtier0_s.so` and
`libvstdlib_s.so` alongside it. The launcher validates the client's ELF
architecture before starting the translator.
The normal launcher keeps Steam's normal authentication behavior. The probe
below explicitly selects the engine's anonymous test mode for local bring-up.

The launcher selects the staged amd64 Lavapipe ICD unless the caller explicitly
selects Vulkan drivers. For that default it also passes Valve's
`-vulkan_allow_cpu` option: the renderer normally excludes CPU adapters from its
device list. An explicit caller driver selection leaves this option to the
caller. Native ARM64 Venus libraries cannot be loaded by the
translated x86-64 process. This software path does not provide the GPU
acceleration used by native OpenGothic.

The default translated CPU is `Haswell`. In the actual Vinix probe, Mesa
22/LLVM 15 enumerated with QEMU's `max` CPU but aborted at shader compilation
with `64-bit code requested on a subtarget that doesn't support it`. `Haswell`
completed the Vulkan rendering probe. `QEMU_CPU` remains overridable.

The launcher enters the Linux ELF directly because Valve's `dota.sh` insists
on the `sniper` distribution. It does not change Vinix's `/etc/os-release`.
Foreign library paths are passed through QEMU's `-E` so the native translator
never attempts to load x86 libraries.

The launcher preloads the existing Bookworm robust-list compatibility library
and the runtime's `libmpg123.so.0` into the translated process. The first
handles QEMU's missing `get_robust_list`; the second prevents Dota's older
bundled decoder from breaking the distro audio dependency's `mpg123_info2`
reference. Caller additions in `VINIX_X86_64_PRELOAD` retain precedence.

The runtime's FreeType is preloaded too. The bundled older FreeType lacks
`FT_Get_Transform`, which the distro HarfBuzz library needs when Panorama loads
its text module. Valve's bundled Pango and PangoFT2 stay together: Panorama
imports `pango_ft2_new_face_substitute`, which current distro PangoFT2 no longer
exports.
Fontconfig uses `/etc/fonts` paths with the private runtime as its sysroot;
including that root in both places makes its configuration load fail.

A guest library preserves x86 `MAP_32BIT` bounds that QEMU 9.1.2 drops
when translating mmap flags. It rejects an impossible 2 GiB reservation,
skips occupied ranges using the translated process's maps, and requests
non-replacing mappings for smaller low-address ranges.

The guest preload `libvinix-dota2-steam-loader.so` opens the actual
Steam client with `RTLD_NOW | RTLD_LOCAL | RTLD_NODELETE` before Source 2 loads.
Without this ordering, Steam's coroutine imports bind partly to Source 2's
different implementation and partly to the SDK, causing assertions and a
startup crash. The early load resolves all eight client coroutine imports to
the actual SDK while preserving the global libc compatibility preloads. It
retains the client for the process lifetime to prevent the measured libnm/GLib
unload and reload failure. A startup marker is consumed before loading the
client, so child helpers skip this early load. Valve's ELFs and Steam API
implementations remain unchanged.

The Dota translator also checks guest-page collisions under QEMU's existing
mapping lock before handling a partial host page. Without this correction,
QEMU's unreserved mapping path can accept `MAP_FIXED_NOREPLACE` over an existing
4 KiB guest mapping inside a 16 KiB Vinix page and erase its contents. The
contract probe checks both mmap entry points, adjacent guest pages and retained
contents, occupied hints, boundary and overflow cases, fixed mappings, and
large reservations with small holes. The translator build cache can be selected
with `VINIX_DOTA2_QEMU_BUILD_DIR`.

## Reuse an existing installation without another full data copy

Steam's macOS installation supplies the common assets, but its executable is
Mach-O. Obtain the matching Linux depot through Valve's Steam console or
SteamCMD, then overlay it when exporting the assets. In the measured local
installation, public build `25664722` used Linux depot `373306`, manifest
`6617705396435397356`. This was obtainable with anonymous SteamCMD:

```text
login anonymous
download_depot 570 373306 6617705396435397356
quit
```

The manifest must match the installed assets; these identifiers describe the
tested build, rather than a permanent latest version. Keep the source files
unchanged while an export is in use.

```sh
python3 tools/dota2/ext2_export.py build '/path/to/dota 2 beta' \
    --overlay '/path/to/depot_373306' --state build/dota2/game-export
python3 tests/dota2/export-run.py --source '/path/to/dota 2 beta' \
    --export-state build/dota2/game-export
```

The [read-only exporter](../tools/dota2/README.md) maps file contents into a
virtual ext2 disk served over loopback NBD. The complete local Linux overlay
occupied approximately 121.5 MB of filesystem metadata for 77.58 GB of virtual
disk space. The Vinix proof compares real VPK bytes through both `pread` and
`mmap`, crossing direct and indirect block boundaries, and checks that writes
return `EROFS`.

## Verify graphics before starting the game

```sh
python3 tests/dota2/vulkan-run.py --staging build/dota2-runtime/staging
python3 tests/dota2/launcher-test.py
python3 tests/dota2/export-test.py
```

The Vulkan probe boots Vinix, runs translated `vulkaninfo` and `vkcube` on
Xvfb, and records the kernel, translator, and ICD hashes alongside its serial
log. A successful enumeration alone is insufficient: shader compilation and
presentation must complete too. The Dota probe uses Valve's engine test mode
for anonymous local bring-up and real Steam client libraries; it does not
establish authenticated matchmaking support.

With the early loader, the real Steam API test passes anonymous initialization,
callbacks and clean shutdown even with Source 2's tier0 loaded globally. The
full game advances through anonymous initialization and loads its renderer,
resource system, schema system and material system. A rendered game menu is
not yet verified.

After the file and graphics probes, capture the real game:

```sh
python3 tests/dota2/run.py \
    --base-root build/dota2-vulkan/test/root \
    --translator-staging build/dota2-runtime/staging \
    --desktop build/vinix-desktop \
    --export-state build/dota2/game-export \
    --steamclient /path/to/Steam/steamrt64 \
    --gldriverquery /path/to/Steam/ubuntu12_64/gldriverquery
```

`--steamclient` supplies Valve's Linux `steamclient.so`, `libtier0_s.so`,
and `libvstdlib_s.so`, and `--gldriverquery` supplies the real Linux helper;
if an actual Linux64 `vulkandriverquery` is present beside the supplied GL
helper, the probe validates and copies it too, recording its hash. The probe
never copies an account profile. Its private boot moves the
read-only game mount from `/root` to the game directory and
leaves both the desktop's and game's settings in writable RAM. Captures and
serial output are saved under `build/dota2/game-test`. The report requires
visual review: an engine crash or the desktop's launch/error placeholder is
not evidence that the game rendered.
