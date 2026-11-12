# Wine private NLS discovery, 2026-11-12

Source baseline: `c0363a781daeb6d289229bdfd1e325eedccfdcb7`, plus the
maintained patch and source snapshots in the external evidence below. This
continues the [fork-safe retention checkpoint](wine-forksafe-retention-check.md).

The local Wine producer now composes the private-prefix patch with one server
instruction change. Wine 9.17's [NLS directory discovery](https://github.com/wine-mirror/wine/blob/wine-9.17/server/unicode.c)
normally uses `realpath("/proc/self/exe", NULL)` on Linux and
`realpath(server_argv0, NULL)` on other platforms. The private bridge supplies
an absolute admitted `root/usr/bin/wineserver` identity through musl's
`--argv0`. Using that identity locates `../share/wine/nls` inside the same
runtime without requiring a procfs path grant.

The original server pin remains
`9583955993378e1c20e3c1353b8a6ad0dfbadc6bce77fe14bc26e178cf38d9d6`.
At file/virtual address `0x5efe4`, the seven-byte instruction changes from
`48 8d 3d 40 f9 00 00` (address of the procfs string) to
`48 8b 3d 35 4d 03 00` (load `server_argv0` at `0x93d20`). Admission checks
the full input hash, surrounding instructions through the `realpath` call,
and the original `main` store of `argv[0]`. The private-prefix changes remain
exact; the client receives its existing patch only. Layout admission derives
the complete expected binaries from the original pinned inputs rather than
trusting a producer hash.

`wine-runtime-patch-check.v DISTRIBUTION_ROOT` passes normal, production and
ASan/UBSan builds. It compares every output byte, checks unchanged input bytes
and size, and refuses 16 reapplication, swapped-role, truncated and corrupt
inputs. The final sanitizer run disables leak detection; it makes no retained
allocation claim. An earlier leak-enabled attempt remains retained and reports
V runtime/`os.real_path` startup allocations. The final checker borrows its
supplied distribution path.

Fresh `prepared-arm-01` and `native-arm-01` pass. The actual signed Win64 probe
runs as the ordinary account with the existing private prefix/socket,
outside-write refusal, natural-exit and lease checks. The independent
`retained-arm-01` passes. All **56 refusal controls** pass across eight shards;
each admits both original and copied baselines. The coverage checker confirms
complete, unique assignment and unchanged baseline hashes. A new resealed
mutation restores exactly the original procfs instruction while preserving
the private-prefix patch and is refused at the exact layout gate. The updated
collection checker also passes its synthetic baseline/retry and nine refusal
controls. Source offer and redistribution admission remain local and incomplete.

Fresh `prepared-x86-01` passes, and `native-x86-01` gets beyond the previous
`failed to load l_intl.nls` failure. Wine initializes its server but now exits
23 while mapping PE images: `unix_prot 0x7` requests fail with `Not supported`.
The signed READY/PASS markers are absent. The unchanged outcome gate refuses
retention with `requires uninterrupted passing native Wine outcome`, creating
no success output. This qualifies the NLS fix and records the next failure;
it does not qualify x86 execution or permit writable/executable mappings.

Raw evidence is retained at
`/Users/alex/.cache/vinix-wine-nls-20261112`. It includes both architectures'
prepared trees, controller builds, generated C, literal target argv, logs,
full inventories, the passing ARM receipt and failed x86 outcome, host checks,
and disassembly before and after the NLS change. `repository-baseline.tar`,
`source-baseline.txt`, `source.patch` and the new checker snapshot preserve
the source used for this continuation. The unchanged compiler, MinGW, PE,
distribution, translator, sysroots, GCC runtimes and kernels also remain in
the complete [preceding pinned-input archive](wine-forksafe-retention-check.md).
Historical auditors still require their original complete absolute input
namespaces; these records do not substitute relocated copies silently.

The continuation archive is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-nls-20261112-01.tar.gz`.
Keep it with the preceding pinned-input archive. Its adjacent `.inventory.txt`
and `.sha256` receipts cover the complete new workspace. The original workspace
and `wine-nls-20261112-01-restoration` are retained.
The existing V archive tool returned 0 after comparing original and restored
types, modes, link targets, sizes and file hashes; both root modes are `0755`.

| Artifact | SHA-256 |
| --- | --- |
| Archive | `fafe8797639aa632764c1ef8ce0951771358b597d1cf6ad06bb08a678d367572` |
| Typed inventory | `dd711c061cd847186ba59a2a14e1707f73e53bdc7ec29d5d5970aa32617b3b58` |
