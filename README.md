# Vinix

Vinix is an effort to write a modern, fast, and useful operating system in [the V programming language](https://vlang.io).

Join the [Discord chat](https://discord.gg/S5Nm6ZDU38).

## Download the ISO

You can get a continuously updated ISO of Vinix [here](https://builds.vinix-os.org/repos/files/vinix/latest/vinix.iso).

## What is Vinix all about?

- Keeping the code as simple and easy to understand as possible, while not sacrificing
performance and prioritising code correctness.
- Making a *usable* OS which can *run on real hardware*, not just on emulators or
virtual machines.
- Targetting modern 64-bit architectures, CPU features, and multi-core computing.
- Maintaining good source-level compatibility with Linux to allow to easily port programs over.
- Exploring V capabilities in bare metal programming and improving the compiler in response to the uncommon needs of bare metal programming.
- Having fun.

![Reference screenshot](/screenshot.png?raw=true "Reference screenshot")

## Roadmap

- [x] mlibc
- [x] bash
- [x] builds.vinix-os.org
- [x] gcc/g++
- [x] V
- [x] nano
- [x] storage drivers
- [x] ext2
- [ ] X.org
- [ ] X window manager
- [ ] V-UI
- [ ] network
- [ ] Intel HD graphics driver (linux port)

## Build instructions

It is *highly* recommended to just download an ISO from:
https://builds.vinix-os.org/repos/files/vinix/latest/vinix.iso

These instructions are for building Vinix, which may take a long time and
require some debugging on Linux distros that weren't properly tested
for build.

The tested distributions are: Ubuntu, Debian, and Arch Linux.

### Building Vinix on macOS, *BSD, or other non-Linux OSes

This build system does not support OSes other than Linux, due to how various packages
interact with the host distro during their build process. Pull requests making the build
capable of successfully working on non-Linux OSes are welcome, alternatively,
run the build in an x86_64 Linux VM or real hardware.

### Distro-agnostic build prerequisites

The following is a distro-agnostic list of packages needed to build Vinix.

Keep in mind that the following packages should be relatively up to date, so
older distros may not work despite the following packages having been
installed.

Skip to a paragraph for your host distro if there is any.

`GNU Bash`, `curl`, `git`, `docker`, `coreutils`, `grep`, `find`, `xorriso`,
and `qemu` to test it.

### Build prerequisites for Ubuntu, Debian, and derivatives
```bash
sudo apt install bash coreutils git docker.io grep find xorriso qemu-system-x86
```

Since the `meson` version from the repositories may be outdated, install it from `pip3`:
```bash
pip3 install --user meson
```

### Build prerequisites for Arch Linux and derivatives
```bash
sudo pacman -S --needed bash coreutils curl git docker grep find xorriso qemu
```

### Building the distro

To build the distro which includes the cross toolchain necessary
to build kernel and ports, as well as the kernel itself, run:

```bash
make # Build the distribution and image.
```

This step will take a while.

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
