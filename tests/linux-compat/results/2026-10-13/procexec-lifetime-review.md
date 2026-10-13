Independent exec metadata lifetime review: PASS

Reviewer: `/root/procstat_lifetime_review`; no source edits or commits.
Reviewed both kernel sources, both emitted kernel C files, the final fixture
source and previews, actual guest C and final native exec serial captures.
Whole-kernel C restoration changes only the exec loader body, normalizing
unused-loop source-offset identifiers.

The replacement name is independently owned and constructed before acquiring
the process table lock. The existing pathname allocation transfers to the
process. Both old strings are freed and both replacements installed while
procfs readers are excluded by that lock. No failure return intervenes; later
command-line and executable-filesystem installation occur after unlocking.
The lock is not nested with earlier page-map, thread-list or filesystem locks.
Its allocator lock ordering matches existing PR_SET_NAME.

Fixture image/record/observer descriptors close on every return. Unfinished
children are killed and reaped before retained pipe ends close. The final gate
holds the child alive throughout storage observation. Exec arguments, argv,
Counts and Slabs use explicit stack storage; emitted C contains no hidden
memdup, malloc, array allocation or bounds-runtime dependency. Same-UID
dumpability is established before the initial gate, avoiding expected
post-setuid EACCES unrelated to this publication race.

Candidate reads per kind are 603/603 (UID1000/root) on ARM and 8175/7593 on
x86, with zero failures during 200 exec replacements per cohort. All 18 ARM
and 14 x86 slab classes remain flat over 200 subsequent observer cycles;
large pages stay 79/79 and 205/205 respectively. This measures observer
retention after exec completes, while the child stays alive; it does not
qualify allocation retention across the exec sequence. The x86 baseline
reproduces 27 invalid-name observations: 12 comm, 9 stat and 6 status. ARM
baseline timing did not expose the race.

SHA-256 pins:

- kernel/userland/userland.v: 1cceebb504d423ba7e6c7b91d1391deae12f2a8f9bd0edbe06183a2abb010bc8
- kernel/userland/userland_arm64.v: da6881ff21cf825b5c0e07804cd0f8209df2862557116c608498e668cb3870b9
- fixture source: a0efb8338adaa6fe5249bd6c23f597a7734da46db116bc3daec71610659cba64
- both fixture previews: 176c5e21054e4ab5ca94bff432357354d8d33ddc093c4f3aadf67a22b82f2be3
- ARM kernel C: e4eb28b7bc6266519e87332293567f9a5b53cbb89269cf434951ea7fe3be392a
- x86 kernel C: 88b5c482285c4357328e82fda04b015ac6219cef1a07aed34dfb0ade839d7995
- ARM final-after exec serial: 9719d5931b1a8947ab4fbe3f6e28b2ceb32b999faff4ecd2ff6912189ddeb2a6
- x86 final-after exec serial: 42f62f401bf4ff3ee6b455754b896380241715d73da37e99da484935a18faa22
