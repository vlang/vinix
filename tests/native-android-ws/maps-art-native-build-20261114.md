# Native ART build continuation — 2026-11-14

Continuation of 801c43674. Maps r84 renders tiles, place details and route/turn
geometry; r85 still fails Google sign-in before credentials after a 10-second
check-in timeout. The imageless AOT source candidate has not been deployed.
No runtime improvement or successful authentication is claimed here.

The isolated ARM64 Linux/Alpine builder now has GCC/G++ 15.2.0-r9 and the
Java/JNI dependency closure installed offline. All 150 cached APKs passed native
signature verification. The V installer additionally checks the bounded URL
plan, manifest membership and SHA256 before invoking APK with networking
disabled. Duplicate, unlisted, altered and Python/PyPy inputs are rejected.
The compiler and remaining dependency transactions passed the original caps
separately: sampled RSS 76042240/220942336 bytes, growth 120791040/465047552
bytes, both 0/0 with complete cleanup. Final inventory is 157 installed packages.
No Python was executed or modified.

The complete original ART archive was extracted onto a separate owned 8-GiB
ext4 work disk. Zero-fuzz patches retain the current 16-KiB ABI/lifetime fixes,
the imageless AOT guard and V generator integration. The applied-input checker
compares complete bytes of six audited ABI/lifetime files, oat_file_assistant.cc
and eleven Makefiles, publishing an 18-file manifest only after every match.
Native r3 input checking passed. Tests reject drift in ABI, Make, AOT and
compiler-flags files without publishing a manifest. GNU Make eval, globbing,
redirection, full patch application and incremental compiler-flags transition
also passed. The buildspec sets ART_PAGE_SIZE=16384 for both C and C++.

The first native build exposed quadratic retained allocations in assembly
constant extraction under `-gc none`: repeatedly slicing a multi-MiB assembly
tail exceeded the 629145600-byte RSS limit. Searches now use absolute offsets
in the original backing string. Escaped ASM_DEFINE templates in GCC debug
strings are ignored; emitted constant validation remains intact. The regression
uses 136 constants between large ignored regions. Host and native helper
self-tests passed; the real 5267846-byte assembly produced the same 124-define
header on host and ARM64, SHA256
`14ba3f6ef96bd5781e7b7b3e075aeb21e91f2cd7732d5f5b8574bd26d3595ef4`.

Subsequent C++ compilation exceeded RSS with debug metadata, and again with
debug metadata removed. The build-only Make overlay now replaces `-ggdb3` with
`-g0 --param=ggc-min-expand=10 --param=ggc-min-heapsize=16384`. GCC's measured
defaults were 100 and 131072 respectively. Optimization remains -O2 and ART
runtime macros are unchanged. Native r4 sampled peak RSS was 531214336 bytes;
its native wall limit still stopped it. This is evidence for the observed
compilation segment, not qualification of the complete library.

Host guard failure initially disconnected SSH without cancelling guest Make.
The new V remote runner serializes builds, stops only a process group whose
worker and leader match the private chroot and exact build cwd, checks process
identity, and requires a native cleanup receipt before releasing its lock.
The controlled cancellation fixture r2 passed: host wall timeout, exactly one
stopped guest group, native child 137 with no native guard violation, cleanup
complete after 1061 ms under its stricter 10-second limit. The earlier failed
fixture remains retained. Pre-controller partial outputs were renamed to
`/work/failed-out-before-controller-r1`; r5 started a clean output tree.

Native r5 was cancelled after the host observed 553512960 bytes of disk growth
in 52695 ms. Native sampled RSS was 451973120 bytes and native disk growth
3051520 bytes. Exactly one guest group was stopped; both receipts confirmed
cleanup. This failed attempt is retained. Host and guest growth measurements
cover different filesystems and do not identify the source of all host growth.
There is no successful complete libart.so build at this checkpoint.

After source/tooling commit 20e7670c1, incremental attempts retained further
objects without changing the checked inputs. Each failure remains a failure:

| Attempt | Stop | Elapsed ms | Guest peak RSS bytes | Host growth bytes | Guest growth bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| r6 | Host disk growth | 201619 | 531025920 | 590249984 | 8835072 |
| r7 | Guest wall limit | 290058 | 494010368 | 377974784 | 11210752 |
| r8 | Host disk growth | 104136 | 527372288 | 601542656 | 3371008 |

All native and host cleanup receipts passed. Host-triggered r6/r8 cancellation
each stopped exactly one matching guest group; r7's native guard had already
stopped its group. The changed oat_file_assistant.cc compiled to a 79184-byte
object, but compilation has not reached a linked libart.so. Incremental objects
are retained for continuation; these attempts do not establish a fresh bounded
full-build pass or a usable replacement runtime.

The native evidence archive was exported and its SHA256 matched on both hosts:
`art-builder-guest-20261114-r5/native-evidence-r1.tar`,
`7b1c53c76783666b9e34bbe4a57d09e413f14dcbc71b7e2d78891e5b28d10cd5`.
It includes native logs/receipts through r8, the applied-input manifest, actual
ARM generator/control binaries and installed APK database. Native archive
creation and guarded host transfer both passed 0/0 with complete cleanup.

The owned builder QEMU19729 was synced and powered off through systemd. UART
records Power down; PID and open-disk checks confirmed it stopped before any
offline access. Read-only work-disk e2fsck passed all five phases, 0/0 and
complete cleanup. A subsequent 20-second host probe with the builder stopped
observed 83849216 bytes of disk growth without exceeding its cap. This shows
host writes continued with this VM off, but does not attribute every byte of
the earlier build-time growth. A read-only shasum attempt then exceeded the
host growth cap with the VM still stopped: 552665088 bytes in 48355 ms,
guard 125/child 137 and complete cleanup. Its failed receipt remains retained.
The existing V/CommonCrypto hash tool subsequently completed both stopped-disk
hashes under the same caps (5451/17786 ms), with complete cleanup. This reuses
a verification tool; it does not select a historical V compiler for any build.
The host has roughly 21 GiB free; repeated growth-limit failures remain the
immediate build blocker. No Maps VM is running.

The stopped disks retain the source tree, exact dependency/header inputs,
partial outputs and installed toolchain:

| Disk | SHA256 |
| --- | --- |
| /Users/alex/.lima/vinix-art-20261114/disk | db1f08c8d25b71b1b4ed31de554e195b220f3edd9463f9a3e31af71e7ad80946 |
| art-builder-work-disk-20261114-r1/work.img | ba74ff92d887aeb459c6bf6ef66534569fa02beb4bad46cfbedf04be5aa40e4a |

Final host receipts are art-builder-work-fsck-20261114-r1,
art-builder-stopped-probe-20261114-r1, art-builder-stopped-hashes-20261114-r1
(failed), art-builder-stopped-root-hash-20261114-r2 and
art-builder-stopped-work-hash-20261114-r2. Root-disk hashing does not establish
a new root-filesystem fsck result. The work disk's read-only fsck is current.

## Latest continuation: r9

Using the same available V 0.5.2 7d74206, the remote runner was rebuilt in
art-resume-controller-20261114-r1: guard/child 0/0, complete cleanup, 3500 ms,
sampled RSS 312279040 bytes. The owned builder restarted as QEMU98364 with the
same 6-GiB/four-CPU configuration and original work disk. A new native r4
applied-input check again passed all 18 complete source-file comparisons.

Incremental native build r9 reached runtime_options.cc before the host guard
stopped it after 27677 ms: 571211776 bytes of host disk growth against the
536870912-byte ceiling. Guest growth was only 253952 bytes; native sampled
peak RSS was 376520704 bytes. The checked cancellation stopped one matching
guest group and both cleanup receipts passed. No linked libart.so exists and
no new runtime was deployed or tested with Maps. The retained input gate,
build limits and account/session authority were not relaxed.

The new V host-write-sample tool reads Darwin process I/O counters and names,
without reading process arguments/files or interrupting jobs. It requires its
own telemetry to be present, matches process start times to reject PID reuse,
and excludes counter resets. Its fixture check and actual 10-second observation
passed under the original caps. The sample saw 726/719 readable processes,
345/344 unavailable processes and 41959424 bytes of filesystem growth. Python,
Brave and FuseCode were among the observed writers, but process byte counters
are not filesystem free-space changes; inaccessible and short-lived processes
prevent complete attribution of the earlier burst. No sampled process was
started, stopped or otherwise controlled by this tool.

Initial telemetry r1 failed its own-process check because the native PID list
used V int. The corrected tool uses explicit 32-bit Darwin PID storage; final
r2 compilation, fixture check and live sampling all passed 0/0 with complete
cleanup. Failed evidence remains retained. Source SHA256 is
`34337af0569dcc640cf4d812570db7af3884dcbecb0e2214e7452b4fb5aef474`;
qualified binary SHA256 is
`57e6c80de3c29fcf70a8a69f3c1aab97b459d733e819caa01f10c3985ec0bd76`.
Evidence roots are host-write-tools-20261114-r2,
host-write-checks-20261114-r2 and host-write-observation-20261114-r2.
The observation log SHA256 is
`c5829271e427115de158363a3ef3941db0c62ed37e716ec4e11077f0a6028b95`.

The r9/input-check addon archive was exported under the original guards, with
matching host/guest SHA256:
art-builder-guest-20261114-r6/native-evidence-r2.tar,
`0e2d57042398de7c764191df49e7929fe5cc1ded6c213747b139513d852095a4`.
The builder was synced and powered off; PID/open-disk checks and UART Power
down confirmed it stopped before offline access. Current read-only work-disk
fsck passed all five phases. Stopped-disk V hashes and fsck passed 0/0 with
complete cleanup in art-builder-stopped-{root,work}-hash-20261114-r3 and
art-builder-work-fsck-20261114-r2. These new hashes supersede the earlier
checkpoint identities above; root filesystem fsck was not repeated:

| Disk | Current stopped SHA256 |
| --- | --- |
| /Users/alex/.lima/vinix-art-20261114/disk | ce5db9199f724e4863c29050def3f3245e4080a273edfcfb4c2e9d9d2cc78d5a |
| art-builder-work-disk-20261114-r1/work.img | 855f2c2d6c781f0b40d9dc08187f4a967ba6cb7a83498cc6420d73a69ffcbc03 |

At the r9 checkpoint, repeated host-growth guard failures remained the build
blocker. The next continuation changes only the host resource profile below.

## Shared-host profile

Continuation after dedc34384. The available V is still 0.5.2 7d74206. Native
input check r5 again passed all 18 files. Incremental r10 reached trace.cc,
r11 reached method_verifier.cc, and r12 was stopped while recompiling that
verifier. All three failed on observed host disk growth; no passing build or
new runtime is claimed. Cleanup passed for every host/native group.

| Attempt | Host elapsed ms | Host growth bytes | Guest growth bytes | Guest peak RSS bytes |
| --- | ---: | ---: | ---: | ---: |
| r10 | 134130 | 566341632 | 1716224 | 428400640 |
| r11 | 95157 | 540749824 | 630784 | 392183808 |
| r12 | 48600 | 542019584 | 0 | 416489472 |

The previous host growth cap measured filesystem-wide changes, including other
sessions' writes. Applying it unchanged repeatedly stopped this build despite
negligible writes to its dedicated guest volume. Recovery of the earlier
session record confirmed its use in host-tool qualification; no explicit user
requirement fixing that value for ART was found in the inspected record.

The ART runner now uses a separate bounded host profile: 4294967296 bytes
growth and a stricter 8589934592-byte free-space reserve. Host RSS 629145600,
wall 300000 ms and output 4194304 remain unchanged. The native guest retains
its original RSS, 536870912-byte growth, 1073741824-byte reserve and output
caps, with the existing 290000-ms wall limit. The original guard executable,
historical audit checkers, source inputs and runtime authority are unchanged.
This is a new profile, not a passing result under the old host limits.

The new runner compiled under the old limits in
art-shared-host-controller-20261114-r1: 0/0, complete cleanup, 3353 ms,
sampled RSS 313147392 bytes. Its cancellation fixture r3 passed under the
unchanged stricter fixture limits: one owned guest group stopped, native
child 137, no native guard violation and complete cleanup.

Under the new profile, r13 successfully compiled method_verifier.cc and
progressed through register-type verification into quick_fillarray_entrypoints.cc.
It still failed: the host guard's disk probe exceeded its one-second deadline
after 115716 ms. Its last sampled free space was 13502820352 bytes and observed
growth 2153525248 bytes. A subsequent df showed only about 5.2 GiB free, later
falling below 5 GiB. The guard failed closed and cancelled one matching native
group; both cleanup receipts passed. Native peak RSS was 415645696 bytes and
growth 3403776 bytes. No linked libart.so or ARM/Maps qualification is claimed.

The host now has less than the new 8-GiB reserve, so another build cannot be
admitted. Admission also accounts for the 4-GiB growth allowance: restore more
than 12 GiB free and a stable write window before retrying. The reserve and
probe deadline were not lowered after this failure.

QEMU52868 was synced and powered down normally. UART Power down, PID and
open-disk checks confirmed shutdown before offline access. Native evidence
through r13, input-check r5 and cancellation fixture r3 was exported under the
old audit caps, with matching native/host SHA256:
art-builder-guest-20261114-r7/native-evidence-r3.tar,
`82c8274581ce6aaa517355c6ed0689309369544811d7ced281c393750f3e2a77`.
Host/native r13 receipt hashes are respectively
`fd3748778f87f131a3484a580ac934d940a52d3e2cc6c9b9bb58876316896303`
and `4cdef8d6c4e41886ffe0d3f5d6eb8ab0a02d01a1c4d9fb47a6084b6832708a11`.

Current read-only work-disk fsck passed all five phases in
art-builder-work-fsck-20261114-r3. Work-disk hashing passed in
art-builder-stopped-work-hash-20261114-r4: current SHA256
`1b5ee5fe8181310ab92a6927148a08eef17cba9dcb0c28e678c499fd828eeafd`.
Both returned 0/0 with complete cleanup. The simultaneous root-disk hash
attempt art-builder-stopped-root-hash-20261114-r4 failed on host growth:
562454528 bytes in 7333 ms, 125/137, complete cleanup. It produced no digest;
the earlier root-disk hashes are historical and do not identify this current
root image. No current root-disk seal or root-filesystem fsck is claimed.
The full source, generated inputs, dependency files and incremental objects
remain on the stopped work disk. No test VM is left running.

## ART library staging preparation

The next continuation adds VINIX_CURRENT_ART_LIBRARY to maps-current-guest.
It stages the selected libart.so and records its actual SHA256 at the guest
library path in deployment inputs. Selection is optional, preserving existing
SDK/native/core/TLS/controller staging. The helper requires a bounded regular
ARM64 shared object, libart.so SONAME, no interpreter, valid 16-KiB-compatible
load segments and a private-origin search path. It compares selected/copied
bytes before publishing the input hash and refuses an existing destination.

The baseline ART uses DT_RPATH=${ORIGIN}, which the general ELF checker
deliberately rejects. The ART-specific inspection path permits only $ORIGIN
or ${ORIGIN} legacy RPATH; the general checker still rejects every legacy
RPATH. Both RPATH and RUNPATH together are rejected. This inspects original
bytes without rewriting the ELF. Source provenance, companion-library symbol
compatibility and the signed ARM runtime regression remain separate required
checks; staging shape alone does not qualify a rebuilt runtime.

The focused ELF suite passes its original mutations and new page alignment,
executable/SONAME, search-path ambiguity, strict-checker preservation,
symlink/oversized input, overwrite and input-hash controls. With
VINIX_ART_TEST_LIBRARY pointing at the existing baseline ARM library, actual
copy/readback and recorded-hash comparison also pass. The new stager compiled
with available V 0.5.2 7d74206. No rebuilt ART or new Maps guest is qualified by
these host checks.

Final compile/test receipts use the shared-host profile (RSS 629145600,
wall 300000 ms, reserve 8589934592, growth 4294967296, output 4194304),
all 0/0 with complete cleanup:

| Evidence root | Elapsed ms | Sampled RSS bytes |
| --- | ---: | ---: |
| art-library-stage-tests-20261114-r5 | 2844 | 344588288 |
| art-library-stage-checks-20261114-r3 | 380 | 13959168 |
| art-library-stage-host-20261114-r3 | 3071 | 368803840 |

Stager SHA256 is
`ca475ab6e43689d05dd198dbf463b97bfdeb2ad2b9066a71b9bcce6455d9c51b`;
test executable is
`5fbcc8e1ef80b03b7be0facdc5c8f99ff05e2690033f45d8ce7612b090dcb864`.
Earlier failed evidence is retained: missing module search paths on r1,
baseline legacy-RPATH rejection on the first real-library check, and r4/r2
compiles stopped by the old filesystem-wide growth limit. They are not passes.
No retained image or audit bundle was deleted or archived during this work.

The original profile used RSS 629145600 bytes, reserve 1073741824, growth 536870912,
output 4194304 and host wall 300000 ms. The guest uses the stricter 290000-ms
wall limit to leave cleanup time. Make uses -j1. The source is ART
e78bf68917bcaaf58fef3960cd88793b3b7f39cc; this is the runtime source being
rebuilt, not a V compiler pin. Earlier helpers used then-current V 0.5.2
39e0e79. The final installer host build and self-test passed with the now
available V 0.5.2 7d74206, executable SHA256
`c1a30c20cd9612350b4a70a56c25089f8de4fc13aa8a7c2ae52540da726be385`.

External evidence is under `/Users/alex/.local/state/vinix/android/`:

| Evidence | Location / SHA256 |
| --- | --- |
| Package manifest | art-builder-packages-20261114-r6/packages.json / b43903ddefe698e872f0d4c8278c8a39dee46b272ff46f3e9f41f2f3b5456ab8 |
| Installed inventory | art-builder-guest-20261114-r4/installed-packages.txt / 0da98348c7f644eaaf70d211d85daf188bde85c6aab3f819f7841c6c636fc799 |
| Native installation receipts | art-builder-guest-20261114-r4/guard-evidence.tar / ae97f806d3abc76330fe2e84e645704a8706e59804234ed81a0c8145c282a376 |
| Exact Make overlay | art-make-checks-20261114-r6/overlay/v-generators.patch / af18d5968e7c6780780f713457b051bb460265213e774cc06faa521eb845dc04 |
| Make input manifest | art-make-checks-20261114-r6/overlay/inputs.json / e7986960fdaa4c31413865a9bcb5e709b324ff2ede677ac9be59d546e5750bf2 |
| 16-KiB buildspec | art-make-checks-20261114-r6/overlay/art16k-buildspec.mk / 0e10b8c5338a6ca28557b02a309209f67fdce57735b7a44c90e262e0d4e6c073 |
| Cancellation native receipt | art-native-libart-build-20261114-cancel-fixture-r2.native.json / b4b31907a1a4e2c1a5e1a2af12d503feb47584804295a11b392f587950ca0062 |
| Failed r5 native receipt | art-native-libart-build-20261114-r5.native.json / 2f7a8d4b0a3cfc508302f9d207bcd4de0cafa04483e16992f3937548561de209 |

Passing check roots/receipts include art-make-checks-20261114-r6,
art-asm-memory-checks-20261114-r2, art-asm-memory-arm-checks-20261114-r1,
art-native-input-check-20261114-r3 and art-control-final-checks-20261114-r1.
Generated assembly, compiler argv/dependency files and partial objects remain
on the owned work disk. All failed build receipts remain outside Git.

Next: finish guarded native compilation, retain and inspect the exact ELF and
dependency inputs, stage the complete runtime closure, run the signed ARM API
regression and retry real Google Maps sign-in in a fresh protected session.
