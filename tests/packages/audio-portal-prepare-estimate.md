# Native audio preparation size forecast

`audio-portal-prepare-estimate.v PLAN PLAN_SHA256 NEW_REPORT` measures the
capture selection of the checksum-pinned AArch64 audio producer. It reads the
reviewed Plan and selected originals, requires fresh preparation and an empty
content store, and writes one exclusive mode-0600 report. No compiler, producer
or guest is executed by the estimator.

Captured input paths count separately. Only content-store objects deduplicate
by SHA-256. Independent source/runtime copies, traversed directory headers,
existing hardlink paths, the runner's Plan copy and two complete input maps
are included. The apparent-cap forecast rounds every existing entry and new
copy to 4 KiB, conservatively above the observed 1 KiB `du` units. Sparse-file
logical size is retained. A separate 128 MiB allowance covers generated files,
temporary state and other receipts; it is a budget assumption, not a measured
guarantee about future output size.

The strict production host build and independent source review passed. Pinned
V and clang match the [Plan checkpoint](audio-portal-plan-check.md), with
`-prod -nocache -keepc -backend c -Werror=incompatible-pointer-types`.
The shared audio input/preparation modules match `a443190dc` unchanged.
Source SHA-256 is
`05f61843bcb97ed6ab190e4b6b3658c67c75599067d3b3ae9b18e2e90202a428`;
binary SHA-256 is
`81f0a88cefc7b2080da7215b85d080f070bd3caf079352990b96dd8ff88a1434`.
Generated C confirms both empty-directory map insertions and is retained with
SHA-256 `0ede290fdd6bf47471c3589caa304d427bfa674aa1eb199f4b9ae0da1456a670`.

The real forecast returned actual exit 0 and `WITHIN` for the exact final Plan
`d939f4091b42d556db5739845e9f099c0f2cd877a0be4332b91beeb665e90290`
and independent source revision `56941c3e3d059911b736f4ac21d169f122013b5d`.

| Forecast component | Bytes |
| --- | ---: |
| 5,558 captured/copied paths, rounded | 641,159,168 |
| 5,108 new store objects, rounded | 539,451,392 |
| Directory allowance | 13,905,920 |
| Runner Plan and two input maps, rounded | 44,965,888 |
| Generated/temporary/receipt allowance | 134,217,728 |
| Projected allocated total | 1,888,219,136 |
| Projected conservative apparent total | 2,125,312,000 |
| Unchanged cap for each measure | 2,147,483,648 |

Wrong-Plan-digest and existing-report controls refused with actual exit 1;
the former created no output, and the latter preserved the report's bytes and
metadata. Five original complete postchecks passed for both source worktrees,
the compiler, selected kernel and original full kernel bundle. The earlier
raw-apparent draft compiled but was superseded before execution; its source,
binary and generated C remain preserved.

Evidence remains under
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-independent-fixtures-aarch64-prepare-20261104-01/setup`.
`target-projection-01.json` SHA-256 is
`d7f54c0431c8161a433bc1cc131e4f24a02f902f4efb78e063b062604914b63e`;
`estimate-controls-01.json` is
`d3bc4880b6bbd9354644d2c7164bf787f10f3733304997662c4187556f483d9d`;
`estimate-commands-01.json` is
`6fb9aa657bdf6eca8500703a3a8ee16fc81384be831dbd5a22af240197efbf38`.

This forecast supports fresh admission only. It provides no continuous cap,
free-space admission, future-size, hermetic-toolchain or target-qualification
claim. Actual preparation retains the qualified allocated-space guard and
independent dual-measure endpoint checks; native audio execution remains open.
