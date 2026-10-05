# Steam on Vinix

Alpine does not publish a Steam client APK. Its [Steam guide](https://wiki.alpinelinux.org/wiki/Steam)
recommends the Steam Flatpak because Valve's Linux client requires glibc.
Vinix does not have Flatpak, so this image uses Valve's official installer and
a private Debian glibc root. The QEMU translators are staged from Alpine APKs.

Valve publishes its Linux Steam client for x86 only: a bash launch script, a
32-bit glibc bootstrapper that downloads and updates the client from Valve's
CDN, and 64-bit helpers such as the Chromium-based `steamwebhelper`. The
AArch64 image runs that unmodified client through the same QEMU user-mode
translators that host Wine, with one difference: Steam is a glibc program, so
it gets a Debian multiarch root of its own instead of the musl roots the Wine
runtime lives in.

## Building the layer

The x86 translators come from the x86 translation layer; Steam's own layer
downloads Valve's installer package and the Debian libraries Valve's
`steam-libs-i386` and `steam-libs-amd64` packages depend on, then assembles the
desktop image with both:

```sh
./scripts/build-x86-translation-aarch64.sh --translator-only
./scripts/build-steam-aarch64.sh
./scripts/build-desktop-aarch64.sh --compact-initramfs --with-steam
```

The Steam layer adds about 1.3 GiB before compression. For a faster VM build,
set `VINIX_DESKTOP_GZIP_LEVEL=1`; the default is `6`. Use a translator-only
staging tree for `--with-steam` if the default x86 translation tree also holds
Wine, or the combined image can exceed the boot disk's 4 GiB file limit.
The resulting compressed Steam image is about 1 GiB with the current layers,
which exceeds the 500 MiB Asahi EFI partition; this build currently targets
the AArch64 VM.

`scripts/build-steam-aarch64.sh` fetches `steam.deb` from Valve's CDN and the packages
from `deb.debian.org`; set `VINIX_STEAM_DEB_URL`, `DEBIAN_MIRROR` and
`VINIX_STEAM_DEBIAN_RELEASE` to take them from elsewhere. It installs nothing
with dpkg: `build-support/debian-root.py` resolves the closure from the
Packages indices and unpacks the archives under
`/usr/libexec/vinix-steam/root`, so no maintainer script runs and nothing in
that root can replace a native file.

## What the launcher does

`steam` is a native shell script. It unpacks Valve's bootstrap into
`~/.local/share/Steam` on the first run, links `~/.steam/steam` to it, and
starts `steam.sh` with the Debian bash inside a UTS namespace, because Steam's
scripts stop on any kernel whose `uname` is not `Linux` and Vinix answers
`Linux` to whatever runs in its own namespace.

Every x86 program the tree starts from then on, by the scripts or by the
client itself, is handed to `qemu-i386` or `qemu-x86_64` by the kernel's exec
path. `VINIX_I386_ROOT` and `VINIX_X86_64_ROOT` in the environment tell it to
use the glibc root; without them the translators use the musl roots the Wine
launchers expect. Steam opts into a library path for each x86 word size, so
translated programs find Debian libraries before native AArch64 libraries.
The Debian tools come first on Steam's `PATH` so its scripts
get GNU coreutils and xz. Native helpers provide archive extraction, report
Steam's `zenity` prompts on the console, list x86 library dependencies with
the glibc loader, and answer `uname` for the Linux machine the client believes
it is on when no namespace could be entered. Valve's runtime scripts start
with `#!/bin/bash`; an image without a native bash gets `/bin/bash` as a
trampoline to the Debian one. The tar helper uses native Python for extraction
and GNU tar for other operations. GNU tar tries to chmod Valve's symlinks on
Vinix and fails with `ELOOP`.

The translators start as a `qemu64` CPU, which predates the SSE4 and
`CMPXCHG16B` baseline the client and its web helper are built for, so the
launcher sets `QEMU_CPU=max`. The launcher also keeps the i386 client's
large glibc allocations off QEMU's problematic `mremap` path on 16 KiB host
pages. An i386 preload answers the client's robust-list query from glibc's
thread state and rounds writable shared file mappings to Vinix's 16 KiB page
size before QEMU maps them. The 64-bit web helper makes the same robust-list
query and uses its own preload with the x86-64 glibc thread layout. The kernel
passes each preload only to translated programs of the matching architecture.
The i386 preload also loads `libXrandr` at process startup. Steam resolves
`XRRGetOutputInfo` through `RTLD_NEXT` before it loads that library itself;
without the preload its display lookup reports a missing function even when
the X11 display and library are present.
Steam authenticates its loopback WebSocket by asking `lsof` which process owns
the TCP connection. Vinix exposes socket inodes and endpoints in
`/proc/net/tcp` and `/proc/<pid>/fd`, and the Steam layer installs an `lsof`
helper for the field format that the client requests.

Valve's current launcher requires user namespaces for its container runtime.
Vinix does not provide them yet, so the Steam launcher disables that
requirement check, uses the staged glibc libraries with `STEAM_RUNTIME=0`,
and starts the client with `-no-cef-sandbox`. Steam's web helper script still
calls a steamrt entry point, so the launcher points it at a staged x86-64
`env` that starts the helper directly in the Debian root. A companion wrapper
starts Valve's downloaded launcher service from the same root; the client uses
that service to start its web helper. The launcher starts a D-Bus session bus
when the desktop has not provided one and generates a machine ID on first use.
This is Valve's unsupported runtime
disabled mode. Container based games and Proton still need user
namespaces; this feature targets the Steam client interface.

On the QEMU user network, DHCP advertises `10.0.2.3` as DNS. If that proxy
does not answer an actual query, the launcher waits for the network and uses
`1.1.1.1` and `8.8.8.8` in the guest resolver. It leaves other DHCP resolvers
alone.

## Running it

Open **Steam** from the desktop, or run `steam` in a Terminal with a
`DISPLAY`. The first launch downloads the current client (about 500 MiB) over
the guest network before the client window appears; on an emulated CPU this
can take a while. Later launches start the installed
client directly. `steam --reset` reinstalls from the bootstrap archive kept in
`/usr/lib/steam`.

The desktop uses `steam-hosted` to keep its X11 bridge open while Steam's
launcher detaches. It starts the installed client after the first updater
finishes, then closes the bridge when the client exits.

Check the pieces without starting the client with:

```sh
steam-smoke
```

It runs the Debian bash and the client's own loader through both translators,
unpacks Valve's bootstrap, detects whether the namespace compatibility mode
is needed, and confirms the kernel reports Linux inside a UTS namespace.

## Tests

`tests/steam/launcher-test.sh` checks the launcher on the host against a fake
runtime. `tests/steam/run.sh` boots an image built with `--with-steam`, runs
`steam-smoke`, and waits for the client window on the desktop's X11 bridge.
The test allocates a 12 GiB persistent home volume for Steam's first update
and at least 32 GiB of VM memory. Steam's translated Chromium subprocesses
exhausted a 16 GiB guest during startup even after the client was installed.
