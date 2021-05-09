# Veenyl

An effort to write a modern, fast, and interesting operating system in V.

Join the [Discord chat](https://discord.gg/vlang) (`#v-os` channel).

#### Goals

- Keep it simple and easy to understand.
- Write it in V as much as possible.
- Target modern 64-bit architectures and CPU features.

#### Why?

- Explore V capabilities in bare metal programming.
- Break the compiler as much as possible.
- Build a minimal and useful platform for software [especially written in V :^)], allowing for better control, isolation, and smaller attack surface in VMs.
- Having fun.

![Reference screenshot](/screenshot.png?raw=true "Reference screenshot")

## Build instructions

### OS-agnostic build prerequisites

The following is an OS-agnostic list of packages needed to build Veenyl. Skip to a paragraph for your host OS if there is any.

`GNU make`, `GNU patch`, `GNU coreutils`, `git`, `meson`, `ninja`, `m4`, `texinfo`, `gcc/clang`, `python3`, `pip3`, `util-linux`, `wget`, `mtools`, and `qemu` to test it.

### Build prerequisites for macOS

These are the step-by-step instructions to build Veenyl on macOS:

First of all, it is necessary to have `brew` installed:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After `brew` is installed, install the required dependencies:
```bash
brew install meson wget util-linux gpatch mtools coreutils qemu
```

Since not all the needed tools are in `PATH`, we will have to export `PATH` to include them, for the session.
```bash
export PATH="/usr/local/opt/util-linux/sbin:$PATH"
```

### Build prerequisites for Ubuntu, Debian, and derivatives

For Ubuntu or Debian based distros, install the prerequisites with:
```bash
sudo apt install build-essential git meson m4 texinfo python3 python3-pip util-linux wget mtools qemu-system-x86
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
