# Request-boundary RNG key retirement

This change adapts the backtracking-resistance design goal in OpenBSD's kernel
`_rs_rekey()` to Vinix's existing shared ChaCha20 generator. It depends on the
explicit-erasure change; neither a new cipher nor an entropy source is added.

## Invariant

Before a successful non-empty `krandom.fill()` releases the generator lock,
the key that generated the request has been replaced using a separate ChaCha
block that is never copied to the caller. Temporary state/key material is
explicitly erased. Thus a later disclosure of the retained generator state
should not enable reconstruction of earlier completed requests, assuming
ChaCha20's security and no remaining copies of earlier keys.

Keep the existing in-request 1 MiB rekey limit. If the final block already
triggered it, do not rekey twice. A zero-length request does not change state.
Only the shared generator changes; both amd64 and arm64 callers get the policy.
The original 64-bit counter / 64-bit nonce layout is retained. The previous
comment incorrectly described this as RFC 8439's 32-bit counter / 96-bit nonce
layout; this change corrects the comment, not the algorithm.

This is not a byte-for-byte port of OpenBSD's buffered RNG. Output across
request boundaries changes; callers must not depend on a deterministic kernel
random stream. A small non-empty request costs one additional ChaCha block
and erasure of its scratch storage. Performance has not been benchmarked.

## Limits

Rekeying is not reseeding. Compromise of live state can still predict future
output until fresh unpredictable entropy is incorporated. Timer-only boot
state stays insecure; rekeying must not flip the readiness flag. This change
does not remove retained firmware/device-tree seeds, implement ongoing entropy
collection, guarantee removal of register/compiler copies, or protect output
already copied into a caller's memory. Those are separate hardening tasks.

## Tests and merge gate

Run `V=/path/to/v sh tests/security/run-krandom.sh`. It stages the actual shared
`random.v` unchanged, uses the production `securemem` wrapper and C eraser,
and replaces only privileged hardware seeding and the lock with host fixtures.
No test fixture is included in a kernel build. These are single-threaded
algorithm tests, not an SMP locking or boot test.

The six tests cover a known ChaCha block, two one-byte requests with independent
key/nonce fixtures, null/zero length, partial-block canaries, exact and crossed
1 MiB boundaries, and rejection of insecure state unless explicitly permitted.
The fixtures were calculated independently with Python cryptography 46.0.4's
ChaCha20 implementation, using a little-endian 64-bit counter and 64-bit nonce.

The CI workflow runs the V tests and builds production amd64 and arm64 kernels.
A green workflow plus QEMU/hardware boot and getrandom smoke tests are required
before merge. Host C erasure tests alone do not validate this V change.

## References

- OpenBSD kernel `_rs_rekey()` and `_rs_random_buf()`:
  https://github.com/openbsd/src/blob/master/sys/dev/rnd.c
- OpenBSD RNG interface: https://man.openbsd.org/arc4random.9
- Independent vector implementation:
  https://cryptography.io/en/46.0.4/hazmat/primitives/symmetric-encryption/
