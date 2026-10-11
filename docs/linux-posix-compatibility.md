# Linux and POSIX compatibility

Roadmap section 15 remains partial. This matrix describes source support and
reproducible acceptance workflows, not universal Linux binary compatibility.
`open` means absent or awaiting implementation; `partial` means a subset exists;
`implemented` means a described behavior exists; `qualified` requires a passing
receipt for the exact architecture, kernel, libc and application versions tested.
Host, QEMU and physical-machine evidence are separate.

See the [2026-10-11 qualification report](linux-posix-qualification.md) for
native syscall/runtime results, translated x86-64/i386 runtime checks, actual SQLite
and HTTP workloads, and the unsupported application dependencies. Those receipts
qualify their stated checks and exact binaries only.

The [generated native syscall inventory](linux-syscall-coverage.md) and
[machine-readable inventory](linux-syscall-coverage.json) cover every number in
the pinned musl 1.2.5 namespace on AArch64 and x86-64. Regenerate it with:

```sh
build-support/run-v-tool.sh tools/linux-compat/coverage.v
build-support/run-v-tool.sh tools/linux-compat/coverage.v --check
v -cc cc test tools/linux-compat
```

Numbers with a handler are reported as wired and unqualified. A function pointer
does not prove correct argument widths, errno, lifetime or libc behavior. All
unassigned numbers, and the explicitly absent BPF and rseq implementations,
return ENOSYS. Updating the reference namespace requires review; the generator
never downloads or silently advances it.

## Behavior matrix

The owner for these rows is the Vinix compatibility workstream. Both columns
refer to native ELF64. Linked existing tests document their own dated evidence;
they are not automatically rerun or upgraded to current qualification here.

| Interface / runtime expectation | AArch64 | x86-64 | Acceptance workflow and current limit |
| --- | --- | --- | --- |
| Syscall numbers, signed integer arguments, stat and iovec layouts | partial | partial | Generated inventory; [stat buffers](../tests/stat-buffer/README.md), [ABI scratch](../tests/abi-scratch/README.md). Compare bad pointers and flags with Linux, not just successful calls. |
| Terminal, descriptor and framebuffer ioctls | partial | partial | [Terminal jobs](../tests/terminal-jobs/README.md), [console](../tests/amd64-console/README.md), [X11 input](../tests/x11-input/run-vm). Constants in `kernel/ioctl`; per-resource methods reject unsupported commands with ENOTTY. Generic DRM/KMS device compatibility is not qualified. |
| Block and filesystem ioctls | partial | partial | [Storage volumes](../tests/storage-volumes/README.md), [filesystem attributes](../tests/ext2-xattr/README.md). Vinix-specific volume ioctls do not establish Linux LVM/device-mapper support. |
| Socket ioctls, flags, ancillary data and options | partial | partial | [Socket I/O](../tests/socket-io/README.md), [network options](../tests/network-options/README.md), [IPv6](../tests/network-ipv6/README.md). Each protocol and option needs its own verdict. |
| Signals, masks, alternate stacks, return frames and EINTR/restart | partial | partial | [Process SMP](../tests/process-smp/README.md), [ARM signal return](../tests/aarch64-sigreturn/README.md), [AMD64 exceptions](../tests/amd64-exceptions/README.md). |
| clone/fork/exec, pthread TLS, cancellation, robust futexes and timers | partial | partial | [Process SMP](../tests/process-smp/README.md), [POSIX timers](../tests/posix-timer/README.md), [Steam robust lists](../tests/steam/run-robust-vm). rseq remains unavailable. |
| access, credentials, ACLs and descriptor paths | partial | partial | [POSIX ACLs](../tests/posix-acl/README.md), raw faccessat2 regression in `tests/linux-compat/accessfixture`. Test real/effective IDs, O_PATH, deleted files and empty paths. |
| openat2 and constrained path traversal | partial | partial | Raw regression in `tests/linux-compat/openfixture`: ordinary opens, NO_SYMLINKS and NO_MAGICLINKS during lookup/creation, final O_PATH link handles. BENEATH, IN_ROOT, NO_XDEV and CACHED remain EOPNOTSUPP, including combinations with supported flags. |
| rename/unlink, sparse files, links, directory iteration and xattrs | partial | partial | [Sparse ext2](../tests/ext2-sparse/README.md), [xattrs](../tests/ext2-xattr/README.md), [journal](../tests/fs-journal/README.md). tmpfs and disk-backed behavior must be tested independently. |
| mmap, W^X, mprotect, shared/private mappings and page sizes | partial | partial | [TLB](../tests/tlb/README.md), [paging](../tests/paging/README.md), [mapped writeback](../tests/mapped-writeback/README.md). AArch64 uses 16 KiB native pages; x86-64 uses 4 KiB. Runtime assumptions must be checked, not hard-coded. |
| `/proc` processes, threads, maps, mounts and memory/accounting | partial | partial | [Process inspection](../tests/process-inspection/README.md), [proc mounts](../tests/procfs-mount/README.md), [proc allocations](../tests/procfs-allocs/README.md). Linux tools may require fields or files that are not present. |
| `/sys` device discovery and cgroup behavior | partial | partial | `kernel/fs/sysfs*.v`, [resource groups](../tests/resource-groups/README.md). Linux sysfs is not fully reproduced; device cgroup BPF filtering is absent. |
| musl ELF loader, auxv, shared libraries and runtime fallback | partial | partial | Alpine userland and native fixture boots. [Dumpability/auxv](../tests/dumpability/README.md), [developer tools](../tests/developer-tools/README.md). Pin userland and kernel versions in qualification receipts. |
| Unmodified glibc loader and GNU runtime APIs | partial | partial | Selected staged Debian/Steam runtime paths exist; `gcompat` is not a complete glibc implementation. Validate each loader/library set and publish required GNU symbol versions. |
| Alpine package acquisition, save/update/remove and desktop launch | partial | partial | `pkg`/apk and package smoke fixtures. Per-application catalog below; complete lifecycle qualification needs persistent guest disk and desktop services. |
| D-Bus activation, service management and desktop portals | open | open | No qualified Linux systemd integration or complete freedesktop portal backend. Native file-dialog helpers are not the D-Bus portal protocol. Applications requiring these services need an explicit supported integration. |
| Sandboxes, containers, Flatpak/Snap/AppImage runtimes | partial | partial | [Application sandbox](../tests/application-sandbox/README.md), [MAC](../tests/security-mac/README.md). Native controls are distinct from Linux namespaces/seccomp/cgroups. BPF, `/dev/fuse`, complete portal integration and packaging lifecycle are not qualified. Do not report package installation as sandbox support. |
| ptrace/debuggers, core dumps and JIT debugging | open | open | ptrace has no native syscall dispatch. Debugger-specific workloads, translated guest tracing and symbol/stack unwinding need independent implementation and checks. |

## AArch64 foreign-application qualification

| Execution path | State | Required independent checks |
| --- | --- | --- |
| Native AArch64 ELF64 musl | partial | pthread TLS, atomics, NEON, W^X transitions/cache flush, auxv and 16 KiB pages; application workload and persistent save/update. |
| Native x86-64 ELF64 on x86-64 | partial | pthread TLS, atomics, SSE/AVX feature discovery, JIT protection transitions, debugging and 4 KiB pages. |
| x86-64 ELF64 through `run-x86-64` on AArch64 | partial | QEMU-user translator plus private musl/glibc loader; [translation smoke](../tests/x86-translation/smoke.sh) checks static instructions and a dynamic BusyBox call only. Run the same atomics/TLS/SIMD/JIT workload through the translator; check guest page size, low-address mappings and signals. |
| i386 ELF32 translation on AArch64 | partial | The [static runtime probe](linux-posix-qualification.md) passes TLS, 64-bit atomics, SSE2, JIT, 4 KiB/32-bit checks and lseek/time64 clock/timerfd predicates through QEMU-i386. Ordinary dynamic apps use `run-x86-32` and separate i386 libraries; [Steam robust fixtures](../tests/steam/run-robust-vm) cover selected behavior. Complete large-file/time ABI coverage, loader interoperability and debugger operations remain unqualified. |
| Native i386/x32 on either 64-bit kernel | open | The ELF64 dispatch inventory does not certify a native ELF32 syscall entry or x32 ABI. |

## Application acceptance catalog and unsupported dependencies

Each catalog item needs install, meaningful run, output verification, saved-data
reopen, update and desktop integration. A version banner or an empty window is
insufficient. Existing scripts below are input specifications for the V suite;
they do not certify all architectures or current releases.

| Category | Existing workload | Dependencies / outstanding qualification |
| --- | --- | --- |
| Browsers | Firefox/Chromium page rendering, JS and screenshot fixtures in `tests/browsers` | X11/GTK/NSS/fonts/network; full sandbox, D-Bus/portals, WebRTC capture, GPU acceleration and proprietary DRM not qualified. Some launchers currently disable browser sandboxing. |
| Office | [Gnumeric conversion/window](../tests/packages/gnumeric-smoke.sh), [Office Wine fixtures](../tests/office-compat/run-vm) | Native GTK/X11 or separately staged Wine/x86 runtime. Document reopen, printing, accessibility, clipboard and portals need integration verdicts. Wine fixtures do not establish LibreOffice or Microsoft Office application qualification. |
| Media | [FFmpeg encode/probe](../tests/packages/ffmpeg-smoke.sh), [Blender](../tests/packages/blender-smoke.sh), [OBS](../tests/packages/obs-init.sh) | Native codecs, audio/video devices, GL/Vulkan; GPU encode, capture and proprietary codecs need separate qualification. |
| Language runtimes | [Go](../tests/go/README.md), [Java](../tests/java/README.md), V/GCC developer fixtures | Native TLS/futex/mmap/signals, JIT permissions and certificates. Tests written in application languages remain application inputs; maintained build/test orchestration is V. |
| Databases | SQLite transactional create/query/reopen workload | sqlite CLI runtime; WAL locking, concurrent writers, recovery and disk durability require additional tests. PostgreSQL/MySQL service and multiuser qualification remain open. |
| Servers | HTTP loopback response and service lifecycle workload | Networking, DNS/TLS, credentials and supervision. Linux systemd unit installation is not a supported service integration claim. |
| Games | [Doom](../tests/dhewm3/README.md), [OpenGothic](../tests/opengothic/README.md), [Steam](../tests/steam/run-robust-vm), emulator suites | Runtime/assets/licenses, sound/input/GPU; proprietary DRM, kernel anti-cheat, account services and vendor APIs may block use. List failures per title and runtime. |

Do not silently disable isolation, install a no-op service or substitute a fake
success when a dependency is required. Unsupported results must stay visible in
the report and fail the complete qualification gate. Section 15 only closes
when the advertised combinations meet its full install/run/save/update/desktop
acceptance workflow.
