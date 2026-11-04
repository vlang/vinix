# Cached peer login qualification

`guest.v` is a Vinix target fixture using the Linux socket ABI and the
`SO_PEERLOGIN` option (`0x564c`). Compile it with the qualified V compiler and
the target's musl sysroot, then run it in the guest under an external deadline.
Its own 30-second alarm bounds thread startup and blocking calls. A host compile
checks declarations only; do not execute it on macOS.

The fixture checks the two-u32 record and written length, short/null output
refusals, socketpair identity, retained identity after peer close, failed-connect
recovery, and rejection of another connect after success. Each of 32 concurrent
rounds releases two threads against the same client descriptor and distinct
listeners. Exactly one connect must succeed, the losing listener's queue must
remain empty, and the accepted transport must match the winner. Every connected
endpoint must report the process identity obtained from the initial socketpair.
The fixture checks transport ownership with equal process labels; differing
login-session provenance is qualified separately by the account/audio fixtures.

The [native runtime check](runtime-check.md) passes on both fresh kernel ELFs,
including all 32 concurrent rounds and natural guest shutdown. Cross-login
provenance, allocation/performance and production integration remain separate.

`guarded-build-check.v` builds the isolated allocation-tracked kernel for both
architectures and retains source, complete input closures, generated C and
linked symbols. Its generated-C checks include coherent process snapshots,
single-writer lifecycle claims, reset after failure, permanent close retirement,
packed atomic loads/stores, and the store/barrier/publication order. All 29 peer
mutations must be refused. `--frame-baseline` builds the independent frame-only
x86 baseline with its separate fixed source pins.

`matched-atomic-fresh-kernel-retain.v` derives the fresh format-2 consumer
receipt from the complete atomic build-03 bundle after its strict audit passes.
The derivative retains the original audit reference; consumers must recheck the
complete original. The [fresh retention report](matched-atomic-fresh-kernel-check.md)
records the source revision, checksums and external evidence location. Guest,
allocation/performance and production integration gates remain separate.

`matched-kernel-retain.v` and [its report](matched-kernel-check.md) retain the
historical atomic-v3 build-02 profile. Its later complete metadata audit refused;
the fresh profile does not requalify that bundle. A derivative or a content
match does not replace a complete bundle's metadata audit.
