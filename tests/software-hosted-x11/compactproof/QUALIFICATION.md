# Compact compositor proof host qualification

On 2026-11-05 the normal and production standalone tools compiled with strict
pointer diagnostics and passed all eight explicit control categories. This
qualifies the small proof readers and refusals. No original complete audit,
real compositor import, target build or guest ran in these controls.

The main reference revision before this change was
`bb8ffd6e8ac281c10fc15b7b94f47bf9360f2aef`; the new files are identified by
the hashes below and the captured module map, rather than that revision alone.
The independent source preparation retains the earlier native fixture base
and its explicit prerequisites. This is not a build of the whole current tree.

Raw sources, generated C, executables, argv, logs, statuses, samples and
before/after maps remain outside Git under
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02`.
The host artifacts below are relative to `native-supervision-host-01/`.

| Qualified source or artifact | SHA-256 |
| --- | --- |
| `compactproof/admit.v` | `558e3d949d310b54d8550bb8d51bbabfab395655f58afdb6167bf1f42fc58f80` |
| `compactproof/controls.v` | `8b0ea41834fac2b4959ca30d6f9f2d0b2d90e18973a9fa5b2c190f59fb6b8e61` |
| `compactproof/check/main.v` | `0c5eeacdfe5dab36ce10182fcd8987689661c6bdb7d83517e0fd7b78f940cc32` |
| unchanged `launchproof/admit.v` | `e8ba120b8b4ac08207bd53be979c5d6ea8085eb11df4689025b107ab0f1aeb94` |
| unchanged `optionsfixture/fixture.v` | `c5d895e978fb42959de5824ea5945683edd3acab05f0fd126cf963d59b369b56` |
| normal `compactproof-check-normal-02` | `7a7d0a4e15cbc7a7981224763b3f67c2309c9d43b344ce65653401b1e3be21a3` |
| production `compactproof-check-01` | `53034195bcf776d70af9b81e98a5dd9960f05c487007d44e5acd61402059679e` |
| normal build receipt | `c75be4a62fbdb3843c0f2d2be44b65ddbbfaf10ed92671bab7090ba9283d62d6` |
| normal control receipt | `52e78f0548b011a1e27acc3631980190c67b11d453ae5a18754014d79c986620` |
| production build receipt | `2838b4936d543e5095a5ab1aa86069d360aa68001d10df07f6dfb4116fece8a9` |
| production control receipt | `2fc43073e4b6ee01e6ac179cd3c0d0965f65a8317c4175288484c145fa7b40d6` |
| each control `result.json` | `079fa1a515b66f7861e68ac144862abe3740e69854eb2748b338ac5fcd19e2c7` |

The eight categories cover literal relative names, complete manifests and
hidden files, aliases and scan limits, audit argv/log/actual-exit refusal,
unready/stale/changed live tokens, canonical recorded-proof and producer hash
binding, static ELF architecture/type/interpreter/load bounds, and refusal of
output inside frozen evidence. Recorded-proof controls read the pinned original
checker and manifests but use explicitly synthetic callback receipts; they
establish no new checker execution. All checks survive `-prod` without relying
on assertions. The unchanged historical `launchproof` tests were copied into
Git but were not executed by this profile.

The existing fixed builder `build-supervision-03`, SHA-256
`500561b47c862bf5c2d4edcce3fabe8cdeaf8116c3f298fd7a5146409ee13ff8`,
owns the four child commands sequentially. Its source is
`source/tests/software-hosted-x11/build-supervision-03.v`, SHA-256
`0cc0e57c3b0a7a4912aa9104c14293f0d82b6153cce792e63b8fa35c1cf332f1`.
Both compile logs are empty. Normal compilation omits `-prod`; production
includes it. Both retain `-nocache -keepc`, Clang, and
`-Werror=incompatible-pointer-types` with the existing separate const-discard
compatibility exception. These use the default host collector, without ASan,
manual-free or retained-allocation qualification.

The pinned V executable is `ff75a301…c4c5`, using the independently qualified
wait-width library overlay. The builder compared its complete overlay to the
original pinned map `65b8b832…786f` before and after each command. It also
captured `compactproof`, `compactui`, `launchproof`, `optionsfixture` and `proof`
module maps before and after every child. All eight module-map files are
identical, SHA-256
`7574aa941eeea3b7beb3dc58c14f6c23e57aea93bd5349a09f1aa8a51da9abce`.
The six maintained module/prerequisite V files compare byte-for-byte with the
independent captured copies.

All four outer and child exits are zero. Each command observed its private
group, reaped its leader, confirmed the group absent and ended with
`waitpid=-1`, `ECHILD=10`, without kills. The unchanged small-host limits are
120 seconds per child, sampled 550 MiB available-space admission/floor, and a
40 MiB host namespace with 64 KiB reserved for final receipts. The final
production control receipt records 13,197,312 allocated bytes before its final
tail and available space of 57,729,612 KiB. These are sampled namespace/free-space
observations, not quotas or a hermetic toolchain qualification.

The first normal compile, `compactproof-check-normal-01`, failed before C
generation because the local identity comparator used `os.FileInfo` while
`os.lstat` returns `os.Stat`. Its actual outer/child exits are one, with complete
successful group cleanup. The sole correction names `os.Stat`; all compared
identity fields and refusal behavior are unchanged. Original source
`fac6363b…78c10`, compile log `67c0ea79…4d15d`, and the exact correction receipt
remain under the same host root. No failed evidence was replaced.

After these controls, the host root was frozen and fully inventoried under the
narrower read-only aggregate reservation described in
[the staging projection](../compact-staging-projection.md). Failed attempts
remain present. New consumer tools use a separate root. No complete-bundle seal
is claimed for these host controls.

A later separate [complete inventory qualification](../compactdiagnosis/QUALIFICATION.md),
committed as `e21fc13ec`, retained both actual historical-check refusals. The
unchanged original auditor then sealed and separately checked both complete
current roots. Complete canonical comparisons found only the explicitly allowed
device, inode and timestamp differences, with no protected-field changes. No
original checker was executed in this host-control phase, and this historical
profile retains its strict refusal. An explicit consumption profile for the
fresh inventories, real compositor imports, compact UI interaction, retention
integration and both native guest scenarios remain pending.
