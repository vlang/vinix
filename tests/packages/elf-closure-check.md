# Fixed-profile ELF dependency admission

The SQLite and FFmpeg catalog publishers validate the complete packaged
`DT_NEEDED` graph before publishing a catalog lock. This supplements the existing
ELF target/segment/interpreter check; the generic native profile remains a
structural check for static applications.

For each Linux application, admission uses only that application's files and its
declared fixed runtime. The search directories match `linux-runner`:
`APP/lib`, `APP/usr/lib`, `RUNTIME/lib`, and `RUNTIME/usr/lib`. A missing direct or
transitive library refuses publication. Two different content-addressed objects
competing for the same needed basename or loaded SONAME also refuse publication.
This publisher policy deliberately rejects ambiguity even when the loader would
choose the first match. Copies of the same object are allowed, and the packaged
musl loader and `libc.so` must be the same SHA-256 object.

PIE/shared images require one file-backed, terminated `PT_DYNAMIC` table and a
bounded `DT_STRTAB`. The static runner must have no dynamic table. Limits are 128
images, 256 needed entries per image, a 64 KiB dynamic table, 4 MiB per string
table, and 16 MiB total string storage. Conflicting virtual-to-file mappings,
invalid names, unbounded strings, duplicate metadata tags, and auxiliary/filter
dependencies refuse admission. Section headers are not required.

The current fixed recipes use files immediately under `bin/`, `lib/`, and
`usr/lib/`. Accepted RPATH/RUNPATH entries are explicit `$ORIGIN` or `${ORIGIN}`
forms that resolve from those locations to the same packaged library directories.
Empty entries, ambient/absolute paths, arbitrary relative paths, and escapes are
refused. This is a bounded policy for the two fixed publishers, not a general
ELF loader or a promise about instruction/ABI compatibility, symbol versions,
`dlopen`, plugins, or guest execution. All included library objects are checked,
including libraries not reached by the entrypoint.

## Retained host qualification, 2026-10-22

[The receipt](results/2026-10-22/elf-closure-host.json) binds the exact parser,
profile hooks, fixture/test sources, heap tracker, compiler/tool binaries, and
real SQLite/FFmpeg input-file SHA-256 identities. Each replay input was checked
against the admitted catalog file identity. [The transcript](results/2026-10-22/elf-closure-host.txt)
contains the command options and retained check output.

- 64 dependency, metadata, mapping, search-path, and alias cases across AArch64
  and x86_64; 2,048 repeated parser/graph checks and 256 inventory checks retained
  zero tracked bytes/allocations with stable descriptors. Normal and ASan/UBSan
  builds passed.
- The complete SQLite and FFmpeg publisher ownership suites passed, including
  repeated missing-`DT_NEEDED` refusal, absent output, staging cleanup, exact
  restored canonical retry, source preservation, and stable descriptors under
  a 32-descriptor limit. The new refusal paths also passed ASan/UBSan.
- Real musl cross-compiled PIE/shared/static inputs produced eight CLI refusals
  (missing direct/transitive, conflicting SONAME, and ambient search path on each
  architecture), each followed by a successful exact restored retry. Both
  packaged `$ORIGIN/../lib` cases passed.
- Existing structural unit/ownership checks and all 20 malformed-ELF CLI
  refusals/restored retries passed. Both profile regression suites passed.
- Both architectures' actual reviewed SQLite and FFmpeg payloads were accepted.
  Their historical canonical catalog hashes were unchanged:
  SQLite `f4a5cd471b7801fd8391c22fdcbd1ebb77ff58b3208743a41b539325d709285b`;
  FFmpeg `c297cb8500a8fdea626bcd0fadfa0e94266bdc08f54435f83ba581674c8a9694`.
  These payloads need the already packaged `libc.so`; no new aliases were added.

The common synthetic structural fixtures now contain a genuine empty dynamic
table for PIE/shared images. Their ownership-test catalog golden hashes changed
for that reason; real payload catalogs did not change.

## Reproduce

From the repository root, use the reviewed V compiler with an explicit host C
compiler. Do not use `-prod` for these assertion-based checks. The real-ELF driver
also enforces this restriction.

```sh
V=/path/to/reviewed/v
OUT=/new/qualification/tools
mkdir -p "$OUT"
"$V" -cc /usr/bin/cc -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' -o "$OUT/vinix-package" tools/packages
"$V" -cc /usr/bin/cc -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' -o "$OUT/elf-closure-check" \
  tests/packages/elf-closure-check.v
"$OUT/elf-closure-check" "$OUT/vinix-package" /new/qualification/real \
  /reviewed/sqlite-roots /reviewed/sqlite-catalog.json \
  /reviewed/ffmpeg-roots /reviewed/ffmpeg-catalog.json
```

`CC_AARCH64` and `CC_X86_64` may select the musl cross compilers; defaults are
`aarch64-linux-musl-gcc` and `x86_64-linux-musl-gcc`. Omit all four replay arguments
to run only newly linked qualification inputs. The output directory must not
exist. The generated C programs are test payloads built by the V driver.

Build `tools/packages/pkgcore/elf_closure_test.v` and both
`{sqlite,ffmpeg}_builder_ownership_test.v` with the same options plus
`-d track_heap`. Run each binary directly. FFmpeg's suite also requires
`VINIX_PROFILE_EXPORT_SOURCE` pointing to the reviewed FFmpeg 8.0.1 source
archive. Add `-cflags '-fsanitize=address,undefined -fno-omit-frame-pointer'` and
`-ldflags '-fsanitize=address,undefined'` for the sanitizer build; run with
`ASAN_OPTIONS=detect_leaks=0` because allocation retention is measured explicitly
by the repository heap tracker.
