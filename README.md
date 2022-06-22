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
- [x] X.org
- [ ] X window manager
- [ ] V-UI
- [ ] network
- [ ] Intel HD graphics driver (linux port)

## Build instructions

### Distro-agnostic build prerequisites

The following is a distro-agnostic list of packages needed to build Vinix.

Keep in mind that the following packages should be relatively up to date, so
older distros may not work despite the following packages having been
installed.

Skip to a paragraph for your host distro if there is any.

`GNU Bash`, `curl`, `git`, `mercurial`, `docker`, `xorriso`, and `qemu`
to test it.

### Build prerequisites for Ubuntu, Debian, and derivatives
```bash
sudo apt install curl git mercurial docker.io xorriso qemu-system-x86
```

### Build prerequisites for Arch Linux and derivatives
```bash
sudo pacman -S --needed curl git mercurial docker xorriso qemu
```

### Docker

Make sure Docker and its daemon are up and running before continuing further.
This may require logging out and back into your account, or restarting your
machine.

If Docker is properly running, the output of `docker run hello-world` should
include:
```
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

If this does not work, search the web for your distro-specific instructions
for setting up Docker.

### Building the distro

To build the distro which includes the cross toolchain necessary
to build kernel and ports, as well as the kernel itself, run:

```bash
make # Build the base distribution and image.
```

By default the build system will build a minimal distro image. The `make full` option
is avaliable to build the full distro image; this step will take a while.

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
