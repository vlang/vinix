# Package signing dependency

This is the MIT-licensed V Ed25519 implementation from standard-library commit
`826e96f56ca12fcb8fd02dfd6edf1551008e62a8`, retained under a package-local namespace.
[provenance.json](provenance.json) records immutable Git blob IDs and before/after
SHA-256 hashes; [LICENSE](LICENSE) retains the upstream copyright and license.
Package staging retains this notice at
`/usr/share/licenses/vinix-packages/ed25519-MIT.txt` in binary releases.

The only operational adaptation replaces the private variadic point-initialization
check with one value check per point, preserving its order and predicate. The
qualified compiler's variadic lowering copied a mutable receiver pointer as a
160-byte point value and caused an ASan stack-buffer-overflow during key generation.
The adapted helper passes values through the ordinary argument conversion; calls
with two points become two checks, and slice expansion becomes iteration.
Field/scalar arithmetic, point encoding, nonce derivation and signature layout
are retained from the pinned source.

The package publisher and consumer import this dependency rather than whichever
Ed25519 implementation happens to accompany the build compiler. No demonstration
key is enrolled by this module or its test fixtures. Standard-library SHA-512,
entropy, integer and synchronization dependencies remain part of the toolchain
qualification closure.

Reproduce or check the generated sources from a V checkout containing the pinned
commit, without reading dirty checkout files or fetching from the network:

```sh
v -no-skip-unused -o /tmp/vendor-signing tools/packages/vendor-signing.v
/tmp/vendor-signing --check /path/to/v-checkout
# --write regenerates the nine pinned production/license files and provenance.
```

Updates require source review and renewed reference-vector, sanitizer, package
integration and both-architecture guest qualification. The package signing format
remains SDK-1 Ed25519 over the exact repository index bytes.
