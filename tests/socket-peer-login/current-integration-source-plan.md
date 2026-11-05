# Current-HEAD peer/frame source preparation

2026-11-05: source preparation and independent source review only. No host tool
was compiled, no kernel was built, and no VM was started. The production kernel
in the shared main checkout was not changed. Section 14 qualification is open.

## Retained source

- Selected current base: `ffe3a39016fe89ff494cf59fa1126aca8a76dee5`.
- Detached sparse worktree W:
  `/Users/alex/code/vinix/build/package-peer-frame-current-20261105-worktree`.
- Evidence R:
  `/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01`.
- Held donor D: `build/package-peer-login-atomic-fresh-worktree`, base
  `9acefa77bee69247c837e97987a2377536aa41cc`. D and historical evidence remain
  unchanged.

W was created with bounded `git worktree add --detach --no-checkout`, sparse
checkout and detached checkout, each exit 0. Pristine status and diff were empty.
Its sparse set is the set in `fresh-frame-plan.md`, plus the socket suite.
No shared uncommitted `elf`, `pselect` or `userland` changes were copied.

The six tracked-file patch is 97 insertions and 17 deletions. A seventh new
file is `kernel/alloctrack/frame_page.v`. Five tracked-file donor hunks applied
directly; the tracker loop was replaced separately. Tracker retains all four
current `uint` expressions. UNIX retains the later `MSG_NOSIGNAL` constant,
comment and receive mask. Do not copy whole donor tracker or UNIX files later.

| Kernel path | Prepared SHA256 |
| --- | --- |
| `alloctrack/frame_page.v` | `be2b4cee4283cc4c5275cd5a1cb668a12ab2e08300c18a15b4731ca185dad48d` |
| `alloctrack/track_d_alloc_track.v` | `1948b5f6d2bc30dae9ca50bc5726ee47937d56bcb05869891ceb9e644e4fa698` |
| `file/locks.v` | `74067cb8deb1f7d41bfc1deeee51af94b48ece3761078c179ed06a90d7a6a1b6` |
| `memory/slab.v` | `5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4` |
| `socket/public/public.v` | `19b4b0a8fceaf0bbb78957d69025e7a6e8d805b1557d5f9c924067f82a3e372a` |
| `socket/socket.v` | `98588cce3eb94e72a89baf181178b92ea4de2a2b304d139c0f79af2571c7c3a8` |
| `socket/unix/unix.v` | `fec45e9c6f5ac12c615b3e8790ae0307ba809381e3a36cc36c220feb37951261` |

R retains ordinary independent copies of all seven files and the four-file
controller closure under `source/`. `source-sha256.txt` has SHA256
`616c07d0a255580240ba8471c546811704c1b5f29363c57fa02d0968e14b23de`.
The complete tracked kernel patch `integrated-six.patch` has SHA256
`67a57af1641ef48c731d021d1166655eeb82c993ff4ef1d1b6ad30101ed6159b`.
The extra helper is covered separately above; it is not omitted from the source
snapshot merely because an ordinary tracked-file diff excludes it.

## Concrete V controller profile

The maintained V driver is already tracked at this current base. Modifying it
in place would violate its own six-path tracked-change whitelist. The prepared
source therefore lives in the untracked four-file subtree
`W/tests/socket-peer-login/current-head-profile/`: `guarded-build-check.v`,
`abi.h`, `dylibclosure/core.v`, and `dylibclosure/core_test.v`.
No binaries, modules, caches or result files belong in that subtree.

The driver starts from the exact historical source SHA256
`20aa8efe95413e461a2cb95f1a0fd94331709fa79225029f334cc72103cc43dd`.
The prepared source SHA256 is
`46be2985c371399c6f1b6081fc58340cce9a67d20baf3bca1fc2efac4e2ccc31`.
R retains `controller-rebind.patch`, SHA256
`4ed7d913a860f398a88ad47f0abd618645c1c0dafc2eed91344518d7b38cdd48`.
It contains exactly five reversible substitutions:

1. `const revision` becomes the selected current base.
2. The tracker source hash becomes the prepared hash above.
3. The candidate UNIX source hash becomes the prepared hash above.
4. Candidate `run()` root becomes
   `repository + '/build/package-peer-frame-current-20261105-worktree'`.
   The nested source's `@FILE` ancestor is unsuitable for locating W.
5. Append the four exact nested paths to the existing as-run source-copy list.

All other bytes, including ownership, cleanup, bounds and generated-C guards,
are unchanged. The original baseline mode remains historical and is not an
execution route for this candidate. Only the ordinary two-architecture candidate
mode is proposed.

The existing snapshot recursively inventories `W/tests/socket-peer-login`, so
the derived source and closure are bound before and after the build without
changing any whitelist. Shared-main untracked artifacts do not enter this
traversal. Declared compiler/dependency referents retain their explicit original
inventory. The four copied closure inputs match their historical pins.

Independent review confirmed the kernel scope, retained later edits and exact
five-edit controller delta. Reversing the edits restores the original source.
No new lifetime issue was found: existing OFD/slab objects remain referenced;
frame reads remain synchronous and within the adapter's mapped page; scalar
identity snapshots are published before connected state; a failed-connect CAS
cannot overwrite connected or closed state. Actual C and runtime checks remain
required. `git diff --check` passed. The no-index profile whitespace check
produced no diagnostics; its exit 1 records the expected source differences.

## Admission and remaining execution gates

Pre-mutation allocated/apparent projection used du-rounded KiB over the
selected main inputs plus the complete donor: 88680/122948 KiB. This deliberately
overcounts uncopied dependencies, cache and donor files. Adding 16384 KiB for
setup/profile/metadata and 1024 KiB for final receipts gives 106088/140356 KiB,
below the unchanged 524288 KiB cap. Available space was 46913932 KiB. R retains
the corrected probes and an earlier missing-path read-only du refusal; no failed
attempt was deleted. Later admission must use fresh rounded allocated/apparent
measurements, include retained failures and reserve final receipts again.

The first post-preparation measurement, including new Git worktree metadata,
was 15268/12744 KiB before the independent source snapshots. The final retained
receipt gives the later measurement. These source-only probes make no continuous
sampling or process-group qualification claim.

The next stage must be reviewed separately:

1. Check exact W HEAD, the six tracked paths, only the new helper and four-file
   profile as untracked inputs, all source hashes, source snapshots and projected
   full build-work size. Recheck live resources and all pinned tools/dependencies.
2. Bootstrap the nested driver with the existing pinned host compiler, coherent
   private modules/cache/tmp and strict incompatible-pointer checks. Record
   exact source/tool maps before and after. Run its unchanged host/closure
   controls. No current-main compiler compatibility is claimed yet.
3. Reuse the qualified `fresh-atomic-observer.v` through exact-count reversible
   fixed-profile substitutions following `prepare-fresh-frame-observer.v`.
   Bind W, R and fresh sibling audit paths, actual newly qualified controller
   binary hash, prepared source hash, and the nested controller-source path in
   `production()`. Preserve both architectures, all limits, original full
   auditor, actual inner cleanup receipts and final timing gates. Use the
   reviewed qualified observer profile appropriate to the final timing checks;
   do not introduce a new owner implementation. Retain derivation and complete
   generated diff, bootstrap and rerun that exact profile's host controls.
4. Run both sequential `-j2`, `PROD=true`, `ALLOC_TRACK=1` architecture builds.
   Require actual generated-C validation and all 18 frame plus 29 peer mutation
   refusals, ELF/symbol checks, complete input equality and cleanup receipts.
5. Freeze the complete new bundle, then run the unchanged original full seal,
   separate check and independent check before downstream consumption.
6. Qualify both peer-login guests and current-source allocation/performance and
   desktop scenarios. Old-base artifacts cannot qualify this current snapshot.
   Preserve the documented global allocation-allowance baseline failure rather
   than silently changing `allowed.txt`. Audio and other Section 14 gates remain
   separate.

This report commits source preparation, not production-kernel integration or
runtime success. Future main changes require an explicit comparison against
the selected base before this prepared patch can be integrated.
