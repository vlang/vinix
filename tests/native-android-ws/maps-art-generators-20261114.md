# V replacements for ART build helpers

Continuation of 6f9da880b. `art-source-generators.v` and the `artgenerators`
module replace three Python build helpers in the retained ART source:
Makefile discovery, assembly constant extraction and enum stream operators.
No Python was run or modified. ART's ARM64 interpreter template generator and
the Makefile integration remain prerequisites before building the runtime.
Google sign-in remains unresolved; the imageless-compilation candidate has
not been built or deployed.

```text
art-source-generators find-leaves [--mindepth=N] [--prune=NAME] DIR... NAME
art-source-generators asm-header COMPILER_ASSEMBLY
art-source-generators operators LOCAL HEADER...
art-source-generators --self-test FRESH_OUTPUT
art-source-generators check-art-inputs MAKE_ROOT HEADER_ROOT FRESH_OUTPUT
```

The replacements follow the original line-oriented algorithms from ART source
e78bf68917bcaaf58fef3960cd88793b3b7f39cc. Discovery sorts and deduplicates paths,
stops below a discovered file, supports depth/pruning and follows directory
aliases. It rejects cycles and excessive depth instead of recursing forever.
Assembly constants sort the original decimal tuples before formatting hex,
including signed minima and negative compiler spellings of unsigned values.
Malformed markers, out-of-range values and missing constants fail. Enum
generation preserves namespaces, enclosing classes, scoped enum handling,
literal values, aliases, private markers and alternate text. Anonymous enums
are skipped as in the original helper. Unsupported expressions fail before
any output is printed. Generated comments identify the V replacement.

Focused checks use independent expected values for sorting, all three
immediate prefixes, signed minima, unsigned maxima and wrapping. They also
compile a C++ inline-assembly fixture, then parse the actual emitted markers.
Another fixture compiles and executes generated stream operators, checking
their exact stream output for nested/scoped enums, aliases, alternate text
and unknown unscoped values. Directory fixtures cover duplicate roots,
pruning, minimum depth, aliases, cycles and invalid arguments.

The source check reads the five original Android.mk operator-header lists,
generates each output separately and retains input/output SHA256 records.
All 50 headers passed: runtime 31, libartbase 3, libdexfile 6, compiler 7 and
dex2oat 3. These are source-generation checks; the complete ART libraries
still require native compilation and ARM regression. Generated C++, assembly,
executables and inventories remain external.

Available latest V was V 0.5.2 39e0e79 at `/Users/alex/code/v/v`, SHA256
6bfbbc9bb51703846e68c0733605d848e8e8f09ec8e73be0d1497f457e6fe922.
The final r6 build passed in 1017 ms with sampled RSS 306167808 bytes. Build,
focused checks and the 50-header check returned 0/0 with complete cleanup
under the original caps: RSS 629145600, wall 300000 ms, free reserve
1073741824, growth 536870912 and output 4194304 bytes. Earlier r2 compilation
failed on nested Option/Result handling; the first source check exposed the
anonymous-enum case. Their failed evidence remains separate.

Artifacts are under `/Users/alex/.local/state/vinix/android/`:

| Artifact | SHA256 |
| --- | --- |
| art-generators-tools-20261114-r6/art-source-generators | fb553438a69bebfc01b334537e72a209eeb57c2348b9fc225674e3beb7c1fa51 |
| art-generators-checks-20261114-r6.json | e4013fffe45cb2664f17da01331bc5bfcf0480759a4def30f7d6b18383d5a45d |
| art-generators-source-checks-20261114-r3/inputs.json | 6771de3616bac64adfed62d0c11524b8aa5edf80047e4bdec50f7d2a5115e763 |

Each generated root has a sibling guard log/receipt. Retained source selections
are `art-generator-inputs-20261114-r1`, `art-header-inputs-20261114-r1` and
`art-build-make-inputs-20261114-r1`; the original complete archive remains in
`art-alpine-inputs-20261114-r1/art-source.tar.gz`. No VM was started.
