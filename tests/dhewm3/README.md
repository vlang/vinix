# Doom 3 demo on ARM64 QEMU

`build-dhewm3-aarch64.sh` builds dhewm3 1.5.5 for ARM64/musl and downloads the
original Linux Doom 3 demo data. The benchmark records one scene on Vinix,
then replays that exact render-demo file on Vinix and Debian. No x86 game
binary or CPU emulation is involved.

The comparison uses QEMU/HVF, four host CPU cores, 8 GiB RAM, 640×480,
disabled sound and swap interval, and four llvmpipe workers. Both guests run
the same engine, game library, musl loader, Xvfb, Mesa 24.0.9 and LLVM 17.0.6.
Debian supplies its ARM64 kernel, base files and static init shell. This
isolates the kernel comparison; it does not compare Debian's packaged
glibc/Mesa build or hardware GPU acceleration.

![The Doom 3 demo running on Vinix in ARM64 QEMU](vinix.png)

## Build and run

Use an Apple Silicon host with QEMU, Python 3, curl, CMake, Ninja, cpio and
the `aarch64-linux-musl-gcc` / `aarch64-linux-musl-g++` cross compilers. Build
the existing userland and X11 layers first if they are absent:

```sh
./build-userland-aarch64.sh
./build-x11-aarch64.sh
./build-dhewm3-aarch64.sh
python3 tests/dhewm3/prepare-debian.py
```

The builder pins dhewm3 commit
`455b88e8dff2be822f08eb498f51b383e851fa38`, retains debugging symbols and frame
pointers in a Release build, and stages the result under
`build-aarch64-dhewm3/staging`. The demo installer is downloaded from
[the Holarse mirror](https://files.holarse-linuxgaming.de/native/Spiele/Doom%203/Demo/doom3-linux-1.1.1286-demo.x86.run).
Only `demo/demo00.pk4` is extracted, without executing the installer. Its
483,535,485-byte size and MD5 `70c2c63ef1190158f1ebd6c255b22d8e` are checked.
The freely available demo is used; full-game data is not needed.

Build an isolated ARM64 kernel, with the normal dependency directories linked
from the main checkout, and enable `LIMINE_MP=1`. For example, after creating
that worktree:

```sh
make -C ../vinix-dhewm3/kernel ARCH=aarch64 LIMINE_MP=1 CC=clang V=/path/to/v
python3 tests/dhewm3/run.py --os vinix --record --check-clock \
  --kernel-dir ../vinix-dhewm3/kernel \
  --work build-aarch64-dhewm3/gameplay
```

Recording loads `game/demo_mars_city2`, waits for startup, then records a
stationary gameplay view. `wait` counts engine command-buffer iterations, so
the recording's rendered frame count can vary with host speed. Record once,
and use that saved `vinix-demo.demo` for both guests.

```sh
python3 tests/dhewm3/run.py --os both --rounds 7 --check-clock \
  --kernel-dir ../vinix-dhewm3/kernel \
  --work build-aarch64-dhewm3/gameplay \
  --debian-kernel build-aarch64-dhewm3/debian/root/boot/vmlinuz-6.12.107+deb13-cloud-arm64 \
  --debian-root build-aarch64-dhewm3/debian/userland
```

Use the kernel path printed by `prepare-debian.py`; its package version and
SHA256 are written to `debian/kernel.json`. The Debian package index and
downloads are cached. Each guest performs a discarded warmup and the requested
number of measured runs. `results.json` contains every run and median FPS;
`vinix.log` and `debian.log` contain the complete serial transcripts. Frame
counts and successful independent ARM counter measurements must match. The
counter measures the entire engine process, including startup, rather than
only the timedemo interval.

The harness keeps its VM disks, root archive and cached root beneath `--work`.
After changing staged game/runtime files, use a new work directory or remove
the old `root` directory before replaying. Preserve the shared demo file.
Do not run other benchmark guests or CPU-heavy builds during measurements.

`--clock-only --check-clock` runs just the clock regression. `--screenshot`
captures playback from Xvfb's displayed XWD framebuffer; with host ffmpeg it
also exports a PNG. The engine's own front-buffer screenshot command returns
black under this Xvfb setup. The original demo lacks a loading GUI required
by dhewm3's render-demo playback, so the builder supplies a minimal loading
screen. That screen is outside the timed frames.

To launch in an existing guest X11 session, install the staging layer alongside
the X11 runtime and run as an ordinary user:

```sh
run-dhewm3 +map game/demo_mars_city2
```

`DISPLAY` must name a GLX-capable X server. Use `Xvfb-glx` for an offscreen
display; the smaller ordinary `Xvfb` build has GLX disabled.

## Findings and validation

On Apple M5 Max with QEMU 11.1.1, seven measured replays of the same 353-frame
gameplay recording produced:

| Guest | Median FPS | Measured range |
| --- | ---: | ---: |
| Vinix | 13.0 | 12.8–13.1 |
| Debian 13, kernel 6.12.107 | 14.5 | 14.2–14.8 |

Vinix is 10.3% below Debian in this scene. Each measured replay took about
27 seconds on Vinix and 24 seconds on Debian. These are software-rendering
results for a stationary demo scene; they are not a whole-game average.
Raw runs, independent process durations, clock checks and file hashes are in
[results-2026-10-01.json](results-2026-10-01.json).
The host is shared with other sessions. A subsequent fresh-image verification
measured 11.6 FPS under different host load with identical game and library
files, so absolute FPS and small differences should be interpreted accordingly.

The first short cinematic test showed a large, inconsistent gap. Repeating
the original kernel changed its median from 6.1 to 26.7 FPS, while a subsequent
matched test measured 28.2 FPS on Vinix and 30.5 on Debian. Host contention
affected those measurements, so they do not establish a several-fold speedup
from the kernel change. The longer gameplay test is recorded separately in
`results-2026-10-01.json`.

The timing probe did identify a reproducible kernel fault: 99 of 100 short
measurements returned identical `clock_gettime` values on the original kernel,
and dhewm3's pause-loop calibration could measure zero elapsed time. ARM64
precise clock syscalls now read the architectural counter directly. Coarse
clocks retain their tick snapshots, and `clock_getres` reports the actual
counter period, 42 ns on this host, instead of claiming 1 ns.

Checking absolute sleeps also found that a timer could subtract time that
elapsed before it was armed, returning before the requested deadline. ARM64
timers now store a counter deadline. The regression checks advancing clocks,
normalization, monotonicity, `gettimeofday`, and absolute `clock_nanosleep`
and futex deadlines against the independent counter.

The ARM64 kernel build, both boots of `tests/qemu-core/run.sh`, clock/deadline
checks and dhewm3 playback passed. The x86-64 kernel also cross-built; modern
Clang required `-Wno-error=incompatible-pointer-types` for existing VMX C/V
descriptor declarations. The existing real-time suite fails at the same
`sched_getscheduler` policy check on both the original and changed kernels.
No new allocation ownership or freeing was introduced.
