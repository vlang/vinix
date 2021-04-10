# vOS

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

### Build Instructions

#### Prerequisites

The following packages need to be installed on the system in order to build vOS: `make`, `git`, `nasm`, `meson`, `ninja`, `m4`, `texinfo`, `gcc/clang`, `python3`, `pip3`, `parted`, `wget`, `pkg-config`, `libuuid`, `libfuse`, and `qemu` to test it.

For Ubuntu or Debian based distros, the command is:
```bash
sudo apt install build-essential git nasm meson m4 texinfo python3 python3-pip parted wget pkg-config uuid-dev libfuse-dev qemu-system-x86
```

It is necessary to fetch `xbstrap` from `pip3`, too.

```bash
sudo pip3 install xbstrap
```

#### Build commands

To build the distro which includes the cross toolchain necessary
to build kernel and ports, run:

```bash
make distro
```

The OS can then be built with `make` and ran within qemu with `make run`.
