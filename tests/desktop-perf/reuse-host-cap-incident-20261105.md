# Reuse-profile compiler fallback incident, 2026-11-05

The first normal reuse-profile build failed strict C compilation, then its
compiler automatically attempted to install/build a compatibility compiler.
That unplanned fallback exceeded the cumulative 32 MiB host allowance. The
producer was stopped; all failed artifacts remain preserved. No reuse adapter
qualification, normal controls, production build, preparation or VM followed.

Let `C=/Users/alex/Library/Caches/vinix-codex/section14`,
`S=C/perf-runtime-host-20261105-01`, and
`H=S/reuse-adapter-host-01`. H includes independent source drafts, both finite
generator attempts, generated source and the complete failed build/cache tree.
The frozen runtime source worktree remains at
`984fdc1897c7da4b166e2d93baa548cbe8c48e2d`; the generated profile source checksum
is `9dcca0b3717c9f17d130aae78710f0de9a6826d4f29def62111e1e81572c1e21`.
The native and explicit-C finite generators produced identical source bytes;
those observations do not qualify the main adapter or its compiler source
closure. The source implementation remains an unqualified draft.

The normal invocation selected the pinned ff75 executable, `-backend c`,
default GC, `-nocache -keepc`, clang23, MacOSX26.5 and pointer/format errors.
Its retained C failed at `src.c:34014`: `waitpid` received an `i64 *` where the
SDK requires `int *`. The mapped private `vlib/os/process_nix.c.v:285` already
declares `cstatus` as `i32`; the actual C instead declares it `i64` and embeds
`/Users/alex/code/v3-selfhost-performance/vlib/time/tzdata/zoneinfo.zip`.
These are evidence of an unresolved compiler source-binding gap. They do not
establish which complete vlib was actually consumed or prove a compiler defect.
No protected compiler/library or strict-C rule was changed to bypass the error.

The producer omitted explicit fallback refusal. Its actual `/usr/bin/env -i`
invocation supplied PATH, private HOME/TMPDIR/VMODULES/VCACHE, V/VEXE, SDKROOT
and DEVELOPER_DIR; it supplied no `V_MACOS_V3_NO_FALLBACK` marker and no
`-new-compiler` option. There was no contemporaneous `environment.json` receipt.
`normal-01/environment-from-toolcall.json` is explicitly a post-incident
transcription of the recorded tool invocation, not an observed complete child
environment. Coherent source-selection/caller markers were not established.

The log then records `make v1`, a V 0.5.2 Darwin/arm64 release download, a
symlink permission error, and an oldv Git-clone fallback. The historical launcher
source matching the reported `fd996` version is retained as
`normal-01/launcher-fd996.v` (Git blob
`6b8cff850397400d35ab8cd681bc07aebc3cc712`). Its lines 182–184 set no-fallback
for `-new-compiler`, line 414 checks the explicit refusal markers, and line 1332
starts the compatibility-install path. This source inspection is separate from
proof of the binary's full build provenance.

Read-only follow-up matched the private tree's `vlib/v/driver/driver.v`
(`7112d951708a9114b0e35c6045b87ff991eb85104740db6249c109f84c29cade`)
and `vlib/v/pref/pref.v`
(`7d7112feaa2ed7bb0ca1f07a7183d9fbac5f44dc2ba7edc1c82a11b1bfed2779`)
to the same fd996 Git source. Pref lines 350–354 default to baked `@VMODROOT`.
Driver lines 11968–11975 select `embedded_vroot` only when the caller-presence
markers pass pref lines 279–282. Otherwise, `resolve_vroot_for_input` at 20259
searches the input/cwd and then retains the initial baked root. The embedded
branch at 20272 instead accepts the VEXE parent when it has `vlib/builtin`
(20316). The failed invocation omitted those markers. Both retained qualified
owner C files instead contain the private ff75 tzdata path and `i32 cstatus`,
and their recorded environment includes the caller markers. This supports the
resolution diagnosis; no corrected invocation was executed. GNUmakefile is a
requirement of the launcher's fallback installer, not of this driver vlib test.

The existing precision compiler `53debcfe...ec7e` has the same driver source.
Its retained compiler C and qualified heap-check C contain its private toolchain
root, and its qualification environment includes the caller/refusal markers.
Those retained observations offer a possible future input choice, not proof
that swapping binaries alone fixes this invocation or permits another run.

An initial in-progress measurement of 148,196 KiB was superseded by the
post-termination measurement of **369,712 KiB allocated / 302,597 KiB apparent**
for H. It is an actual allowance breach. The compiler's private fallback HOME
retained the downloaded/unpacked/partly cloned files. No failed output was
deleted or hidden to make the budget fit.

The observed process chain was timeout 37522 → compiler 37526 → make 37644 →
V runner 38343 → oldv 38423 → Git clone 38428. The first four were in PGID 37522;
oldv and Git used PGID 38423. TERM was sent to both observed owned groups.
The outer tool returned actual status 143. Subsequent exact `ps` and group
`pgrep` queries each returned 1; root independently confirmed group absence.
This is present-day absence of the observed identities, not a native-owner
wait/reap/ECHILD receipt or a guarantee about arbitrary escaped descendants.
The original Clang/compiler/fallback statuses are not reconstructed.

Complete selected compiler-root, SDK-include, clang-include, private-source,
runtime-worktree and generated-source maps matched their before maps after the
incident; direct executable pins also matched. Complete R1 and R2 captures
still matched their frozen `03ce6150f13b2f25454f5fc163d82b1ad8483006372b7261cc0a9a4cfd92ff93`
and `c1bb658176983b19d8c2f907f85a426fa9ac91006ed14e5b9f6ca7a63dd4a763` maps.
This protects those selected inputs. It supplies no hermetic or actual-vlib
binding claim for the failed compiler invocation.

After bounded incident receipts and post-maps, final H measured 370,500 KiB
allocated and 304,974 KiB apparent. It is frozen at complete literal inventory
`S/reuse-failed-host-inventory-01/primary.tsv`: 25,539 entries, 3,981,932 bytes,
root mode 16877, checksum
`3b2dce99844628718cfe3310f8845b47e79f8b76228eca6a80d124921c2f0787`.
The inventory stays outside H; no subsequent H writes are allowed.
Root independently captured the complete unchanged H tree to
`S/reuse-failed-host-inventory-01/root-independent.tsv`. Its actual status was
0 and its complete bytes, entry count, root mode and checksum matched the
primary inventory; direct byte comparison returned 0. Root's separate
`kill(-PGID, 0)` probes also returned ESRCH for both observed former groups.
Those probes retain the present-day-absence limitation described above.

| Artifact relative to H | SHA256 |
| --- | --- |
| normal-01/command.log | `d832a9335982025025d6e453855c8e6934fa17e0ff1cab0bbc332da8f47a001d` |
| normal-01/reuse-x86.c | `05d06c53d39ebb97627a7947aedb5c3521c89fb0ae70ce48b4ad563393c96af9` |
| normal-01/environment-from-toolcall.json | `223de865f2e66e87054edba740edc55d1f06dc94ed770beb0fffcbcf6986f2cd` |

The closure endpoint across the four existing charged roots was 3,082,968 KiB
allocated / 3,929,582 KiB apparent, with 12,319,456 KiB free. The proposed fifth
root R3 does not exist. Adding the proposed 262,144 KiB blank disk, full
786,432 KiB reserve and 8,192 KiB preparation allowance would reach 4,986,350 KiB,
exceeding the unchanged 4,718,592 KiB ceiling by 267,758 KiB. Later independent
receipts add to that retained scope. No future guest fit, retry or budget
widening is inferred. Further execution requires corrected source-binding and
fallback-refusal prerequisites plus a new concrete resource review.
