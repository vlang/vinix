# Vinix

Vinix is an effort to write a modern, fast, and useful operating system in [the V programming language](https://vlang.io).

Join the [Discord chat](https://discord.gg/S5Nm6ZDU38).

## What is Vinix all about?

### The key features of Vinix include:

- Support for modern 64-bit architectures, CPU features, and multi-core computing
- Keeping the code as simple and easy to understand as possible, while not sacrificing performance and prioritising code correctness.
- Good source-level compatibility with Linux to enable easy program portability
- Making a *usable* OS which can *run on real hardware*, not just on emulators or virtual machines.
- Exploration of V capabilities in bare-metal programming and improving the compiler in response to the uncommon needs of bare-metal programming
- A fun development experience


**Note: Vinix is still pre-alpha software not meant for daily or production usage!**

![Screenshot 0](/screenshot0.png?raw=true "Screenshot 0")
![Screenshot 1](/screenshot1.png?raw=true "Screenshot 1")

Photo by Hubblesite.org:
<a href="https://hubblesite.org/files/live/sites/hubble/files/home/science/stars-and-nebulae/_images/STScI-H-stars-nebulae-0411a-2400x1200.jpg">Click here</a>



## Download latest nightly image

You can grab a pre-built nightly Vinix image at
<a href="https://github.com/vlang/vinix/releases">Click here to go to the Vinix releases on GitHub</a>


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
- [ ] Wayland 
- [ ] Hypervisor
- [ ] X window manager
- [ ] V-UI
- [ ] Networking
- [ ] Intel HD graphics driver (Linux port)

## Build instructions

### Distro-agnostic build prerequisites

The following is a distro-agnostic list of packages needed to build Vinix.

Skip to a paragraph for your host distro if there is any.

`GNU make`, `curl`, `git`, `mercurial`, `bsdtar`, `xorriso`, and `qemu`
to test it.

### Build prerequisites for Ubuntu, Debian, and derivatives
```bash
sudo apt install -y make curl git mercurial libarchive-tools xorriso qemu-system-x86
```

### Build prerequisites for Arch Linux and derivatives
```bash
sudo pacman -S --needed make curl git mercurial libarchive xorriso qemu
```

### Build prerequisites for Red Hat Linux and derivatives
```bash
sudo yum install -y make curl git mercurial libarchive xorriso qemu
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

## Thank You for Using Vinix OS!

We hope you've enjoyed trying out Vinix OS and exploring what it has to offer.We appreciate your support and feedback as we continue to develop and improve Vinix OS. If you have any suggestions or issues to report, please don't hesitate to reach out to us on our <a href="https://discord.gg/S5Nm6ZDU38">Discord server</a>

Thank you again for choosing Vinix OS. We look forward to sharing more updates and features with you in the future!
