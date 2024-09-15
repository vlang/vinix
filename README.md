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

`GNU make`, `findutils`, `curl`, `git`, `zstd`, `rsync`, `xorriso`, and `qemu`
to test it.

Additionally a working C compiler (`cc`) needs to be present.

### Build prerequisites for Ubuntu, Debian, and derivatives
```bash
sudo apt install -y build-essential make findutils curl git zstd rsync xorriso qemu-system-x86
```

### Build prerequisites for Arch Linux and derivatives
```bash
sudo pacman -S --needed gcc make findutils curl git zstd rsync xorriso qemu
```

### Build prerequisites for Red Hat Linux and derivatives
```bash
sudo yum install -y gcc make findutils curl git zstd rsync xorriso qemu
```
### Build prerequisites for Void Linux and derivatives
```bash
sudo xbps-install -Suv gcc make findutils curl git zstd rsync xorriso qemu
```
### Building the distro

To build the distro, which includes the cross toolchain necessary
to build kernel and ports, as well as the kernel itself, run:

```bash
make distro-base # Build the base distribution.
make all         # Make filesystem and ISO.
```

This will build a minimal distro image. The `make distro-full` target
is also avaliable to build the full distro; this step will take a while.

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
