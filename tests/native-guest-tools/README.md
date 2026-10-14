# Native guest commands

The [independent policy commands](policy-guests.md) also provide native tracker,
console, stack-diagnostic, random-hook and public hypervisor ABI checks.

These commands compile and run V directly:

```sh
tests/kernel-gaps/run-native --source FILE --arch aarch64|x86_64 --expect MARKER
tests/kernel-gaps/test-runner
tests/hypervisor/run-vm --arch aarch64|x86_64 [--require-vmx]
tests/amd64-console/run --state-dir DIR
tests/kernel-resources/run --arch aarch64|x86_64 --state-dir FRESH-DIR
tests/amd64-poll/run --state-dir FRESH-DIR --build-only
tests/amd64-exceptions/run --state-dir FRESH-DIR --build-only
tests/memory/run-pagetable --arch aarch64|x86_64 --state-dir FRESH-DIR --build-only
```

Kernel/state selection, independent verdicts, timeouts, original C controls,
build-only selection and the exception fixture's one/four CPU modes remain.
Generated modules use the qualified native compiler producer. Fixture objects
retain their strict warning policy and allocator-import guards. Manifests retain
source/executable hashes, compiler flags and imports. Explicit build directories
must be fresh and remain available after failure; guest artifacts and raw serial
logs remain available after each run.

The supervisor owns its PTY and child, checks every marker, drains final output,
rejects nonzero exits and requires two seconds of settled success for a live
guest. Normal and expected-panic marker policies retain their original rules.
QMP has its one-second socket operations; Ctrl-A x precedes the three
three-second stop phases and TERM/KILL escalation. SIGINT retires the child and
PTY before reporting interruption. An emergency owner also reaps a failed stop.
The child performs only execve/write/_exit after fork; argument strings and
environment pointers are prepared and retained by the parent beforehand.

ARM uses the existing pinned ISO builder and directly launches QEMU with a
private firmware-variable image. This completes the native path: the desktop
boot script starts a Python package server even for a bare fixture init. These
disposable images contain the fixture rather than a package runtime. Networking
is disabled when requested. x86 retains the existing ISO builder and q35/TCG
configuration. Both paths use their own QMP socket and retain the original
fixture sources and assertions. Existing Python import interfaces remain for
other callers awaiting their complete native ports.

ARM firmware variables are copied into a fresh inode with mode `0600`. The V
copier preserves the complete byte content and logical file length while
seeking over zero-filled 64 KiB chunks, then sizing the zero tail explicitly.
This avoids allocating the template's padding on filesystems that support
sparse files. Templates must be regular files; an existing destination or link
is refused, and an I/O/size failure removes the partial image. Each guest can
write its own variables without changing the template. Existing images remain
available to repeated launchers.

Run `v -path 'tests/native-guest-tools|tests/linuxkpi|build-support|@vlib|@vmodules'
test tests/native-guest-tools/guesthost` for the host checks. They cover mixed
chunk boundaries, empty/all-zero files and zero tails, private guest writes,
permissions, existing-file/link refusal, invalid templates and partial cleanup
after a real `RLIMIT_FSIZE` failure in an isolated child.

On 2026-10-14 the 64 MiB QEMU ARM variables template had only twelve nonzero
64 KiB chunks. A real ARM HVF boot of the full mount lifecycle suite passed with
the sparse variables file, which used 768 KiB after boot. Before guest writes,
the complete copied image matched template SHA-256
`b3b855c5a80310168051164986855692d1bdb06e67619856177965cd87c6774f`;
a private write then left that template unchanged. `firmware-exact.log` records
this check and the helper source hash. `firmware-profile.log` records the dense
and sparse post-boot image hashes, which differ after independent guest writes.
Both logs are under `build/development17-20261013`, alongside the passing native
receipt/serial log in `mount-firmware-arm-all-after-a` and host tests in
`firmware-unit-b.log`.
Logical size remains 64 MiB. This changes host storage allocation, not the guest
firmware format; disk savings depend on filesystem sparse-file support.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan hosts pass the original twelve runner
test methods, including all three forbidden userspace markers, a 200,000-byte
final drain, late failure and unsettled-panic timeout. Additional native checks
cover QMP exchange, SIGINT, failed exec, UTF-8 replacement and 100 repeated boots
with stable FD counts and no unreaped children. The eight cold entrypoints pass
outside the checkout.
All seven controller binaries build on the three profiles. Original C and V
poll, exception and both-architecture page-table fixtures build static ELF64
executables with verified machine IDs, guards and manifest hashes on every
profile. Nine additional init compiler profiles, including the linked sandbox
and audit cores, also build successfully. To repeat those builds, run
`build-support/run-v-tool.sh tests/native-guest-tools/check-builds.v`.

Actual QEMU hypervisor fixtures pass on prepared ARM and x86 kernels. Both
report hypervisor unavailable under TCG, so these runs establish boot/syscall
integration without VMX execution. The cached x86 kernel fails the V poll
fixture and original C control at the same line-48 predicate with errno 22.
The two ISOs contain identical kernel bytes. This remains a failing guest
verdict; no new production kernel build or physical hardware run is claimed.

Qualification uses the isolated V 0.5.2 `c6bb06f` compiler described in the
[policy host qualification](../native-policy-tools/README.md). Local logs and
receipts are under `/tmp/vinix-native-guest-qualification-{arm,x86,san}` and
`/tmp/vinix-native-guest-final-checks`; maintained commands do not depend on
those directories. No Python was run.

The init-policy, process-churn, memlock, standalone realtime and N64 instruction-
budget commands share the native serial/command owners. See
[serial-tools.md](serial-tools.md) for usage, comparisons and guest limits.
