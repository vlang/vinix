# Explicit erasure of kernel RNG secrets

Vinix's `securemem.zero()` provides the non-elidable memory-erasure property
of OpenBSD's `explicit_bzero(3)`. It uses a small original C implementation
with volatile byte stores, not OpenBSD's weak-hook implementation. The same
implementation is compiled for amd64 and arm64 and requires no CPU feature.

The caller must provide writable kernel memory. Zero length performs no
memory access, including for a null pointer. This is not a checked usercopy
primitive, a memory barrier for other CPUs, or an entropy source.

## Integration

The shared ChaCha generator erases its original/working state arrays, output
scratch, rekey material and boot-seed copy. The amd64 seed collector erases its
address-taken hardware-random word. The arm64 collector erases its temporary
VirtIO entropy page after device reset and before freeing it, and its copied
seed/hash buffers before freeing them. Ordinary zero-initialization is unchanged.

This does not claim to erase registers, compiler-created copies, SHA-256's
internal temporaries, the original device-tree `rng-seed` property, or copies
held by firmware. Original boot-seed disposal needs a separate mapping/lifetime
audit. Generator readiness, output and rekey policy are unchanged by this PR.

## Validation

Run `python3 tests/security/securemem_test.py` with host `cc` and `clang`.
It runs bounds/canary and null-zero-length tests at O0/O2/O3 and O3+LTO, then
checks that an otherwise-dead local still receives volatile zero stores in
optimized freestanding amd64 and arm64 assembly. These tests exercise the
production C helper, not a copied model. The kernel RNG hardening workflow
also builds the actual production kernel for both architectures.

Assembly checks and host tests are not a boot test. Both kernel builds and
normal QEMU/hardware boot and getrandom smoke tests remain merge requirements.

## References

- OpenBSD semantics: https://man.openbsd.org/explicit_bzero.3
- OpenBSD kernel implementation (public domain):
  https://github.com/openbsd/src/blob/master/sys/lib/libkern/explicit_bzero.c
- OpenBSD use for random-key storage:
  https://github.com/openbsd/src/blob/master/sys/dev/rnd.c
