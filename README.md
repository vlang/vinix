# Vinix

**Website:** [vinix-os.org](https://vinix-os.org/)

Vinix is an effort to write a modern, fast, and useful operating system in [the V programming language](https://vlang.io).

Join the [Discord chat](https://discord.gg/S5Nm6ZDU38).

## What is Vinix all about?

- Keeping the code as simple and easy to understand as possible, while not sacrificing
performance and prioritising code correctness.
- Making a *usable* OS which can *run on real hardware*, not just on emulators or
virtual machines.
- Targeting modern 64-bit amd/arm architectures, CPU features, and multi-core computing.
- Maintaining good source-level compatibility with Linux to allow to easily port programs over. On arm64 Vinix runs Alpine binaries.
- Running on Apple Silicon Macbooks. Only M1 for now.
- Exploring V capabilities in bare metal programming and improving the compiler in response to the uncommon needs of bare metal programming.
- Having fun.

**Note: Vinix is still pre-alpha software not meant for daily or production usage!**

<img width="600" alt="image" src="https://github.com/user-attachments/assets/d2277e43-e088-4b8c-a9aa-c688c07bd439" />
<img width="600" alt="image" src="https://github.com/user-attachments/assets/60d421d7-664b-4249-b084-d4417bed8522" />

![Screenshot 0](/screenshot0.png?raw=true "Screenshot 0")
![Screenshot 1](/screenshot1.png?raw=true "Screenshot 1")

## Download latest nightly image

You can grab a pre-built nightly Vinix image at https://github.com/vlang/vinix/releases

Make sure to boot the ISO with enough memory (8+GiB) as, for now, Vinix loads its
entire root filesystem in a ramdisk in order to be able to more easily boot
on real hardware.

## Roadmap

- [x] mlibc
- [x] bash
- [x] gcc/g++
- [x] V
- [x] nano
- [x] storage drivers
- [x] ext2
- [x] X.org
- [x] X window manager
- [x] Networking
- [ ] Wayland 
- [ ] Hypervisor
- [x] V-UI 2
- [ ] Intel HD graphics driver (Linux port)
## Build instructions

### Distro-agnostic build prerequisites

The following is a distro-agnostic list of packages needed to build Vinix.

Skip to a paragraph for your host distro if there is any.

`GNU make`, `findutils`, `curl`, `git`, `xz`, `rsync`, `xorriso`, `qemu`
to test it, and a working C compiler (`cc`) needs to be present.

### Build prerequisites for Ubuntu, Debian, and derivatives
```bash
sudo apt install -y build-essential make findutils curl git xz-utils rsync xorriso qemu-system-x86
```

### Build prerequisites for Arch Linux and derivatives
```bash
sudo pacman -S --needed gcc make findutils curl git xz rsync xorriso qemu
```

### Build prerequisites for Red Hat Linux and derivatives
```bash
sudo yum install -y gcc make findutils curl git xz rsync xorriso qemu
```
### Build prerequisites for Void Linux and derivatives
```bash
sudo xbps-install -Suv gcc make findutils curl git xz rsync xorriso qemu
```
### Building the distro

To build the distro, which includes the cross toolchain necessary
to build kernel and ports, as well as the kernel itself, run:

```bash
make all     # Build the base distro and make filesystem and ISO.
```

*Note:* on certain distros, like Ubuntu 24.04, one may get an error like:
```
.../.jinx-cache/rbrt: failed to open or write to /proc/self/setgroups at line 186: Permission denied
```
In that case, it likely means apparmor is preventing the use of user namespaces,
causing `jinx` to fail to work. One can enable user namespaces by running:
```sh
sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0
```
This is not permanent across reboots. To make it so, one can do:
```sh
sudo sh -c 'echo "kernel.apparmor_restrict_unprivileged_userns = 0" >/etc/sysctl.d/99-userns.conf'
```

This will build the base distro image. Setting the `PKGS_TO_INSTALL` env
variable will allow one to specify a custom set of packages to build/install.
For example:

```bash
PKGS_TO_INSTALL='*' make all
```
This will build all packages (may take some time). Or:

```bash
PKGS_TO_INSTALL='python sqlite' make all
```
This will build the base system (like `make all`) plus the `python` and `sqlite`
packages.

The amd64 base image includes GCC, V, Xorg, and a framebuffer-backed OpenGL
demo. Boot the image and run:

```sh
run-gl-triangle
```

Use `run-gl-triangle --rebuild` to compile the same demo with GCC inside Vinix
before launching it. On amd64 this currently uses Mesa softpipe on the Limine
framebuffer.

### Python 3 on aarch64

The aarch64 image can include Alpine's musl CPython 3.12 runtime and its native
standard-library dependencies. Stage it before assembling the userland:

```sh
./build-python-aarch64.sh
./build-userland-aarch64.sh
```

Both aarch64 userland builders automatically merge
`build-aarch64-python/staging` when it is present. Set
`VINIX_PYTHON_STAGING=/path/to/staging` to use another tree. The staging script
also installs `/root/python3-smoke.py`; the ARM64 VM image runs this test during
its boot suite and it can be rerun manually with `python3`.

### Ruby on aarch64

Ruby 3.3, RubyGems, Bundler, Rake, and the native standard-library dependencies
can be staged and merged into the same aarch64 image:

```sh
./build-ruby-aarch64.sh
./build-userland-aarch64.sh
```

The userland builders merge `build-aarch64-ruby/staging` when present. Set
`VINIX_RUBY_STAGING=/path/to/staging` to override it. The runtime includes
`/root/ruby-smoke.rb`, which the ARM64 VM boot suite runs automatically and
which can also be invoked manually with `ruby`.

### Go on aarch64

The Go compiler, linker, formatter and standard library can be staged for
native development inside Vinix:

```sh
./build-go-aarch64.sh
./build-userland-aarch64.sh
```

Both aarch64 userland builders merge `build-aarch64-go/staging` when present.
Set `VINIX_GO_STAGING=/path/to/staging` to use another tree. The ARM64 VM boot
suite compiles `/root/go-smoke.go` with the native Go compiler, then runs it to
exercise goroutines, filesystem operations, subprocesses, cryptography and TCP
loopback networking. It also builds a cgo program through the native GCC
toolchain when GCC is installed.

### Codex CLI on aarch64

The aarch64 image can include the official ARM64/musl Codex CLI together with
Alpine's musl builds of its `rg` and `zsh` helpers. Stage it before assembling
the userland:

```sh
./build-codex-aarch64.sh
./build-userland-aarch64.sh
```

Both userland builders merge `build-aarch64-codex/staging` when present. Set
`VINIX_CODEX_STAGING=/path/to/staging` to use another tree. When Python is also
installed, the VM boot suite runs `/root/codex-smoke.py`, which drives
`codex exec` against a local Responses API server without requiring credentials
or Internet access.

Vinix does not yet implement Linux namespaces, so interactive and non-interactive
Codex sessions must currently opt out of the upstream sandbox:

```sh
codex --dangerously-bypass-approvals-and-sandbox
codex exec --dangerously-bypass-approvals-and-sandbox "your task"
```

### Packages on aarch64

Vinix uses Alpine 3.21's aarch64/musl repositories for optional software. Build
the network-tools layer before the userland (the desktop's compact image already
requires this layer):

```sh
./build-network-tools-aarch64.sh
./build-userland-aarch64.sh
```

The desktop builder also overlays the current network-tools layer directly,
so rebuilding the desktop refreshes `pkg` even when its base userland archive
was created before package support was added.

Inside Vinix, use `pkg` to search, install, remove, and upgrade Alpine packages.
The friendly `gtk` name installs GTK 3, its two demonstration programs, the
Adwaita icons, and DejaVu fonts:

```sh
pkg update
pkg search gtk
pkg install gtk
./gtk-package-smoke.sh
```

Gnumeric is also installed on demand with its GTK theme and fonts:

```sh
pkg install gnumeric
./gnumeric-package-smoke.sh
```

`pkg` disables Alpine maintainer scripts that assume a complete Alpine init
system.
The package database and installed files live in the running root filesystem;
with the standard initramfs they last until reboot. Direct Alpine package names
also work, for example `pkg install nano`.

GTK and Gnumeric are deliberately not included in the base or network-tools
package layer. GTK is downloaded only when it or an application that needs it
is requested. The GTK smoke test first checks that the base image is GTK-free,
installs it, then opens both `gtk3-demo` and `gtk3-widget-factory` against the
Vinix Xorg server. Gnumeric is likewise absent until explicitly installed.

### Firefox on aarch64

Firefox ESR can run as a stock Alpine musl application on Vinix's existing
framebuffer-backed Xorg server. Firefox draws its own interface with Gecko/XUL;
GTK 3 is staged as a userspace dependency for Linux window-system integration,
not implemented in the kernel or in `vinix-desktop`.

Build the X server and stage Firefox before assembling the full userland:

```sh
./build-x11-aarch64.sh
./build-firefox-aarch64.sh
./build-userland-aarch64.sh
```

Boot with at least 8 GiB of RAM, then launch the browser. The first command
creates a 2 GiB sparse boot disk when one does not already exist. With no URL,
Firefox opens the bundled smoke page; pass a URL to browse normally:

```sh
./run-aarch64.sh --mem=8192 --disk=2048
run-firefox
run-firefox https://example.com
```

After rebuilding the desktop image, its wallpaper and taskbar also contain a
Firefox launcher. Clicking it hands the framebuffer, pointer and keyboard to
Xorg for the lifetime of Firefox, then returns to the native desktop when the
browser exits:

```sh
./build-desktop-aarch64.sh
./run-desktop-aarch64.sh --no-build --mem=8192
```

The X11 session uses a small Vinix-specific input bridge for the native
absolute pointer packets and console keyboard. This keeps Linux evdev and udev
out of the system while giving Firefox normal X11 mouse and keyboard events.
The desktop builder overlays the current bridge and Firefox configuration onto
the full userland too, so an older base image cannot contain `startx` without
its required input bridge. If the compiled bridge is absent, rebuild X11 first.

`build-firefox-aarch64.sh` resolves and stages the complete Alpine runtime
dependency closure, including GTK/X11, fonts, TLS certificates, and media
libraries. It defaults to Alpine 3.22's Firefox 140 ESR: newer Alpine builds
currently link Scudo, whose virtual-memory contract Vinix does not yet provide.
Set `VINIX_FIREFOX_STAGING` to merge a different completed staging tree, or
`ALPINE_BRANCH`/`VINIX_FIREFOX_PACKAGE` to select another compatible build.
The compact desktop image used by the default M1 deployment merges the Firefox
and X11 staging trees directly, alongside Python, Git and GCC, so its launcher
works without shipping the much larger complete userland image.

On M1, Firefox automatically enables WebRender over X11 EGL when the native
render node and exact Asahi Mesa runtime are present. Xorg imports those AGX
buffers through DRI3 and uses glamor; all other targets keep the software
renderer, as does `VINIX_FORCE_SOFTWARE_GL=1`. Firefox's Linux namespace and
seccomp sandboxes remain disabled because Vinix does not implement those
kernel facilities yet, so the browser displays its reduced-protection warning.

### Apple M1 GPU test image

Vinix has an experimental native AGX path for the base M1 (`t8103`/G13G). It
uses the Mesa 25.0.5 Asahi Gallium driver for desktop OpenGL and GLES through
EGL, with surfaceless, GBM and X11 platform support. The native desktop uses a
surfaceless GPU presenter, while Xorg/Firefox share GPU buffers through PRIME
and DRI3. Both still copy the completed image to the Limine framebuffer because
Vinix does not yet have a native DCP/KMS scanout driver. The private GPU
firmware structures are currently pinned to Apple firmware ABI 12.3.0; the
driver refuses other firmware ABIs before touching GPU hardware.

Build Mesa in the Debian ARM64 VM (install `clang`, `lld`, `meson`, `ninja`,
`pkg-config`, `bison`, `flex`, `python3-mako`, `python3-yaml`,
`libclang-19-dev`, `libclc-19-dev`, `libllvmspirvlib-19-dev`, and
`spirv-tools` there):

```sh
./build-asahi-aarch64.sh
```

Copy `build-aarch64-asahi/staging` back to the same path in the macOS checkout,
then build the full ARM64 userland and kernel. The userland build needs the
Homebrew LLVM tools (`brew install llvm`):

```sh
./build-userland-aarch64.sh
make -C kernel ARCH=aarch64 CC=clang
```

Alternatively, build the GCC/V userland in the same ARM64 VM without copying
the Mesa staging directory first:

```sh
VINIX_ASAHI_STAGING="$PWD/build-aarch64-asahi/staging" \
VINIX_MUSL_SYSROOT="$PWD/build-aarch64-asahi/sysroot" \
    ./build-userland-aarch64-vm.sh
```

This produces `build-support/init-aarch64/initramfs.tar`; copy that file and
`kernel/bin/vinix` back to the macOS checkout before deploying.

To put the accelerated native desktop and Firefox in the M1 image, rebuild the
desktop after copying the Asahi staging tree, then select both the GPU and that
image at deployment:

```sh
./build-desktop-aarch64.sh --compact-initramfs
./deploy-m1-efi.sh --apple-gpu --desktop-initramfs /Volumes/EFI
```

The installed M1 deployment helper enables the GPU in its default desktop mode,
alongside Wi-Fi, so the normal hardware test is simply:

```sh
sudo ~/code/kek.sh
```

Use `sudo ~/code/kek.sh gpu` to isolate the driver with the shell test image,
or `sudo ~/code/kek.sh desktop-wifi` to boot the same desktop with AGX disabled
if the experimental probe resets before reaching userspace.

Deploy to an already-mounted M1 EFI system partition with the explicit GPU
opt-in, then boot through m1n1 so Vinix receives the patched device tree:

```sh
./deploy-m1-efi.sh --apple-gpu /Volumes/EFI
```

The test image automatically rebuilds and runs the hardware-only demo when it
finds the M1 render node. A successful first-hardware boot prints:

```text
VINIX M1 AGX RENDER TEST: PASS
```

It applies a two-minute watchdog and always leaves a recovery shell after a
failure. To rerun it manually or collect the renderer output again:

```sh
ls -l /dev/dri/renderD128
run-gl-triangle-agx --rebuild
```

The demo prints the EGL and GL renderer strings, rejects software renderers,
validates a rendered pixel, and reports when the frame reaches `/dev/fb0`.
The base M1 Air (`t8103`/G13G, including its 7-core fuse configuration) is the
first hardware target. The M5 Max (`t6050`/G17C) work remains separate and is
still fail-closed until its firmware command ABI is complete.

### Apple Studio Display on an M1 Air

Vinix can preserve a Studio Display scanout that the Apple firmware and
m1n1/U-Boot chain established before the kernel starts. This is deliberately a
single-output framebuffer handoff. Both USB-C ports are monitored, so an
inherited output reconnects live. If Vinix booted on the M1 Air panel, a first
post-boot connection performs one ANS-ordered warm reboot so firmware can
establish the external scanout.

```sh
./build-desktop-aarch64.sh
make -C kernel ARCH=aarch64 CC=clang
./deploy-m1-efi.sh --apple-studio-display --desktop-initramfs /Volumes/EFI
```

The deploy flag keeps the firmware's native mode, selects the largest GOP
surface when multiple outputs are present, prevents the internal-panel DCP
experiment from resetting the inherited external scanout, and enables the
post-boot recovery. Vinix does not yet switch the output in place because it
lacks native ATC/external-DCP modesetting. The Studio Display's
audio/camera/USB devices are not included. See
[docs/apple-studio-display.md](docs/apple-studio-display.md) for the boot
procedure, expected log lines, and failure diagnosis.

### To test

In Linux, if KVM is available, run with

```
make run-kvm
```

In macOS, if hvf is available, run with

```
make run-hvf
```

To run without any acceleration, run with

```
make run
```


```
  === Vinix aarch64 booting ===
  vinit → exceptions → term → vmm → timer → gic → sched
  → scheduler spawns kmain_thread
  → polling mode timer fires, scheduler switches context via
  eret
  → kmain_thread: framebuffer, socket, pipe, futex, fs,
  initramfs
  → *** aarch64: Kernel initialisation complete ***
```
