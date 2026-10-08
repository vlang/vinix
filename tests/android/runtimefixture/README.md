This V fixture controller owns the complete RuntimeTests and BionicTests groups
from the independent Android runtime fixture at source commit
b13d145ab1c7e4b852e1920ea653025e36af8a5f. The frozen original file SHA256 is
b19cfd6223d7cf5d5ef7a888473cb1564d892821ccd4e6c81c49ef2c43dd58de.

All 17 original case names, mutations and assertions remain: native payload
and optional JAR installation, exact hashes/modes, old hardlink preservation,
ELF architecture/alignment, omitted and unexpected files, path validation,
symlink escapes, source changes, complete destination preflight and Bionic
soname aliases. Contexts and each partial setup retire their own scratch tree.
The three native ELF builders match complete original bytes; JSON comparisons
ignore object key order. The calling unittest entry retains its original names
and filters through a synchronous compatibility binding.

runtime-binding.py imports and calls the public production runtime API and
marshals its results/errors/constants. It retains no test algorithm. The
unmodified public API continues to exercise the maintained V production core.
The shared ELF/DEX/ZIP/payload helpers and the remaining nine ATL cases stay
in the Python fixture until that group is ported and receive no retirement
credit. The fixturehost and hosttest links reuse qualified process/stdio tools.

Qualification runs the full frozen 26-test Python corpus and the combined
17-native-plus-nine-original entry on ARM64 and x86_64, and all native cases
with ASan/UBSan. These are host filesystem and controller checks; no Android
application, production cross compiler, kernel or guest is executed.

The complete ten-case musl fixture from source commit
f75ef88bbf2c74347adec79a26d910d4b562ee7a also runs in V. Its original full
file SHA256 is b02ac26ff056e6e30131bde1ea0284de6c709cb41695391fb848c53c95b7e1b5.
It preserves all receipt, source patch, loader alias, tampering, ELF, symlink,
missing-file and malformed-JSON assertions. Each musl invocation has a waiting
parent that owns the entire scratch tree, including assertion-failure cleanup.
The original copytree/copy2 primitives and public musl API remain synchronous
standard-library bindings and receive no algorithm retirement credit.
The standalone musl-runtime-test.v entry and original unittest method names
exercise the same native cases, qualified against the full frozen corpus on
both host architectures and with ASan/UBSan.
