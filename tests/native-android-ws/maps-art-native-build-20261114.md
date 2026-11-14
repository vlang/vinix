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

Resource caps remain RSS 629145600 bytes, reserve 1073741824, growth 536870912,
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
