# Build ABI arrays fixture

The one-class API-28 fixture checks the real aarch64 process against Build's
all-ABI, 64-bit and 32-bit String arrays. It calls Process.is64Bit and reads
System.getProperty("os.arch"), prints the actual values, then requires true and
aarch64. Those observations are pending ARM execution; source-derived ELF/uname
provenance does not stand in for a printed runtime measurement.

Reflection checks that SUPPORTED_ABIS, SUPPORTED_64_BIT_ABIS and
SUPPORTED_32_BIT_ABIS are public static final fields declared by Build with exact
String[] type. Actual field reads require ALL and 64-bit lists to contain exactly
arm64-v8a in order, with an empty 32-bit list. CPU_ABI must match the primary ABI,
CPU_ABI2 must be empty, and the five corresponding existing property values must
agree. Empty secondary/list properties must be present rather than returning a
fallback marker. Repeated reads must retain each field's array identity; all
three arrays must be distinct objects.

The fixture temporarily changes the public ALL array's first element, proves the
64-bit array is unaffected, restores it, then changes the 64-bit array's element
and proves ALL, CPU_ABI and the real capability property remain unaffected.
Finally cleanup restores both exact original elements on success and failure.
An original assertion failure is retained if cleanup also fails. Baseline checks
run again after restoration. No static final array field is reassigned.

The private static getStringList(String key, String separator) helper is inspected
and invoked through reflection. Only the unique fixture key
`vinix.fixture.build_abis.list` is changed through reflection of the existing
process-local Properties object. No new SystemProperties setter is supplied, and
no real ro.product.cpu capability property, os.arch value or SDK state is changed.
The exact prior key presence and Object are saved before the protected test range
and restored and checked in finally cleanup.

The six property states exercise missing and empty values, comma order, leading
and internal empty entries with trailing-empty removal, retained whitespace and
a semicolon separator. Expected arrays are explicit fixtures, not a second
split implementation. Every state is read twice and requires distinct arrays,
including empty arrays. For nonempty arrays, mutating one returned value must not
affect another result or a fresh helper query. The public ABI baseline is checked
again after custom-property restoration. These helper controls do not turn
synthetic strings into advertised runtime capabilities.

The fixture supplies only org.vinix.bootstrap.Main, has no worker, runtime path,
UID requirement or platform stub, and retains minSdk 28. All assertions and cleanup
precede the success marker. It does not claim 32-bit execution, Google module
completion, Maps rendering, an account or authentication.

The source generators are `buildabisfixture/main.v` and
`buildabisfixture/sources.v`. Independent source/register/exception-flow review
passed at hashes `6965f4f49a996b4b430810fd5ef54ef5e6f27997246308a24b2f74a57e82063d`
and `e614171cf9a2c34b68946680ae705408655e7318114df68c02a852bf19814737`.

The first host builder and signed production attempts passed. Complete frozen
input closure, fresh error-free API-28 assembly/reassembly, two matching canonical
trees with exactly one application class, v3 signing with exactly one signer,
minSdk 28 and exact signed-DEX extraction/readback all passed. The immutable
receipt records source revision `0d6272593dd7ef76d61853ac56a498b29c8615de`.
Complete generated evidence remains outside Git under
`S/build-abis-fixture-2026-11-02-r1` and
`S/build-abis-fixture-controls-2026-11-02-r1`, where
`S=/Users/alex/.local/state/vinix/android`. All earlier closed bundles stay intact.

| Qualified artifact | SHA-256 |
| --- | --- |
| Signed probe.apk | `2036c430d632f7fbca0cfbbe2c0c975b146e80686934fc482ae59ab9662b439a` |
| Build receipt | `1fc189dbcbd26ad3247d8f0d1926e33e25ab63e82b2716310c2f94a1cef89705` |
| Production / signed-extracted DEX | `5d37b519f530f42994a334aa5d9c2fd1a6c2af5457d9e23e89e7720b18cc0b7b` |
| Roundtrip DEX | `b1249db1f82eb0f569385bf951948018a4e139e331bab0aad286c99245d8ce8b` |
| Both canonical Main classes | `2f13d8914c2cd5b33a0572f279ccc5786d246610f2f36f7c06a73323379d83f3` |

The production and roundtrip DEX hashes differ; the complete canonical trees are
equal. Streaming classes.dex directly from the signed APK reproduces the
production hash. Current and frozen sources still match the hashes above.
Framework manifest/build/JAR/DEX were independently rehashed before and after
production; the paired JAR from
`S/combined-account-webview-build-abis-framework-2026-11-02-r1` is
`251753fdee85367880a9b0c48d1cb0058fd17a819e4651a8dc29f232673f531f`.

Both guard and child exits were zero, reasons empty and cleanup complete. Compile
took 1.572 seconds, sampled aggregate RSS 302,710,784 bytes, detailed maximum
353,419,264 bytes and observed growth 1,310,720 bytes. Production took 12.455
seconds, sampled aggregate RSS 106,004,480 bytes, detailed maximum 96,911,360 bytes
and growth 75,173,888 bytes. Detailed logs report zero swaps. Limits stayed 600 MiB
aggregate RSS, 300 seconds, 512 MiB observed growth, 1 GiB reserve, 4 MiB output and
shell file-size cap 16777216. The compiler/Java lane was released after actual
production completion. Host qualification does not establish ART execution or
architecture observations; the signed fixture requires its first ARM run.

The exact success marker is:

```text
BUILD-ABIS-PASS measured-arm64 public-static-final ordered-arrays empty-32 independent-mutable stable-fields fresh-helper custom-property-restored
```
