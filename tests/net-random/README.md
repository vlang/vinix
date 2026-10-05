# Networking randomness

Run `tests/net-random/run.sh` to compile the production V networking and
secret-erasure implementations, then call their exported interfaces from C.
The generator and clock have deterministic host stand-ins. No V builtin
runtime is linked, and the production objects are checked for allocator
imports. Address and undefined-behavior sanitizers are enabled by
default; set `VINIX_NET_RANDOM_SANITIZERS=none` to disable them.

Coverage includes 64 SipHash answers at 16 unaligned offsets, 262,144 IP IDs
with the 32,768-datagram reuse guarantee, IPv4/IPv6 tuple separation and every
address byte, the ISN clock, random port distribution/exhaustion, C callback
arguments and negative results, large unsigned uniform bounds, pooled output
boundaries and the early-boot fallback when the generator cannot fill.
