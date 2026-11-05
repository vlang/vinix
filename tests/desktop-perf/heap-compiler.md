# Derived C compiler for the heap observer

The independent compiler derivation, updated host controls and both strict
static target links passed; see [the qualification report](heap-qualification.md).
Earlier results retain their original source and scope.

The strict ARM link in
`/Users/alex/Library/Caches/vinix-codex/section14/perf-heap-producer-target-build-20261104-02`
failed because the selected compiler emits a 64-bit V string length as a native
printf precision. The maintained [preparer](heap-compiler-prepare.v) changes
exactly one V generator emission:

```v
g.writeln('\tv3_eprintf("%.*s\\n", s.len, (char*)s.str);')
```

to:

```v
g.writeln('\tv3_eprintf("%.*s\\n", (int)s.len, (char*)s.str);')
```

The native precision argument is then an int. Format and pointer diagnostics
remain enabled for the regenerated target links. Generated C is never patched.

The immutable parent is
`/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain`.
Its executable SHA-256 is
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`;
the complete literal-tree manifest is
`ff729f3d39ad09b0401c2f1e08e69784db5c4781117c1f1480a59ee4ffdd39e9`.
The preparer checks all 4,636 entries before and after: names, bytes, modes,
uid/gid, device/inode and mtime/ctime. It refuses links and special files.
Each copied ordinary file must have one link and a different identity from its
parent. The copied tree must initially equal the entire parent.

The parent export lacks `v.bench`. Historical commit
`257b514a303f4d302ed23bbac1d51a2ca9624a66` in
`/Users/alex/code/v` contains matching compiler anchors:

| Source | SHA-256 |
| --- | --- |
| `vlib/v/driver/driver.v` | `7112d951708a9114b0e35c6045b87ff991eb85104740db6249c109f84c29cade` |
| `vlib/v/gen/c/cleanc.v` | `55481f6bde34d3cc79458afe7b7c40fbb9716499f5eac29bafd40d00058ee248` |
| `vlib/v/v.v` | `e580581a4508eb93d31bb7d560e2ae8f6ede2b4ae2ddd66a74dd2e8a2fdb2e1b` |

The helper exports only that commit's complete ten-file bench tree,
`2aa3a53eeac45a276a31f54b96bad192446a7c82`,
and verifies its entry set and every file hash. These 22,816 bytes are an explicit
source addition, separate from the single generator correction. Existing bench
C/header files are exported unchanged. Its memory watchdog remains enabled.
The final source comparison permits exactly this addition and the precision
change; it refuses other differences. Matching anchors and direct import
directories do not establish a complete transitive compiler source closure.
After bootstrap, `verify STATE COMPILER_SHA256` repeats the source comparison,
permits only the pinned new `v-next` binary, and rechecks the complete parent.

The successful independent derivation is retained at
`/Users/alex/Library/Caches/vinix-codex/section14/perf-heap-producer-compiler-20261105-02`.
The byte-identical copied parent compiler built the patched `vlib/v/v.v` into
`bootstrap-output/v-next`; an independent copy of only that executable entered
`toolchain/v-next`. Its generated C remains outside the exact derived tree.
All compiler selectors and the explicit library path point into the copied tree.
This entry builds a C-only compiler. The retained ordinary bootstrap command
shows the parent's default diagnostic-suppression flags. It establishes a
source-bound bootstrap, while the separate target C invocations enforce strict
pointer and format diagnostics without suppressions or generated-C edits.

The external plan is
`/Users/alex/Library/Caches/vinix-codex/section14/perf-heap-producer-compiler-plan-20261104-01.json`.
It proposes a 768 MiB dual allocated/apparent ceiling, including the worktree and
all prior A/B states, with 128 MiB reserved inside that ceiling; 2 GiB admission
and 1 GiB endpoint free-space floors; 300-second preparation and 900-second
compiler-build deadlines. These are endpoint disk bounds, not an RSS or
continuous quota claim. No compiler memory limit is disabled.

Qualification passed new normal/production 373 parser/reader controls and
57 full-transcript controls, rebuilt generation helpers, both strict static
target links and independent generated-C lifetime/ABI review. Passing cursor
state by value avoids the earlier fixed-array heap promotion. The native i32
signal handler and proof output after both snapshots were reviewed. The unchanged legacy C remains SHA-256
`2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771`.
Changed adapter checks, images, guests and full kernel memory qualification
remain separate gates. Preserve every failed attempt and all original checkers.
