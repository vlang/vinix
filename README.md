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

`GNU make`, `GNU patch`, `GNU coreutils`, `git`, `meson`, `ninja`, `m4`, `texinfo`, `gcc/clang`, `python3`, `pip3`, `wget`, `xorriso`, and `qemu` to test it.

### Build prerequisites for macOS

These are the step-by-step instructions to build Vinix on macOS:

First of all, it is necessary to have `brew` installed:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After `brew` is installed, install the required dependencies:
```bash
brew install meson wget gpatch xorriso coreutils qemu
```

### Build prerequisites for Ubuntu, Debian, and derivatives

For Ubuntu or Debian based distros, install the prerequisites with:
```bash
sudo apt install build-essential git meson m4 texinfo python3 python3-pip wget xorriso qemu-system-x86
```

### Installing xbstrap

It is necessary to fetch `xbstrap` from `pip3`.

```bash
sudo pip3 install xbstrap
```

### Building the distro

To build the distro which includes the cross toolchain necessary
to build kernel and ports, run:

```bash
make distro
```

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
