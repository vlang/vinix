# Production slab sampler build compatibility

The observer, parser controls and report formatter now use explicit `u64`/`i64`
libc sizes/counts on the supported LP64 hosts and targets. Deprecated
`usize`/`isize` declarations and casts prevented production compilation with
the current V compiler. Using explicit widths also retains compatibility with
the previously qualified compiler, which predates `uint`. The sampler borrows
`os`'s existing `setvbuf` declaration instead of redeclaring its compiler-native
size type. No parser, arithmetic, workload, signal, snapshot, cleanup or
qualification policy changes are included.

The ARM sampler links musl's pthread implementations from libc. Its explicit
link recipe no longer requests the optional empty `libpthread.a` stub absent
from the selected SDK. `pthread_create` and `pthread_join` are present in that
libc, and the complete static link resolves the sampler's real thread probes.
Math and all strict format/pointer diagnostics remain enabled.

The maintained `heap-build-check.v` runs the existing parser/reader and complete
transcript controls in normal and production builds. The public host-test front
now runs this gate, so deprecated aliases cannot silently break production while
normal host tests pass. It retains argv, output, statuses, compiler/source pins
and the fresh reader fixtures outside Git; compiler fallback is disabled.
Both profiles pass all 373 parser/reader and 57 transcript checks. The expanded
public suite, actual V report test file and ARM adapter's 18 host controls pass;
the public suite retains its 100-PTY-owner flat-descriptor check.

Both production samplers generate and link with the verified compiler from the
[original compiler qualification](../tests/desktop-perf/heap-compiler.md):
`/Users/alex/Library/Caches/vinix-codex/section14/perf-heap-producer-compiler-20261105-02/toolchain/v-next`,
SHA-256 `53debcfe66952ba952d64b2b94dbb2408bed6992453d1ac6bad5889e4bd1ec7e`.
The unchanged original verifier checks its complete derived sources and parent
before and after use. Strict Clang 23.1.5 links select the existing ARM
`tidfault-20261015/sdk` and x86-64 musl-cross 14.2.0 inputs. Readelf confirms
little-endian static ELF64 executables for the intended machines, without
interpreter or dynamic dependencies. The compiler/SDK environment is explicitly
selected; no hermetic toolchain claim is made.

Before/after observer sources, rebuilt with the same selected tools and final
link recipes, produce **byte-identical complete ELFs** on both architectures:

| Target | Baseline and corrected ELF SHA-256 |
| --- | --- |
| AArch64 | `ecc79885b6b9e2189bba9f971e994725a5b18f6fafbfab936bcfc44309b15411` |
| x86-64 | `2605e5e5418210d94ed8b27811dfd0945ca181aba4fc31426a08955a73f537c5` |

The complete generated C differs only in equivalent LP64 type spellings and
compiler-generated local/path identifiers. The legacy C probe bytes remain
unchanged. Source baseline is `efe9589db5444a6697b0096cfb672ea307d088b2`, with
the exact corrected sources retained in the bundle. No kernel lifetime changes
or fresh guest performance measurements are introduced.

The frozen current `cbfc1be` compiler now generates both production targets from
the corrected sources. Its C still fails the retained strict format check on
the previously recorded compiler-generated printf precision defect; the
verified compiler above includes that narrowly qualified correction. Format and
pointer warning errors remain enabled; generated C is never patched. The full
ARM 16 KiB/18-class integration, native performance runs, selected x86 runtime's
missing curl and inherited kernel allocation allowances remain separate open gates. The existing
4 KiB/14-class schema and historical evidence/checkers are unchanged.

The subsequent [explicit ARM schema qualification](linux-performance-arm-schema.md)
adds a separately selected 16 KiB/eighteen-class profile, preserving the default
legacy contract and qualifying native reader cleanup on both architectures.

Complete evidence: `/Users/alex/.cache/vx-sb-1115/bundle`, archived at
`/Users/alex/.cache/vx-sb-1115.tar.gz`, SHA-256
`75b6bd6683fc067fa7b5a3b4cb8baaf61a4b28bee26b2fc8806051f155fe574f`.
The maintained `swift-staging-archive.v check-archive-root` compares all decoded
archive bytes, paths, types, modes and literal links with the retained bundle.
Failed attempts remain present, including shared-disk ENOSPC failures, a refused
older-compiler `uint` attempt and an initial frozen-compiler test reporter setup
failure. The passing report test uses a private copy of its unchanged reporter
sources. Originals and historical qualification bundles remain intact.
