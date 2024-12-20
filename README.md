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

This will build a minimal distro image. Setting the `PKGS_TO_INSTALL` env
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
