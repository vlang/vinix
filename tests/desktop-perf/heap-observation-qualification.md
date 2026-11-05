# Complete heap observations, without qualification

The host-only `heap-observe.v` validates all 44 maintained measurement rows and
DONE, all 40 raw before/after pairs, 80 complete snapshots and 640 canonical
delta rows. It emits every class counter and exact signed delta, large-page and
both corruption counters, exact aggregate page counts, cohort statistics and
the serial SHA-256. `qualification=false` is explicit in the API and JSON.
Successful observation never accepts a nonzero value as flatness.

The existing `heapfull.inspect`, `perfheap.qualify_flatness`,
`perfflatness` and `heap-full-check.v` sources and accepted checker binaries
are unchanged. The added API reuses their private framing and arithmetic
helpers but does not call the strict flatness policy.

## Host qualification

Reviewed source base: `52751de861ecb9959797203fc5dfb78b3284c158`. As-run
sources are retained under `source-02/` and `source-02.sha256` in:

`/Users/alex/Library/Caches/vinix-codex/section14/perf-runtime-host-20261105-01/observation-host-01`

Both final normal and production builds exited zero with the independently
derived compiler `53debcfe66952ba952d64b2b94dbb2408bed6992453d1ac6bad5889e4bd1ec7e`
and clang23, with incompatible-pointer diagnostics as errors. Each passed 33
new observation controls plus the unchanged 57 strict transcript controls.
Controls include complete nonzero observation versus strict refusal, late
changes, cancelling object deltas, positive/preexisting/decreasing corruption,
full-width page sums, and malformed, missing, inconsistent, duplicate and
truncated pairs. Usage and missing-input refusals exited one in both builds
with `qualification=false`.

The first production attempt rejected redundant false field defaults. That
attempt and its complete source copy remain retained. The correction removes
only those defaults and explicitly sets the top-level JSON field false.
An earlier normal bootstrap's tool exit status was unavailable after a context
handoff; it remains unqualified and was rebuilt to obtain an actual status.
The derived toolchain's original complete postcheck exited zero with the exact
completion marker. An earlier retained check has the same marker, but its
actual tool status was also unavailable after the handoff. All 19 immutable
source/tool/serial checksum checks passed.

Final executables:

| Artifact | SHA-256 |
| --- | --- |
| `normal-03` | `49ac07211d9a4867159ce3fac367a22f20c1799d6cc0e7dfe18781d81ab4f046` |
| `production-02` | `9b383ccaef13d211e0c42d2592291c3c1212c791326fd73ebbabe23dfa0c37b2` |
| CLI source | `2ec14d57977556cfc0e7b91b88efebe4d671abcb595cbb664a42f38f0e8bd8dc` |
| Observation API | `c79623ad7e4fe107366bbea553654a09fcc60097d23f1af123156999e6663b18` |
| Observation controls | `b2e47fefb0caf6ecca33240a9a8558c28a502e9b40568b3fe6fda77d2dfae821` |

This is the explicitly scoped GNU-timeout host trust bootstrap with endpoint
disk/log observations. It does not qualify a new process owner or claim
continuous disk/RSS enforcement. New cumulative growth, including preserved
attempts and owned source, remains within the 32 MiB dual allocated/apparent
cap, with 8 MiB reserved; the artifact body remains below 24 MiB. The final
endpoint measurements and artifact checksums are retained beside the logs.
No kernel compile or guest was launched by this component.

## Retired frame transcript observation

Input:
`/Users/alex/Library/Caches/vinix-codex/section14/perf-six-x86-20261105-01/prepared-frame-01/results/serial.log`

Serial SHA-256:
`df7faf539b3b0e256fb810b48d2ca0a9480d35594d88c7d76eb6613c0e28a4c8`.

Both builds produced byte-identical complete JSON (SHA-256
`728de9250ef5f293ba2f6836960f7df8b85f0690b53018740b8add1ffcf60936`),
retained as `actions/normal-retired.stdout` and
`actions/production-retired.stdout`. It validates 44 measurements, 40 pairs,
80 snapshots, 640 delta rows and 560 class rows. Nine cohorts have a single
nonzero size-256 backing-page delta; their object count remains 4555:

| Operation | Directory | Size-256 pages before → after |
| --- | --- | --- |
| proc_read | /tmp | 305 → 306 |
| memfd | /tmp | 307 → 308 |
| rename_over | /tmp | 308 → 307 |
| mkdir | /tmp | 307 → 308 |
| unix_connect | /tmp | 307 → 308 |
| rename | /root | 308 → 307 |
| hardlink | /root | 307 → 308 |
| unix_connect | /root | 308 → 307 |
| unix_datagram | /root | 308 → 307 |

All object deltas, large-page deltas and all 80 original corruption counters
are zero. All four churn pairs are flat; their physical-retention summaries
report zero. Every class row and per-pair aggregate page value, including
changes between cohorts, remains in the JSON. The first pair reports
1900 → 1900 pages and the last pair 1919 → 1919; these endpoints are
observations across different warmed workloads, not a flatness criterion.

The unchanged accepted full checker exits one on this same serial with
`nonzero exact class object or backing-page delta`; the older emitted-delta
checker exits zero with its original limited scope. Neither result is changed
or replaced. Process exits, immutable runtime inputs, kernel provenance and
original runtime audits remain separate evidence. This diagnostic provides
no current-kernel qualification or allocator-fragmentation/leak diagnosis.

