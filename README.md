# Vinix

Vinix is an effort to write a modern, fast, and useful operating system in [the V programming language](https://vlang.io).

Join the [Discord chat](https://discord.gg/S5Nm6ZDU38).

## What is Vinix all about?

- Keeping the code as simple and easy to understand as possible, while not sacrificing
performance and prioritising code correctness.
- Making a *usable* OS which can *run on real hardware*, not just on emulators or
virtual machines.
- Targeting modern 64-bit architectures, CPU features, and multi-core computing.
- Maintaining good source-level compatibility with Linux to allow to easily port programs over.
- Exploring V capabilities in bare metal programming and improving the compiler in response to the uncommon needs of bare metal programming.
- Having fun.

**Note: Vinix is still pre-alpha software not meant for daily or production usage!**

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
- [ ] Networking
- [ ] Wayland 
- [ ] Hypervisor
- [ ] V-UI
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

`build-firefox-aarch64.sh` resolves and stages the complete Alpine runtime
dependency closure, including GTK/X11, fonts, TLS certificates, and media
libraries. It defaults to Alpine 3.22's Firefox 140 ESR: newer Alpine builds
currently link Scudo, whose virtual-memory contract Vinix does not yet provide.
Set `VINIX_FIREFOX_STAGING` to merge a different completed staging tree, or
`ALPINE_BRANCH`/`VINIX_FIREFOX_PACKAGE` to select another compatible build.

Firefox runs with software rendering and its Linux namespace/seccomp sandboxes
disabled because Vinix does not implement those kernel facilities yet. The
browser displays Firefox's reduced-protection warning accordingly.

### Apple M1 GPU test image

Vinix has an experimental native AGX path for the base M1 (`t8103`/G13G). It
uses the Mesa 25.0.5 Asahi Gallium driver for surfaceless EGL/GLES2 rendering,
then copies the completed GPU frame to the Limine framebuffer. The private GPU
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
m1n1/U-Boot chain established before the kernel starts. This is a deliberately
single-output, boot-time framebuffer handoff: connect the display before
power-on and make sure the startup UI is visible there (clamshell mode is the
most reliable choice on an Air).

```sh
./build-desktop-aarch64.sh
make -C kernel ARCH=aarch64 CC=clang
./deploy-m1-efi.sh --apple-studio-display --desktop-initramfs /Volumes/EFI
```

The deploy flag keeps the firmware's native mode, selects the largest GOP
surface when multiple outputs are present, and prevents the internal-panel DCP
experiment from resetting the inherited external scanout. Post-boot hot-plug
and the Studio Display's audio/camera/USB devices are not included yet. See
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
