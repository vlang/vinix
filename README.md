# vOS

An attempt to write an Operating System in V.

Goals:

- Microkernel architecture.
- UEFI support, Multiboot compliant.
- Written in V as much as possible (including libc), not dependent on external libs written in C.
- POSIX subsystem for compatibility with lots of software that already exists.
- Targetted at modern 64-bit architectures (amd64, aarch64, risc-v).
