# Wine pledge continuation, 2026-11-12

Continued the uncommitted kernel work in
`/Users/alex/.cache/vinix-wine-pledge/wt`, based on `24820e5a3`, after inspecting
the newer package changes in `6685159f3`. The kernel source matches the current
`554908ef4` baseline apart from the dependency download URL and these pledge
edits. Both production architectures were already built in that isolated
worktree; the saved ARM and x86_64 executables were used for fresh tests.

Pledge now admits `FS_IOC_GETFLAGS`, its 32-bit request number, and the two
VFAT directory-read requests with `rpath`. These are four exact read requests,
not a whole ioctl family. Unsupported requests still reach the filesystem's
`ENOTTY` response; flag changes remain forbidden. The first violation report
also includes the syscall's second register argument, identifying an ioctl
request or fcntl command on both architectures. The existing report prefix is
preserved.

The production [V guest](../openbsd-security/ioctl-guest/main.v) passes all
20 controls on both targets: ordinary UID/GID 1000, admitted queries, missing
`rpath` with `error` returning `ENOSYS`, missing `rpath` without `error`
terminating with SIGABRT, sign-extended request numbers and refused writes or
neighboring commands. The original ARM kernel at
`build/pty-kernels/aarch64/vinix` fails the first query control with child exit
83. This baseline failure is retained.

The unchanged OpenBSD security fixture passes on both targets, with all exact
feature counts, the ARM pledge report and packet-randomness verdicts. The new
[media controller](../openbsd-security/media-check.v) uses the working FAT
boot path on ARM and invokes the original serial/packet judges in a separate
process. A passing ARM serial log with an empty capture refuses. The legacy
ISO controller still stalls in firmware, including a TCG retry with
`vinix.qemu_platform=1`; its failed log is retained. Two redundant `poll`
declarations were removed so the current V compiler uses `os`'s platform
signature, including Darwin's 32-bit `nfds_t`.

The fresh `native-arm-current-01` run passes the maintained signed Win64
console fixture using the saved ARM kernel and the source-built translator
`21bbd59fb9be632214a1c0fcc73624bf568ea525dd11762513a1faa0334eca83`.
It rebuilds the guest and package CLI, installs a locally signed package and
checks its ordinary account, private prefix/socket, Windows API calls,
outside-write refusal and natural child exit. It also observes a refused
network socket in `wineboot.exe` and Wine initialization warnings. The probe
passes despite those warnings; this does not qualify every Wine process.

The unchanged historical `wine-native-retain` refuses both the older
`native-arm-k2` and fresh run because the prepared producer inventory's
`/Users/alex/.cache/vinix-wine-build/wine-build` digest has changed. Neither
retention output was created. The original checker and prepared inventories
were not weakened or resealed. The fresh run passes its own selected-input
postchecks, but a complete newly admitted producer chain remains required.
The host controller uses the previously retained compiler at
`/Users/alex/.cache/vinix-wine-build/v/v`; the new security controllers use
`/Users/alex/code/v/v` (`f2edf66`).

Section 14 remains open: this is local console execution and pledge regression
evidence. It does not establish a qualified redistributable Wine catalog,
graphical Calculator execution, the detached wineserver lease interval,
complete corresponding source, hermetic builds or guest shutdown. The separate
compiler-consumer checkpoint still lacks three historical compiler files.

Retained evidence is outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/wine-pledge-20261112-01`.
It includes final source snapshots, the kernel/host changes, both saved kernels
and build logs, focused and full regression runs, the baseline refusal, fresh
signed run, prepared runtime and unchanged-retainer refusals. Source baseline
is `554908ef4` plus `sources/changes.patch` and the new source snapshots.
The adjacent `wine-pledge-20261112-01.tar.gz` archive has SHA-256
`8cc5c7913b7d3b71a5a21614e6d9ee76eef37d4c219732db0e711f28dddb2c9c`.
Its complete typed inventory has SHA-256
`e4aae2ce77b86d8807894dcade96155bb0a8ff44325388f5527a32b38861267f`.
The existing V `swift-staging-archive` tool returned 0 after restoring the
archive and comparing all file types, modes, link targets, sizes and hashes
against both the original and restored trees. The original bundle and
`wine-pledge-20261112-01-restoration` remain retained. This is evidence
integrity, not an exception to the Wine retainer's refusal.
