# Local runtime source evidence admission

`pkgprotocol.decode_local_source_offer` and
`wineadapter.admit_local_source_offer` accept evidence for an explicitly local
runtime experiment. The only admitted state is format 1,
`status: "local-qualification-only"`, with `source_closure_complete: false`.
Neither API authorizes redistribution or establishes complete corresponding
source. In particular, pinned recipes, source fragments and publisher notices
must not be described as a complete runtime source distribution.

The decoder rejects unknown, duplicate and escaped-duplicate fields, incorrect
types, trailing input, invalid runtime/version/architecture identities and
unsafe artifact names. Metadata is limited to 256 KiB and 256 unique flat files.
Artifact digests are lowercase SHA-256; source/recipe/patch provenance requires
an HTTPS reference. Only notices/licenses may use `local:publisher`. References
are recorded, not fetched or admitted as remote content by this parser.
Decoded fields are independently owned, and `close()` is repeatable.

Filesystem admission walks an absolute directory without directory aliases,
opens each file relative to its captured descriptor with `O_NOFOLLOW`, and
requires ordinary, nonempty, single-link files. Each artifact is limited to
16 MiB and the total to 64 MiB. It verifies every digest, the exact inventory,
runtime/version/host identity, both `runtime-LICENSE.txt` and
`application-LICENSE.txt` notice entries, final directory identity and unchanged
manifest bytes. Inventory enumeration uses `fdopendir` on the captured
directory, including the maximum 257-entry manifest-plus-artifact inventory.
Temporary digest buffers, parsed fields and descriptors are retired on both
acceptance and refusal.

This is not an atomic snapshot of files that another process can modify.
Publication callers must capture the admitted evidence and recheck their
captured inputs before publishing or using them. Production corresponding-source
qualification needs a separate contract.

On 2026-10-23 the assertion-enabled host runs passed normally, with tracked
manual-free V allocations, and with ASan/UBSan. The tracked runs measured:

- 1,000 successful decodes/double closes and each of 43 parser refusal paths:
  zero retained V bytes.
- 100 maximum-size decode/growth, duplicate and over-count cycles: zero retained
  V bytes.
- 100 actual filesystem admissions/double closes and 300 identity refusals:
  zero retained V bytes and unchanged lowest available descriptor.
- Every changed-file, extra-entry, directory/manifest/artifact link, non-file,
  empty/oversized file and missing-notice refusal, each repeated 32 times:
  zero retained V bytes and unchanged lowest available descriptor.
- Eight admissions of all 256 real artifacts plus the manifest: zero retained
  V bytes and unchanged lowest available descriptor.

The sanitizer runs use `ASAN_OPTIONS=detect_leaks=0`; their evidence is address
and undefined-behavior checking. The allocation measurement concerns the
tracked V allocator, not all libc allocations or guest kernel memory. An
independent peer reviewed new ownership and descriptor lifetimes before commit.

From a checkout containing the Wine adapter, use the pinned package compiler.
Omit `-prod` so assertions execute:

```sh
export V="$PWD/build/package-https-runtime-work/toolchain/v"
export VEXE="$V" V_MACOS_V3_CALLER_VEXE="$V"
export V_MACOS_V3_CALLER_VEXE_PRESENT=1 V_MACOS_V3_CALLER_VCHILD_PRESENT=0
export V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1
"$V" -backend c -cc clang -nocache -gc none -manualfree -no-skip-unused -keepc -d track_heap \
  -path '@vlib|.|tools/accounts|@vmodules' \
  -o build/local-source-protocol tools/packages/pkgprotocol/source_offer_test.v
build/local-source-protocol
"$V" -backend c -cc clang -nocache -gc none -manualfree -no-skip-unused -keepc -d track_heap \
  -path '@vlib|.|tools/accounts|@vmodules' \
  -o build/local-source-admission tools/packages/wineadapter/source_offer_test.v
build/local-source-admission
```

Repeat those commands without `-d track_heap` for normal tests. For sanitizers,
omit that define, add both
`-cflags '-fsanitize=address,undefined -fno-omit-frame-pointer'` and
`-ldflags '-fsanitize=address,undefined'`, and run the resulting binaries with
`ASAN_OPTIONS=detect_leaks=0`.
