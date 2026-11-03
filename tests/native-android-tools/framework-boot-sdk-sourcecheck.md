# Framework boot-classpath SDK resource-loader companion

The runtime must define Android platform classes from ART's bootstrap tier so
isolated module loaders can resolve them. The resource-only framework-res.apk
remains on the ordinary system class path, which ATLPaths also uses to discover
its runtime paths. This companion preserves resource discovery after the
framework implementation moves to the boot class path.

Exactly two existing method bodies change: Resources.getSystem() and
ATLLoadedApp.loadFromPath(String,String,String). Each replaces its one
const-class/Class.getClassLoader pair with the static
ClassLoader.getSystemClassLoader getter and retains the original result
register. The former supplies that loader to AssetManager; the latter supplies
it as the parent of the application's PathClassLoader. No field, method, class,
native declaration, resource path, package parsing or signature check is added
or removed.

The provider is `androidtools/framework_boot_classpath.v`; its directory entry
validates both complete inputs before writing either transformed class. Source
qualification uses `framework-boot-sdk-sourcecheck.v` and
`frameworkbootcheck/main.v`. The focused checker independently records both
complete original method bodies and compares every instruction, register,
annotation, branch and catch scope against explicit expected replacements.
Branch-label spellings are normalized to instruction positions, including
references inside catch braces. Equivalent .locals/.registers directives are
accepted with the correct static parameter count. Quoted strings and field
descriptor colons remain exact.

All other original methods and class/field metadata must remain unchanged.
Raw source permits only the cleared const-class line and changed call line;
source-format controls cover .locals, CRLF, a missing final newline and tab
indentation. Atomic refusal controls corrupt either input, including the second
class after the first has been validated, and require both files to remain
byte-identical. A missing second file is also checked. Separate mutation
controls reject changed native declarations, methods, fields, flags, result
registers, configuration access, monitor behavior, branches, catch ranges,
annotations and certificate checks.

The driver freezes its provider/checker inputs and captures the actual compiler
input closure, assembles exactly the two complete classes for API 28, checks
their first canonical disassembly, then reassembles and checks a stable second
DEX roundtrip. The 2,117-class SDK membership and both classes' inclusion in the
70-class native input set are checked before execution. A fresh coupled native
producer, complete SDK delta audit and live ARM/runtime behavior remain
separate gates. This source proof does not establish resource rendering,
Cronet initialization, GMS stability, Maps or authentication.

Independent source review passed before execution. The first guarded host proof
passed all 41 atomic prewrite refusals, 25 preservation controls, eight format
positives, both complete target-method oracles and stable second API-28 DEX
roundtrips. Both classes preserve their existing 81/23 method membership and
all unrelated bodies/metadata. No compiler or Java phase overlapped another
task-owned compiler, Java or VM phase.

The recorded source parent is `a8ceeefc030d939fb72cb1a1096cb01355bb0b9c`.
The complete exact WebView SDK remains the baseline, manifest
`c79d421bd385777aefd00b0be85a287af7907b1bb6dd55244d7546eb99ea958a` and JAR
`0e5e2632bc64ad9d548379491c59ed4e8a91d42fcfa6677b75aae4798dfeb7a9`.
Frozen/current source identities match:

| Source | SHA-256 |
| --- | --- |
| Provider | `74123ef0d58ebf866287c7b81649bd02cc7f971cc8f8275976537fda39a6417f` |
| Focused checker | `df2557b7ad5d0a6c03004254311f6fcd3d6b4d59500cf1bf41e1d13d40c12041` |
| Proof driver | `b3cc8b6e72df140713f3bb9c6bba5fb50b996ae85c3b5085039d2175354feec7` |

All generated evidence remains outside Git below
`S=/Users/alex/.local/state/vinix/android`, in
`S/framework-boot-sdk-source-check-2026-11-03-r1` and sibling
`S/framework-boot-sdk-source-controls-2026-11-03-r1`. The proof receipt hashes
to `3a9b2f6ae18296f80c66d37b24b21bc6388dd70d23565265472967c506ea80fc`.
It retains source copies, the actual 142-entry compiler-input listing/copies,
input hashes and final readbacks, selected complete classes and all DEX results.
The compiler's kept generated C was copied from its unique temporary path into
the controls root as `checker-generated.c`; both copies hash to
`49c29c01f20c85cf8f6497d2e7794b2bcadb972715a3155d2a6634265c06906d`,
with the equality readback preserved separately.

Driver compilation took 1.966 guard seconds at sampled/detailed RSS
314,982,400/274,694,144 bytes and 1,425,408 bytes observed shared growth.
The complete proof took 10.067 seconds at sampled/detailed RSS
229,605,376/134,004,736 bytes and 14,544,896 bytes observed growth. Both
guards/children exited zero, reasons are empty, cleanup is complete and detailed
logs report zero swaps. Limits remained 600 MiB aggregate sampled RSS,
300 seconds, 512 MiB shared-volume growth, 1 GiB reserve, 4 MiB output and
file-size cap 16777216. Full SDK production, native coupling, image admission
and the old/new ARM behavior checks remain separate gates.
