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
The fixturehost and hosttest links reuse qualified process/stdio tools. The
remaining independent ATL group and its shared builders are now native below.

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

The nine complete BootclasspathTests cases and their DEX builders also run in
V, frozen at source commit edb0b66cfcd29b150f36f246754130239548d6df and full
file SHA256 414a3f237e77ecde182445ef6645f5636773e30b309c06ea4cc179cf5c98c4a7.
The native corpus keeps every malformed DEX, required-class subset, preserved
resource, deterministic JAR, duplicate-class, cached-download, strict-number
and compiler/source receipt assertion. Complete original DEX bytes and full
many-class map hashes/sizes are durable builder vectors. ZIP read/write,
typed Python arguments and the request-local subprocess recorder are narrow
standard-library bindings; production bootclasspath policy remains unchanged
and receives no retirement credit here. A parent owns all scratch files even
after a failed native assertion. ARM64, x86_64 and sanitizer runs compare the
whole original corpus and preserve compatibility method names/filters.
No Java compiler, network download, Android application or guest is executed.

The remaining nine AtlTests cases are native at source commit
1b8efef098379574776d4f950dba19a60aff9d39 and frozen full file SHA256
221b257173b4980ec0be6364aa26de023a8da4720d6430df1b32f22b2d4eb0f6.
They preserve source/compiler/dependency receipt mutations, exact required
components, ELF ABI and soname coherence, JAR bootstrap/class receipts,
resources/font maps, old hardlink preservation and complete installed bytes.
Both original production build.stage workflows run too: cache reuse, stale
framework repair, input changes and retaining prior staging after invalid input.
All ELF and DEX builders match complete bytes from the frozen original.

Generic unittest patch descriptors, Namespace conversion, public Python API
calls and ZIP primitives remain standard-library bindings without fixture
policy. V owns mocked compiler command effects, ELF output, fixture generation
and every original assertion. ExitStack restores every request-local mock;
saved subprocess.run executes synchronous callback children outside the mocked
command route. A native parent owns scratch trees even after assertion failure.
ARM64 and x86_64 qualification runs both the frozen original full 26 cases and
the original remaining nine; all 26 native compatibility cases, all nine direct
ATL cases and the existing boot/musl groups pass with ASan/UBSan too. A forced
post-setup assertion proves parent retirement after a complete case tree exists.
These are host API/filesystem workflows with original compiler mocks; no real
Java compiler, Android app, cross compiler, kernel build or guest is claimed.
