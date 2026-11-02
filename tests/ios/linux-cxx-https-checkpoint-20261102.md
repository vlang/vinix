# Linux C++/GLES, HTTPS and guarded app-probe checkpoint — 2026-11-02

**All four fresh Linux captures passed and are audited. The complete main archive and audit companion passed local restoration checks. External preservation is blocked pending explicit payload/destination approval.**

## Linux outcome and current qualification

The GNU/Linux path executes real ARM64 GNU/glibc runtime binaries under QEMU
on a Linux x86-64 host. Fresh HTTPS, C++, combined C++/GLES and plain combined
runner captures all passed and were independently audited. Their source versions,
fixture limits and complete local archive identities are recorded below.

**Fortnite remains at its historical 4/8 launch gates.** The original full app,
bundled frameworks and cooked assets are absent. No fresh Fortnite execution,
frame, menu, login or gameplay is established. Ads remain skipped. Synthetic
entry, GLES pixels and fixtures do not advance a game gate. No native Apple
Foundation comparison was executed.

## Accepted fresh target captures

HTTPS and C++ qualify b5cd3a7. Combined GLES and the plain runner qualify
7e2ee13. The later fix only changes GLES linking; HTTPS/C++ were not rerun at 7e2ee13.

| Fresh capture / source | Runtime checks | Full driver | Required markers |
| --- | --- | --- | --- |
| `https-r2` / b5cd3a7 | 495.486049203 s ordinary / 474.844921583 s deterministic, PASS | 1238.744159267 s, PASS | 26 in each run |
| `cxx-r1` / b5cd3a7 | 11.846312623 s ordinary / 12.026416810 s deterministic, PASS | 295.540265082 s, PASS | 6 in each run |
| `cxx-gles-r2` / 7e2ee13 | 55.888211714 s ordinary / 55.724872852 s deterministic, PASS | 382.988270309 s, PASS | 5 in each run |
| `runner-cxx-gles-r1` / 7e2ee13 | Help/inspect 0; synthetic entry/extra arguments 37/99 | 129.777751690 s, PASS | Not a runtime fixture pair |

All accepted capture guards were clean; the HTTPS target remained mode 0755.
The C++ native ELF reference exited 0 in **0.282827357 s**; valid, invalid-vptr
and invalid-function controls exited **37/1/1**, with required separate diagnostics.
GLES reported **softpipe, OpenGL ES 3.1 Mesa 24.0.5**. Four **60×48** fixture PPMs
have the same SHA-256:
`184d5099b396f5178e4c167f496876e4fd04f23b211e9da24ef7c80f96b12706`.
These are actual fixture pixels, not Fortnite frames.

| Fresh audited capture | Files / directories / bytes | Inventory SHA-256 |
| --- | --- | --- |
| `https-r2` | 1437 / 26 / 182210553 | `1704835bf9c93e34ca6c7ad72b9c59815ff3d74f73a199c8b497d881ebc94066` |
| `cxx-r1` | 1585 / 35 / 193581950 | `aa6517fca7b5a1068cac65d2a97f9b2e61e22af8344aa3cb580b113217bd544c` |
| `cxx-gles-r2` | 1507 / 36 / 187433896 | `1404599afc264a91f81486596a50a682189125cd13a6286f88630b3fcccf95ed` |
| `runner-cxx-gles-r1` | 1512 / 35 / 76801688 | `d39528065afa99be303d4dd43ad6b6ff739a165301bc0e245583dff6a4fbae6e` |

HTTPS's six typed source trees and two individual files matched b5cd3a7
literally. C++'s six ordinary source trees and three files also matched literally.
For `build-support/ios`, `cp_all` expands five tracked root aliases and nested
`tarstream`/`tarcore` links. The root has 18 names, including 12 regular files;
the expanded capture has 57 files, eight directories and no links. Complete
resolved bytes, names and modes were verified. **This is not literal equality
with the original symlink tree.** Two historical-comparator symlink rejections
remain retained. Full b5cd3a7 source-archive SHA-256:
`0cf51cebf027b531036c44b12a694dac67c6d6d643762e330a331623a55bf6cb`.
Complete combined/runner source checks match 7e2ee13, including the same qualified
resolved-alias comparison for the builder. Full 7e2ee13 source-archive SHA-256:
`655762ee7aceb9f68be84f11b02d939e97b574bffe47ab6970028fb1641cd274`.

## Accepted local main archive and blocked remote delivery

`DELIVERY=/workspace/scratch/6384ba2a563f/vinix-ios-linux-recovery-delivery-20261102`.
The main archive is complete locally in three ordered parts under
`DELIVERY/main-parts-r2/`, with filename prefix
`vinix-ios-linux-recovery-evidence-20261102-r2.tar.zst.`.

| Part suffix | Bytes | SHA-256 |
| --- | ---: | --- |
| `part01` | 471859200 | `6cce59e3fece6c171740467046c6bc468d54652aa2a403264e81c56325d1321a` |
| `part02` | 471859200 | `a34748906d3c56e60e5365e09033880ead74c2b94fba047b055d1cc15b44eba7` |
| `part03` | 305157562 | `6a777eb225210c88d50ba39837cf86dc893f38652cc4163ae0ba040097b3c784` |

The concatenated **1,248,875,962-byte** compressed stream is valid; SHA-256:
`d4a6a22d3954653ae4d48791a9c89f81cd4a2b86e1b959f25d222399c578dcaa`.
Its decoded **3,806,986,240-byte** tar exactly matches the original, SHA-256:
`01cf89af6396ec9e5f2b23b9346022b9758b6c1e5dc07274184d60043c5208ea`.

Isolated `/tmp` restoration r4 **passed** both frozen-manifest verification
and the unchanged full-tree comparison against original STATE: **51,827 regular
files, 3,749 directories including root, 653 symlinks and 5,161,208,498 file bytes**.
Frozen manifest SHA-256:
`a73a906f51c6263a52030baa4070362a80d5a06344047a4162c638d066206689`.
Guards were clean. Receipts are `commands/payload-restored-manifest-verify-r4.*`
and `commands/payload-restored-full-compare-r4.*` under AUDIT.

All four restored capture inventories match their original hashes. All six
original/restored typed-tree comparisons passed, including rejected `https-r1`
and `cxx-gles-r1`. All ten guards reaped children, completed cleanup and left
zero descendants. Original and restored auditor binary hashes match;
receipts are `capture-audits/restored-r4-*`. These are archive checks, not new
runtime executions.

**Automatic approval review rejected the external upload before PUT.** Its
stated reason was that general evidence-preservation authorization did not
explicitly approve transferring this source/SDK/diagnostic payload to ChatGPT
Library. Only upload reservations were prepared: no transfer, finalization or
new saved Library IDs occurred. See `external-upload-rejection.json`.

Explicit approval is required for the three main parts above, the companion
audit archive below and the final publication receipts, to the stated
**ChatGPT Library** destination. Remote preservation remains
**BLOCKED_PENDING_EXPLICIT_PAYLOAD_AND_DESTINATION_APPROVAL**. Local verification
does not establish durable remote saving.

## Audit companion and final receipts

The complete companion is
`DELIVERY/vinix-ios-linux-recovery-audit-20261102.tar.zst`,
**18,715,653 bytes**, SHA-256
`b83e3d400b089918a9b76d372c90b62a8375c315a5b98d07ce8b9d53cb488197`.
Its uncompressed tar is **173,649,920 bytes**, SHA-256
`c0ee9e64409df5592ef8c5fb3dbf4b5e371236b8fc0f47b93ba599cf2709e502`.

GNU tar creation and `--compare` against both the original audit tree and a
fresh isolated restoration exited 0; the compressed stream check also passed.
All accepted guards reaped children, completed cleanup and left zero descendants.
Every audit-tree entry is retained, including its deliberate FIFO corruption
control and the earlier nested control archive. The supplemental V full-tree
snapshot correctly rejected that FIFO; its contract remains unchanged. The
companion's comparisons use GNU tar and do not claim a V full-tree manifest.
An initial compression command rejected an unsupported output option before
writing an archive; the corrected invocation and its receipts are separate.

`DELIVERY/final-receipts` holds the complete packaging, comparison, member-list
and final publication receipts. Those records are outside the frozen companion
to avoid a self-referential archive. The companion includes the external report
draft from before its own packaging; this tracked report supplies its final identity.
The accepted main parts plus companion total **1,267,591,615 bytes** before
the separate final-receipt package. No new external save is claimed.

## Published implementation

| Published commit | Scope |
| --- | --- |
| `ac922ebf048e25b9a1e4d0365b7f4cc77b692d48` | Approved storage of prior GLES evidence/audit bundle |
| `c1debc2d3171f8bd7f8d529b365d2815366f019e` | Apple-facing C++ ABI for ARM64 GNU/Linux |
| `023102769976100363de52fbb6bfc99596c3de44` | Retire Linux registrations after native C++ joins |
| `f225c99814969c5ec249d12761761996acf44887` | GNU/Linux system HTTPS trust selection |
| `4b5fabaaf83e9638bd29c3d0dda7f115fa58af84` | C++/GLES execution, guarded probes, evidence checks and guide |
| `b5cd3a7eb11e82431a04155912bd66e026041dfa` | Validate produced ARM64 executable modes/metadata before and after launches |
| `7e2ee136f101681ed6a0f2f1fe6eeb0008383666` | Link exact validated EGL/GLES libraries without a broad SDK library search |

Newest qualified runtime code tree: `534fa9b8b62d34531b8e9e1e88e9dfa915368554`.
Fresh source-policy checking from `fcee5f780796f6df200eb4a44430741b16c80d8e`
through `4b5fabaaf83e9638bd29c3d0dda7f115fa58af84` passed with clean guard
cleanup; receipts are `AUDIT/commands/source-policy-r2.*`.
The new code also passed `source-policy-r3` with a clean guard. Reviewed local
commit `44e04a6e63c109428e8db4d8c0e89f1dc9c64fb6` remains on its prior branch;
the fetched published b5cd3a7 tree was verified identical. The GLES fix's reviewed
local commit is `9e76ebb9da4188402af2018f9241f74b627611ea`; published code is
7e2ee13, and `source-policy-r4` passed.
The broader PR includes the earlier [Linux core](linux-runtime-checkpoint-20261101.md)
and [GLES/initializer](linux-gles-checkpoint-20261101.md) checkpoints.
At the latest code-status receipt, PR #271 remains open, draft and unmerged at
7e2ee13. Its actual kernel workflow `41407831627` is queued, with no conclusion
(`AUDIT/ci-code-7e2e.json`); no CI pass is claimed.

## Runtime semantics and qualification limits

The V GNU builder adapts pinned LLVM 19.1.7 libc++/libc++abi/libunwind to the Apple-facing ABI. The C++ fixture covers 232 exports, two lifetimes, strings,
sorting, Darwin ctype/TLS, wide conversion/fpos canaries and 32 joins per pass.
The join bridge retires a registration only after normal native return. The original C++ reference is unchanged: V generates exactly two raw-storage
constructor destinations with once-only RAII destruction, retaining every
CHECK and later code. There is no production string change or unpoisoning.
Combined mode selects GLES with C++ linked; separate C++ mode supplies ABI tests.

HTTPS selects installed system trust, falling back only on a missing candidate.
There is no environment trust override. Loopback tests capture selected public
CA bytes and do not install trust or contact game services. The unchanged
five-second shutdown-operation watchdog starts after runtime initialization;
the outer 600-second guard remains. `probe-no-ads` requires a real full app,
main and matching plist, inventories its untouched layout before/after, and
separates app/wrapper status from COMPLETE capture status. Its diagnostic VAPP
peer supplies no compositor/input or guest memory cgroup. See [guide](linux-host.md).

The existing request-cookie correction remains present: an unset request inherits
the configuration, while an explicit request policy takes precedence. The Linux
HTTP fixture exercises disabled automatic sending/storage, manual Cookie headers,
copy isolation and no replay of response cookies. No cookie jar or persistence
was added; automatic and partitioned cookies remain unsupported. Method
normalization includes `OPTIONS` and preserves lowercase `trace`.

Caller ASan/UBSan and assertions remain enabled. Only libc++abi `private_typeinfo.cpp` omits its recursive vptr check; ASan/other selected UBSan
checks remain. The low-level ELF unwinder and packaged Mesa are uninstrumented;
plain runners are unsanitized. Private static UBSan/C++ linkage excludes their
DSO exports and rejects direct shared libstdc++/libubsan; complete populated ELF
tables are required. Mach-O unwinding, video, text and SQLite remain absent;
Metal returns nil. These captures do not qualify native ARM64 hardware or a full
Vinix VM boot. New maintained implementation, generators and helpers are V.

## Fresh host checks and driver

Six maintained host suites passed under native x86-64 ASan/UBSan with
`-O1 -g -pipe`, assertions enabled and no test filters: **31 cases / 241 assertions**.
The five-suite summary accounts for 26/208; the separate GNU builder receipt
`host-builder-checks/result.json` adds 5/33. No sanitizer findings or V diagnostics
were reported; LSan was disabled. Guards reaped children, completed cleanup and
left zero descendants. These are host checks, with no target/game execution.

| Fresh suite | Cases / assertions |
| --- | --- |
| C++ profile/header/native-adaptation | 8 / 44 |
| Static UBSan selection/copy | 2 / 10 |
| ELF linkage parser | 3 / 31 |
| App-input/capture | 8 / 89 |
| Diagnostic desktop wrapper | 5 / 34 |
| GNU C++ builder (separate receipt) | 5 / 33 |

The five-suite `host-checks/summary.json` records source snapshots and generated-C
readback. All 29 selected source files match before/after; inventory SHA-256:
`bb72cfac60b091fd1438ee6f5d5a271797e7ab9e4541a9f742928b0d7f5074f9`.
Recovered driver `linux-checks-r1` built in **14.885073758 s**, exit 0, with a clean guard; SHA-256 `644fc1e97dac1fb03c67b2382cbe34f02abf28946944091ddb560c908998cfa8`.
Driver 1 missing-app and invalid-deadline controls each exited 1 before creating output
directories, with clean guards. The unchanged maintained inventory auditor
accepted 1 valid control and rejected all 19 corruptions in fresh output.

The final mode/probe/desktop host group passed **20 cases / 150 assertions**:
new executable checks **7/27**, repeated probe **8/89** and desktop **5/34**.
Those repeated cases are not added again to the earlier **31/241** total.
Driver 2 built in **14.790026932 s**, exit 0; SHA-256:
`1c89ec2d52164c24aff64f2e018ad4d2fca175f65b8625dcfea4db56af4fe402`.
The GLES host suite passed **8 cases / 43 assertions** in **14.423007573 s**.
Driver 3 built in **15.301963072 s**; SHA-256:
`e7a5a3c6e49fb2f941b62c06b56ee12300459aa45ba67ea64aa9daea766af96e`.
Host/driver checks remain separate from target capture outcomes.

## First fresh HTTP attempt — rejected and unsealed

`STATE/captures/https-r1` remains unchanged and rejected/unsealed. Ordinary
runtime passed in **473.361913226 s**, exit 0, with all **26 markers**. The
deterministic attempt exited **1 in 0.110761582 s**, with an empty log
before guest startup. This attempt does not qualify a complete capture or fixture pair.

Produced `run-ios` had lost executable bits and was observed as **0644**;
upstream QEMU 8.2.2 review and native strace confirm startup rejection. The cause of the mode change is
**unknown**. Simple sandbox/native read/write controls did not reproduce it. A
separate 0755 diagnostic copy reached guest tests, then was deliberately stopped
by an **18-second guard**; it is not PASS.

The published fix validates produced-target mode/identity metadata and ARM64
ELF headers before/after launches. Timestamps have second resolution; these
checks are not content hashes or an atomic guarantee. There is no chmod repair
or automatic retry; existing statuses/deadlines remain.

## Fresh combined GLES attempt — rejected before execution

Fresh `cxx-gles-r1` failed linking with exit 1 after **253.402660608 s**; no guest
ran. A broad SDK `-L` selected a native-layout `libm.so` linker script outside
the cross sysroot, which could not find `/lib/aarch64-linux-gnu/libm.so.6` and
`libmvec.so.1`. The published 7e2ee13 fix links exact validated EGL/GLES libraries.
An independent real-link diagnostic used the same 15 inputs: baseline exit 1,
fixed exit 0. Its result SHA-256 is
`767c6db0c555700fbbc66bed5fa8f8108ab9342af18e55305a6649bc543102a1`.
The complete failed capture, **1,477 files / 135,072,302 bytes**, was verified
unchanged. It remains a failed link attempt, not a render result.

## Preserved archive rejections and observations

The first compression command/guard exited 0, but the later compressed candidate
was **1,045,286,912 bytes** and `zstd --test` rejected premature end. Its SHA-256
is `c8ba58eac37ef2f7c149c6568d4ec5f27d382d4177373f744b6fd845d85e4df1`.
It was proved to be the exact prefix of the accepted stream; its failed bytes
are therefore recoverable from the accepted part set. The cause is **unknown**.

The first part-directory snapshot failed with `ENOENT`; a fresh traced snapshot
passed with the unchanged auditor and included additional transient entries.
No root cause or helper defect is established. Workspace restorations r2/r3
were rejected as nonquiescent when full-tree audits detected directory changes
after tar exited. Those rejections and logs remain preserved; checks were not
weakened. Accepted isolated restoration r4 is recorded above.

## Earlier capture loss and observed results

A workspace reset removed the prior new captures, expanded inputs, receipts and
drafts after implementation publication to PR #271. Four runs had passed and
been independently audited, but **were lost before a complete new standalone
archive existed: they were not archived, restored or durably saved**. Their
recorded identities cannot replace their unavailable payloads. The fresh accepted
captures above are separate recovery evidence; older saved archives are listed below.

These historical values came from completed receipts and independent audits;
they are not fresh acceptance. Target execution was ARM64 GNU/glibc ELF under
QEMU on Linux x86-64. The runtime source copies matched the repository.

| Lost capture | Observed ordinary / deterministic execution | Full driver |
| --- | --- | --- |
| `cxx-r3` | 13.587676581 s / 14.373951567 s; exit 0, six markers | PASS, 302.895974722 s |
| `https-r2` | 497.472608566 s / 475.166153199 s; both PASS | PASS, 1238.913101662 s |
| `cxx-gles-r1` | 41.927898461 s / 43.055741504 s; both PASS | PASS, 348.027026516 s |
| `runner-cxx-gles-r1` | Help/inspect 0; synthetic entry/extra arguments 37/99 | PASS, 124.858490687 s |

| Lost capture | Audited files / directories / bytes | Recorded inventory SHA-256 |
| --- | --- | --- |
| `cxx-r3` | 1579 / 35 / 193567355 | `85218de1e3c63aaa05c41cc6be4952eb198b5f25369a362926de66f73cface2f` |
| `https-r2` | 1433 / 26 / 182162674 | `048483676bbb065810acf02cf029be0c1fcabf76fe4edcc124a6a65ed4a0665b` |
| `cxx-gles-r1` | 1504 / 36 / 187359316 | `253610aa55fab17daa7b43f46e9cf4d481266a158e9b7f0afa702a39cd15f71d` |
| `runner-cxx-gles-r1` | 1509 / 35 / 76716147 | `4fb71678ef3b8dd6f7fc4afce2a90f394fce847b5c69207ecb83e36b1f0aeddf` |

The lost C++ native reference exited 0; independent valid/vptr/function
sanitizer controls exited 37/1/1 with expected diagnostics. Those receipts,
the old focused host results and earlier diagnostic logs were also lost.

## Fresh recovered inputs

`STATE=/workspace/scratch/6384ba2a563f/ios-linux-recovery-20261102`;
`AUDIT=/workspace/scratch/6384ba2a563f/vinix-ios-linux-recovery-audit-20261102`.
The exact frozen source is `c6bb06f5c04d78f9f6d22a57c257d27e835ba40a`. Acquisition used signed Ubuntu Noble/Noble-updates indexes, verified with key
`F6ECB3762474EDA9D21B7022871920D1991BC93C`. Packages were checked against index
sizes/SHA-256 and privately extracted; no installation or maintainer scripts ran.

Base SDK selection contains 35 packages / 73,804,476 download bytes: GCC 13.2.0-23ubuntu4cross1, binutils 2.42-4ubuntu2, QEMU 8.2.2 and target glibc
2.39-0ubuntu8cross1. Clang selection contains 86 packages / 133,127,646 bytes;
static UBSan selection contains 13 / 14,416,900. These are selected concrete
Depends/Pre-Depends closures, excluding Recommends/Suggests. Exact plans,
signatures and receipts are in `acquisition-base` and `acquisition-cxx`.

| Fresh selected input | SHA-256 |
| --- | --- |
| Frozen `V 0.5.2 c6bb06f` executable | `95eefd7c73275614653afe87745364bd2d197880639dc57d0d82fa192a7e71d7` |
| GNU ARM64 GCC 13 | `8487ff08df4a785d6f596663a0b1416afe18638c75cf5fa34f036e3d51324515` |
| QEMU aarch64 static | `10675c4a3df1b2ab279a4ff808fac00e158eede951884a3094c796e41e64e685` |
| GNU ARM64 readelf / assembler | `f7312ca383fd8bffd246e02b75718ab2675eb1241ba6945d3f4ad8857e691e0a` / `68132279f9d768ecfac383270213c2f857601996e0b7ef476a2f3533bae36ccd` |
| ARM64 glibc loader | `142f02374792bf5f62293efc3500d472dbbe280dc658cc60480eff73ad46f33c` |
| Clang 18.1.3 executable | `8ef402d453d1ba4902e4ee0f0f847f6cfa01400c95aa43c24e97818b9c0e3f45` |
| LLVM 18.1.3 archiver | `eedd2efbdee80acf60e17e10adeddf31be0347226245f935be95efa3ae00ec79` |
| Explicit ARM64 GCC 14 static UBSan | `eea148b731edcd92060363fbdcee706e577a3b89103117c5f592b448c2b88730` |
| New private libarchive 3.7.2-2ubuntu0.9 | `2d8605282b26359a0994017373bff09fc7c9a6ed9ab7e1a4fd980b8ffcf1cd40` |

Clang, llvm-ar and static UBSan match their previous recorded bytes. The private
libarchive input is newly selected; no equivalence to the lost host input is
claimed. Complete Clang/UBSan SDK inventories and 254 Clang resource headers
are recorded. Acquisition checks compiled/archived ARM64 relocatable assembly,
but executed no ARM64 program. Actual host interpreter identity is recorded;
a complete native loader/DSO closure or hermetic compiler is not claimed.

| Fresh GNU C++ build | Duration / exit | Manifest SHA-256 |
| --- | --- | --- |
| Sanitized `asan-r1` | 72.171642167 s / 0 | `496fa2b65426b95b8df4b5b2f9a281d86fefd7a02271fa417d649b2a19336d8d` |
| Plain `plain-r1` | 44.458120666 s / 0 | `bdc6c4df5d23a09da30152d33eaddd8384bad30151a660d7263939135bc24503` |

Both builds completed with clean guards; frozen inputs remain unchanged.
These completed dependency builds do not themselves establish a runtime fixture pass.

The recovered Mesa SDK snapshot records **2,543 regular files, 294 directories
including the root, 129 symlinks and 1,659,914,666 regular-file bytes**.
Full-tree manifest SHA-256:
`1724b55d7333b4c6879617272809e9fe122651cf7037a8d7660249f4f18f5ebd`;
package-plan SHA-256:
`2295fab29d954e296e69dd8716104c7b218fb33c5b0b0b61e7919f9525c2f6f1`.
This pins the selected SDK tree; it does not qualify rendering or a host DSO closure.

## Archive controls and capture acceptance

The supplemental V complete-tree helper passed **4 positive / 28 rejection**
controls in both ASan/UBSan and O2 builds, preserving root/empty-dir modes,
regular bytes and literal symlinks. FIFO/socket scans were real; device-node
creation was denied, so character/block checks explicitly cover mode dispatch.
A generated named-root tar restoration passed compare/verify without repairs;
the rejected `./` root-mode control remains separate. These are tool controls,
not acceptance of the real archive. Final helper source/binary SHA-256:
`a61814225bc5e302049ad9983200edbd58035486ee65b081125c80fe6b4a4487` /
`f38a18d33418850d7595858d0f117d8f4e320d74eab5eb10fbe5013470e4fa70`.

## Earlier saved archives

| Previously saved archive | Bytes | Recorded SHA-256 |
| --- | ---: | --- |
| `vinix-ios-linux-evidence-20261101.tar.zst` | 861792432 | `958b3f61e5e1bb0ed6a1ee938f1903c5e2bcdc91f471321dfca9a8a2b80b772d` |
| `vinix-ios-linux-gles-evidence-20261101.tar.zst` | 515117768 | `cbc90afa0f531dd8547463430019b7f1670e8db92e56ae418e942c11d9dba461` |

Prior Linux delivery used two saved parts; the prior GLES archive/audit were also saved. Audit SHA: `511214cd36fdbde315e2d115c299d813760707dc345515c153cc27f5d02a7280`.
Those references survive; their payloads were not materialized/re-audited in
recovery and do not contain the earlier lost captures.
