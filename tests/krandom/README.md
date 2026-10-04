# Kernel random generator checks

Run `tests/krandom/run.sh /path/to/v` for the existing ChaCha/rekey/readiness
tests and SHA-256 known answers, every padding position, unaligned binary
input, seed-sized buffers and input/output guard checks against V's separate
standard-library implementation.

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
