# ART builder recovery and checked dependency transport

Continuation of c2dbc22b9. Maps has rendered real tiles, place details/photos,
route geometry and mapped turn preview; Google sign-in still fails before
credentials. The prepared imageless-compilation guard is not deployed. No ART
runtime or Google authentication success is claimed by these builder checks.

The original ART build was in the removed `vlin` VM. An isolated clone of the
stopped `fastc-linux-loom2v` guest now supplies native ARM64 Linux: clone disk
`/Users/alex/.lima/vinix-art-20261114/disk`. The source guest was not modified.
Direct QEMU boot uses four CPUs and 6 GiB RAM, with an Alpine musl chroot at
`/var/tmp/vinix-art-alpine-20261114-r1`. Recovery required filesystem repair;
the first repair readback still reported orphan inodes, so it is not recorded
as a clean filesystem check. Subsequent Linux boot succeeded without kernel
error messages. Build qualification remains separate from builder boot.

The original ART archive was recovered and its full SHA512 matched
`build-support/android/build-art.sh`. Its source is e78bf68917bcaaf58fef3960cd88793b3b7f39cc;
this identifies the deployed runtime being repaired, not a V compiler selection.
No Python was executed. Upstream Make invokes Python generators for Makefile
discovery, enum operators, assembly constants and the ARM64 interpreter. Those
need V replacements before an actual native build. Interpreter output must
retain the normal ARM64 implementation; switching to a stub is not equivalent.

`art-builder-fetch.v` downloads the official ARM64 Alpine package URL list into
a fresh output and records each completed file's origin and SHA256. Large
packages use at most six concurrent 4-MiB ranges, checked against one strong
ETag, exact Content-Range and length before assembly. Failed scratch is retained.
Completed-manifest caches reject modified files and ignore unlisted partials.
Flat existing dependency caches remain usable; their actual hashes are recorded.
These are transport checks: Alpine signature verification is still required.

```text
art-builder-fetch [--direct] URL_LIST CACHE[:CACHE...] FRESH_OUTPUT
art-builder-fetch --self-test FRESH_OUTPUT
```

The r5 executable passed URL/header/cache self-tests and a real 16-MiB
g++ package cache copy with readback hashes. The copied g++-15.2.0-r9.apk then
passed Alpine `apk verify` inside the builder (`/gxx.apk: 0 - OK`). Package
planning found 150 dependencies with GCC 15.2.0-r9, ICU 78.1 and VIXL 8.0.
The graph omits Python and Meson. The selected musl revision differs from the
old runtime and must be recorded and qualified during the native build.

All qualified commands retain RSS 629145600 bytes, wall 300000 ms, free-space
reserve 1073741824 bytes, observed disk growth 536870912 bytes and output
4194304 bytes. The r5 tool compilation passed in 1046 ms with sampled peak
RSS 294010880 bytes; self-tests passed in 209 ms, and the real cache copy in
2575 ms with growth 51503104 bytes. Each returned 0/0 with complete cleanup.
Guest signature verification passed in 252 ms with sampled RSS 44298240 bytes.

Earlier dependency provisioning through the stale proxy failed; the next
working-proxy install hit the 300-second wall cap and left an incomplete
toolchain. Serial direct fetching timed out on GCC. The r3 parallel fetch then
hit the observed disk-growth cap: 562733056 bytes in 73503 ms, although its
output occupied only 66 MiB. Its failed receipt remains retained. None of
those attempts qualifies a complete dependency installation or ART build.

The next closure fetch, r4, stopped on shared growth 547545088 bytes after
71228 ms; its completed output occupied 122 MiB. A fresh r5 retry using those
completed cache records stopped on growth 557993984 bytes after 25524 ms,
with 164 MiB of output. Both returned 125/137 with complete cleanup. These
failed attempts remain distinct from the passing focused checks. No complete
dependency set, compiler installation or ART build was qualified.

V at `/Users/alex/code/v/v` advanced during this continuation from V 0.5.2
9a38ec5 (SHA256 f52821ef2d15507ef5238e36a5237c909dfbdbc09786671c5d87a3feb1ed843c)
to V 0.5.2 39e0e79 (SHA256 6bfbbc9bb51703846e68c0733605d848e8e8f09ec8e73be0d1497f457e6fe922).
The new r6 build passed with that available compiler in 1071 ms, sampled RSS
311771136 bytes; fresh self-tests passed in 105 ms and the real cache copy in
2662 ms. All returned 0/0 with complete cleanup under the same caps. The r6
executable hash matches r5. No historical V was selected. Tool source SHA256 is
3baf360e3033c60a9fa6a2fe727d8082d7cd080b44a063dfa2c625f4969e2d3f.

Evidence is external under `/Users/alex/.local/state/vinix/android/`:

| Artifact | SHA256 |
| --- | --- |
| art-fetch-tools-20261114-r5/art-builder-fetch | 05f9783af415f22a8eef6a86f8c36dbac5b583a63f100f4f65d988e12a1519e1 |
| art-fetch-cache-check-20261114-r2/g++-15.2.0-r9.apk | 650a2639d378f120f697e4e9f6426ab8fd7836a462465ad3d5d03bd20af44849 |
| art-builder-packages-20261114-r4/packages.json | 0606157d73862b2456b7f607dc0c878737f0e7aa28603cb96957538201b67287 |
| art-builder-packages-20261114-r5/packages.json | 83dac26bf31009129c47078af0d6c56177f93b5587306412051f8c2b546bcf88 |
| art-builder-guest-20261114-r2/guard-evidence.tar | b70b2c480f1da2bfa914b96da08ace87a13e20c38e39ead68767c9e63984e182 |
| art-builder-guest-20261114-r2.fsck.json | 3111606180c4bae38f837ee1c6e5e9cb84f10b39fc6df8f2f11a57f19e135e3c |

Guard logs and JSON receipts are beside `art-fetch-tools-20261114-r5`,
`art-fetch-checks-20261114-r5`, `art-fetch-cache-check-20261114-r2` and each
`art-builder-packages-20261114-rN` output. The checked Linux guard is retained
at `art-builder-guard-20261114-r1/bounded-command`; guest receipts use
`/var/tmp/art-*`. VM boot and repair evidence is in
`art-builder-guest-20261114-r1` and `art-builder-guest-20261114-r2`.
The latter also retains the exact QEMU arguments in `process.txt` and exported
guest guard logs/receipts in `guard-evidence.tar`. The builder was synced and
powered off normally; QEMU PID 93607 exited. No Maps test VM was started.
After confirming that exit, the clone was attached read-only. Final guarded
`e2fsck -fn` completed all five passes, returned 0/0 with complete cleanup in
2553 ms, and reported no errors. The attachment was then detached. This final
check establishes the retained filesystem's consistency, not an ART build pass.
