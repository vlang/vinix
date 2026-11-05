# Current paired-kernel attempt: target compiler refusal

2026-11-05: the one admitted current-source attempt failed during x86_64
compilation. AArch64 never started. No generated-code, ELF, guest, allocation
or production-integration qualification is claimed. The completed host
controller and 67-control observer qualification remains recorded separately.

The reviewed source is W,
`/Users/alex/code/vinix/build/package-peer-frame-current-20261105-worktree`,
detached at `ffe3a39016fe89ff494cf59fa1126aca8a76dee5`, with exactly the seven
kernel changes and nested profile described in
`current-integration-paired-build-plan.md`. No source or guard was changed in
response to this failure. Current `uint` and `MSG_NOSIGNAL` changes remain.

R is
`/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01`;
S is R-seal-01. The exact launch argv, cleared environment, identity pins and
admission are retained in S/build-launch-01/plan.json. The root-approved
inclusive projection was 501 MiB under the unchanged 512 MiB cap, including
the 1 MiB final tail. All source/tool pins, dependency-destination freshness
and source whitelist checks passed before launch; measured roots were
63,792 KiB allocated and 57,029 KiB apparent. Available space was
29,976,716 KiB in that receipt and 29,605,412 KiB at the final launch probe.

The only launched route was the qualified observer
R/observer-host-01/profile-bootstrap-03/fresh-frame-observer
`--build-frame-01`, SHA256
`2370cecc2092c730573dcfcd2afaf2a32182333e9640d2207dd7bb2d3cd98958`.
Observer PID/PGID was 50269; its directly owned controller was PID/PGID 50282.
The controller used its unchanged sequential candidate route with x86_64
first, `-j2 ALLOC_TRACK=1 PROD=true LIMINE_MP=0` and the pinned target compiler
`/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v`, SHA256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.

That V 0.5.2 fd996fc compiler rejects the current `uint` syntax. The retained
log first reports it in the native-generator heap benchmark, then in current
kernel sources including `fs/removed.v`, `fs/storage_control.v` and
`abiargs/args.v`. The kernel invocation retains `-nocache -os vinix
-enable-globals -nofloat -manualfree -gc none -target-libc-headers
-no-closures -arch amd64 -d alloc_track -prod` and the existing exclusions.
No compatible target compiler was substituted and no generated-C check was
relaxed. Compatibility was explicitly unproved in the admission plan.

Make returned 2 after 44,315 ms. Its receipt records `leader reaped; group
absent`. The controller returned 1; the observer actually returned 1 and
observed controller status 1. Its direct cleanup records waitpid -1/ECHILD
(10) and group probe -1/ESRCH (3). The x86 make-group cleanup is the separate
controller's receipt; the outer observer does not independently prove that
group. AArch64 has no receipt or cleanup claim. A post-retirement process
listing found no remaining observer, controller or make command for W/R.

The native watch retained 79 samples: maximum gap 1,014 ms, maximum sample
window 291 ms, peak allocated/apparent totals 79,964/71,029 KiB, and minimum
available space 29,521,120 KiB. This is failed-run observation, not a native
PASS. R/build-01/x86_64 retains the log, partial objects, private runtime,
argv, status, failure reason and complete after-failure input map. All earlier
host/refusal evidence also remains untouched.

The complete before and after-failure input maps are byte-identical (`cmp`
returned 0). Retained SHA256 identities are:

| Artifact | SHA256 |
| --- | --- |
| R/build-01/inputs-before.json and x86_64/inputs-after-failure.json | `a58eb8d74d895b6acaeb46a7678de699c8eba909859a053b0138f376795ee130` |
| R/build-01/x86_64/build.log | `265098508fbee34f488b2a47b824023c0a6f242f3a84e26dc939057be8b2612a` |
| R/build-01/x86_64/build.status.json | `43b129e4e1c94e96721a3b56a9c0777e61a16686fbd5bd88c077329da9b7b4ef` |
| R/native-observer-01/run-01/status.json | `a373e18d58adef71f26c5095eb5e0f2c8d88e30776a7540a34f9d4e77057ccbd` |
| S/build-launch-01/observer.outer.log | `9cbb00b1285b1e40e118d4a5f7a56e14bfcc801bcf6c64096714b57eb536dbbd` |

Quiescent endpoints across the five charged roots measured 79,932 KiB
allocated / 71,033 KiB apparent. R/build-01 alone measured 14,648/13,084 KiB;
its failed x86 subtree was 10,708/9,206 KiB. These retained outputs invalidate
the previous one-attempt projection for a retry. No retry is authorized by
this report. A future attempt needs a compatible independently pinned
compiler/source/vlib closure, reviewed semantic generated-code checks,
fresh output names, a complete inclusive resource projection and a new lane
assignment. The existing target compiler and historical checkers stay intact.
