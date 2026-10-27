# Maps onboarding trace controller overlay

`maps-onboarding-trace-stage.v` replaces only the diagnostic account controller
and its desktop launcher alias over the sealed `maps-broadcast-result-r2` image.
It appends `maps-onboarding-trace-diagnostic.tar` with exactly three regular
files: both identical controller executables and the deployment `build.json`.
The deployment changes only the two controller input hashes. Its framework,
JNI, runtime, APKs and security roles retain their exact existing identities.

The base manifest is
`98522d60a7627927b7ee6b861db502b6574e3d6ab14fdecb09e2da38b2f441de`.
Preparation verifies the complete base and all twenty-six inherited sealed
bundles before and after staging. The fourteen existing modules retain their
hashes and order. Every preceding overlay contributes to the inherited inode
mode audit. Preparation uses APFS clones without a full-copy fallback, bounded
streaming media checks, a 1 GiB reserve and a 512 MiB disk-growth limit. The
source closure, tool identities, command receipts and output checksums remain
in the external stage bundle.

Disk growth accumulates observed volume drops during writable phases without
refunds. Only the initial and final complete-input audits refresh the available
space baseline: these audits read immutable inputs and write no stage files.
The 1 GiB reserve is enforced at both ends; preflight still requires 1.5 GiB.
Other sessions' writes during writable phases remain conservatively charged.
Command and module-hash receipts are writable phases. The final receipt and
seal writes receive a final disk check printed to the external preparation log.

Build and self-test one tool at a time with the pinned V compiler and Boehm GC:
Record peak RSS and swaps with `/usr/bin/time -l`. Image preparation and kernel
patching need an outer file-size limit of at least 16 GiB for the existing boot
image; the stager's reserve and growth guards remain enabled.

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod \
  -gc boehm -nocache -cc cc \
  -path '/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib' \
  -o /absolute/external/maps-onboarding-trace-stage \
  tests/native-android-ws/maps-onboarding-trace-stage.v
/absolute/external/maps-onboarding-trace-stage --self-test
/absolute/external/maps-onboarding-trace-stage --prepare /absolute/external/fresh-stage
```

Keep the existing stage immutable. Use `clone-maps-account-stage.v` to make a
fresh mutable copy, then the kernel patcher's separate `--maps-onboarding-trace`
profile to install the already validated frozen pidfd kernel. That profile
requires the exact base, new controller producer and fourteen original module
identities; earlier profiles retain their original requirements. The existing
bounded lifecycle runner can boot the fresh copy with 12 GiB and one VM.

Start the guest account controller with
`/opt/vinix-maps-account/bin/maps-account-guest --broker --trace-onboarding`
before launching Maps from the desktop. This opt-in records view trees and
threads in the existing private Maps log. The regular account-result export
continues to exclude that log. This diagnostic overlay establishes no Google
authentication result; runtime evidence must be recorded separately.
