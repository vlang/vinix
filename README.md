# Vinix

Vinix is an effort to write a modern, fast, and useful operating system in [the V programming language](https://vlang.io).

Join the [Discord chat](https://discord.gg/vlang) (`#vinix-os` channel).

#### Download the nightly image!

You can get a nightly continuously updated ISO of Vinix [here](https://github.com/vlang/vinix/releases/download/nightly/vinix-nightly.iso).

#### Goals

- Keep the code as simple and easy to understand as possible.
- Write in V as much as possible.
- Make a *usable* OS which can *run on real hardware*, not just on emulators.
- Target modern 64-bit architectures and CPU features.
- Maintain good source-level compatibility with Linux to allow to easily port programs over.

#### Why?

- Explore V capabilities in bare metal programming.
- Improve the compiler by providing feedback in response to the uncommon needs of bare metal programming.
- Having fun.

![Reference screenshot](/screenshot.png?raw=true "Reference screenshot")

## Build instructions

### OS-agnostic build prerequisites

The following is an OS-agnostic list of packages needed to build Vinix. Skip to a paragraph for your host OS if there is any.

`docker`, `GNU make`, `GNU patch`, `git`, `gcc/clang`, `python3`, `pip3`, `xorriso`, and `qemu` to test it.

### Docker

It is necessary to have Docker installed and functional in order to build Vinix.
Read [the Docker get started guide](https://docs.docker.com/get-started/) if
you're new to it.

Generally speaking, it needs to be possible to use `docker` without `sudo` or any
other means, which usually involves adding your user to the `docker` group on
most Linux distros.

If Docker is correctly installed, running:
```bash
docker run hello-world
```
should contain the following output:
```bash
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

Ensure Docker works before moving onto the next steps.

### Build prerequisites for Ubuntu, Debian, and derivatives

```bash
sudo apt install build-essential git python3 python3-pip xorriso qemu-system-x86
```

### Build prerequisites for Arch Linux and derivatives

```bash
sudo pacman -S base-devel git python python-pip xorriso qemu-arch-extra
```

### Build prerequisites for macOS

First of all, it is necessary to have `brew` installed:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After `brew` is installed, install the required dependencies:
```bash
brew install gpatch xorriso qemu
```

### Installing xbstrap

It is necessary to fetch `xbstrap` from `pip3`.

```bash
sudo pip3 install xbstrap
```

### Building the distro

To build the distro, which includes the cross toolchain necessary to build kernel
and ports, run:

```bash
make distro
```

This step may take a long while.

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
