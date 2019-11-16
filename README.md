# vOS

An attempt to write an operating system in V.

Brainstorming started on November 15 2019.

Join the [Discord chat](https://discordapp.com/invite/n7c74HM) (`#v-os` channel). (PM one of the moderators if you don't want to verify your phone.)

Goals:

- Microkernel architecture.
- Unix/POSIX subsystem for compatibility with lots of software that already exists.
- UEFI support, Multiboot compliant.
- Written in V as much as possible (including libc), not dependent on external libs written in C.
- Targetted at modern 64-bit architectures (amd64, aarch64, risc-v).