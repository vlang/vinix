# Networking randomness

Run `tests/net-random/run.sh` to compile the production V networking and
secret-erasure implementations, then call their exported C interfaces from the
independent V oracle.
The generator and clock have deterministic host stand-ins. No V builtin
runtime is linked, and all production and oracle objects are checked for
allocator imports. Address and undefined-behavior sanitizers are enabled by
default; set `VINIX_NET_RANDOM_SANITIZERS=none` to disable them. The native
runner uses V for its complete host and guest path. On macOS, Apple's runtime
does not support LeakSanitizer; ASan/UBSan remain enabled with leak detection
disabled. Supported hosts retain leak detection. Set
`VINIX_NET_RANDOM_ASAN_OPTIONS` to override that platform setting.

Coverage includes 64 SipHash answers at 16 unaligned offsets, 262,144 IP IDs
with the 32,768-datagram reuse guarantee, IPv4/IPv6 tuple separation and every
address byte, the ISN clock, random port distribution/exhaustion, C callback
arguments and negative results, large unsigned uniform bounds, pooled output
boundaries and the early-boot fallback when the generator cannot fill.

Use `--host-arch arm64` or `--host-arch amd64` to select the actual host ABI.
`--original-reference /path/to/frozen/test.c` builds the unchanged original
oracle against the same production cores and compares its exit status,
standard output and sanitizer diagnostics exactly. `--state-dir /unused/path`
retains generated artifacts, source hashes and executable manifests.
The directory must be fresh. Default temporary builds are retired on success
and failure.

A native guest run uses the architecture's real musl SDK and a previously
built kernel, for example:

```sh
tests/net-random/run.sh --arch aarch64 --kernel-dir /path/to/arm/kernel \
  --state-dir /unused/native-build --guest-state-dir /unused/guest
```

Select `x86_64` and `CC_AMD64` for the other architecture. Native C and V
controls have the same 3,600-second outer budget and every original check.
Add `--build-only` to emit a native executable without booting it.
The deterministic SplitMix64 stand-in, 64 literal golden answers and permanent
ID/port tables remain independent of the production algorithms. Local keys,
messages, output buffers and the signed callback context remain on the stack;
port selection borrows its context synchronously through the actual exported
C callback wrapper. Neither fixture nor production core imports an allocator.

See the [native compatibility qualification](../../build-support/native-compat-tools/README.md)
for host profiles, original C comparisons and real guest results.
