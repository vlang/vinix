# Kernel random generator checks

Run `tests/krandom/run.sh /path/to/v` for the existing ChaCha/rekey/readiness
tests and SHA-256 known answers, every padding position, unaligned binary
input, seed-sized buffers and input/output guard checks against V's separate
standard-library implementation.

The deterministic hardware stand-in and printf output policy live in V under
`hosthooks`. Its instruction-only printf entry captures the full native
variadic ABI, including floating-point registers and overflow stack arguments;
libc consumes the borrowed cursor before the producer returns. Run its native
integer/float/long-double/stack oracle on either architecture:

```sh
python3 tests/krandom/run_hooks.py --arch aarch64 \
  --kernel-dir /path/to/kernel --state-dir /path/to/new/guest
```

Set `CC_AMD64` to the native musl compiler for `--arch x86_64` and
`VINIX_V_COMPILER` to a verified compiler. The 32-line original host model is
recoverable at `e55f69e1c982708d8c9a256d897054b7fd229fb3:tests/krandom/host_stubs.c`.
The optional `--c-reference` accepts that immutable materialized file for
differential validation. The new ABI oracle is additional coverage and earns
no original-C translation credit; three native va-list producer lines use
assembly and also receive no V algorithm credit.

Secret erasure uses a volatile byte field in V. The host tests also check
every offset and length through 64 bytes, including empty and null requests,
with guards on both sides of the erased range.

The kernel uses the SHA-256 algorithm from
[FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf), with
borrowed input/output and fixed local working arrays. Digest, padding and
message schedule workspace is erased before return. This replaces the
one-shot standard-library helper whose internal allocations remain live
under the kernel's `-gc none -manualfree` build.

Use separate isolated worktrees for each architecture, with the kernel's
untracked build dependencies installed, then run:

```sh
python3 tests/krandom/run_native.py --arch aarch64 \
  --kernel-dir /path/to/arm-worktree/kernel --v /path/to/v \
  --state-dir /tmp/krandom-arm-new
python3 tests/krandom/run_native.py --arch x86_64 \
  --kernel-dir /path/to/x86-worktree/kernel --v /path/to/v \
  --state-dir /tmp/krandom-x86-new
```

The opt-in test invokes the production reseed and partial-read paths 10,000
times during initialization, before userspace and the maintenance thread.
It requires exactly zero retained objects in every slab class and zero large
pages, then successful userspace startup. It verifies the native hash's `abc`
known answer too. Ordinary builds omit this test. Generated C must also be
inspected for hidden allocations in the digest and its call sites; entropy
quality and the rest of the kernel's allocation behavior are separate checks.
