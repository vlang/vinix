# Vinix

Vinix is an effort to write a modern, fast, and useful operating system in [the V programming language](https://vlang.io).

Join the [Discord chat](https://discord.gg/vlang) (`#vinix-os` channel).

## Download the nightly image

You can get a nightly continuously updated ISO of Vinix [here](https://github.com/vlang/vinix/releases/download/nightly/vinix-nightly.iso).

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

## Build instructions

### OS-agnostic build prerequisites

The following is an OS-agnostic list of packages needed to build Vinix. Skip to a paragraph for your host OS if there is any.

`GNU make`, `GNU patch`, `GNU tar`, `GNU gzip`, `GNU coreutils`, `git`, `meson`, `ninja`, `m4`, `texinfo`, `gcc/clang`, `python3`, `pip3`, `wget`, `xorriso`, and `qemu` to test it.

### Build prerequisites for Ubuntu, Debian, and derivatives
```bash
sudo apt install build-essential git meson m4 texinfo python3 python3-pip wget xorriso qemu-system-x86
```

### Build prerequisites for Arch Linux and derivatives
```bash
sudo pacman -S base-devel git meson python python-pip wget xorriso qemu-arch-extra
```

### Building Vinix on macOS

This build system does not officially support macOS. Run this in an x86_64 Linux VM
or real hardware.

### Installing xbstrap

It is necessary to fetch `xbstrap` from `pip3`:
```bash
sudo pip3 install xbstrap
```

### Building the distro

To build the distro which includes the cross toolchain necessary
to build kernel and ports, run:

```bash
make distro
```

This step will take a while.

### Building the kernel and image

Simply run
```bash
make
```

### To test

In Linux, if KVM is available, run with
```bash
make run-kvm
```

In macOS, if hvf is available, run with
```bash
make run-hvf
```

To run without any acceleration, run with
```bash
make run
```
