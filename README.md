# Vinix

Vinix is an effort to write a modern, fast, and useful operating system in [the V programming language](https://vlang.io).

Join the [Discord chat](https://discord.gg/S5Nm6ZDU38).

## What is Vinix all about?

- Keeping the code as simple and easy to understand as possible, while not sacrificing
performance and prioritising code correctness.
- Making a *usable* OS which can *run on real hardware*, not just on emulators or
virtual machines.
- Targetting modern 64-bit architectures, CPU features, and multi-core computing.
- Maintaining good source-level compatibility with Linux to allow to easily port programs over.
- Exploring V capabilities in bare metal programming and improving the compiler in response to the uncommon needs of bare metal programming.
- Having fun.

**Note: Vinix is still pre-alpha software not meant for daily or production usage!**

![Screenshot 0](/screenshot0.png?raw=true "Screenshot 0")
![Screenshot 1](/screenshot1.png?raw=true "Screenshot 1")

Photo by Pixabay: https://www.pexels.com/photo/gray-and-black-galaxy-wallpaper-2150/

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
- [ ] X window manager
- [ ] V-UI
- [ ] networking
- [ ] Intel HD graphics driver (Linux port)

## Build instructions

### Distro-agnostic build prerequisites

The following is a distro-agnostic list of packages needed to build Vinix.

Skip to a paragraph for your host distro if there is any.

`GNU make`, `curl`, `git`, `mercurial`, `bsdtar`, `xorriso`, and `qemu`
to test it.

### Build prerequisites for Ubuntu, Debian, and derivatives
```bash
sudo apt install make curl git mercurial bsdtar xorriso qemu-system-x86
```

### Build prerequisites for Arch Linux and derivatives
```bash
sudo pacman -S --needed make curl git mercurial libarchive xorriso qemu
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
