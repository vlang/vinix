# Privileged operation policy

Vinix uses a small part of [SBP's selector-based design](https://github.com/okTurtles/sbp): privileged operations have stable, human-readable `domain/action` names. The kernel's [policy](../kernel/security/policy.v) lists the selectors it recognizes and denies unknown selectors. Syscall handlers check permission before reading userspace arguments or changing system state.

| Selector | Syscall operations | Current rule |
| --- | --- | --- |
| `filesystem/mount` | `mount` | Effective UID 0 and `CAP_SYS_ADMIN` |
| `filesystem/unmount` | `umount2` | Effective UID 0 and `CAP_SYS_ADMIN` |
| `system/hostname/set` | `sethostname` | Effective UID 0 and `CAP_SYS_ADMIN` |
| `system/domainname/set` | `setdomainname` | Effective UID 0 and `CAP_SYS_ADMIN` |
| `system/reboot` | `reboot` | Effective UID 0 and `CAP_SYS_BOOT` |
| `system/securelevel/set` | `/proc/sys/kernel/securelevel` writes | Effective UID 0 and `CAP_SYS_ADMIN` in the initial user namespace; cannot lower the boot floor |

The rule applies to both architecture ABIs where those operations exist. A denied call returns `EPERM`. The AArch64 syscall smoke test checks full and effective-only privilege drops, invalid userspace pointers, authorized calls with a nonzero real UID, and unchanged host and domain names after denials.

`tests/security-policy/run.sh` exercises the production allowlist with a controlled credential source, including unknown selectors presented by an effective-root caller and a root caller whose capability was dropped, as a container runtime does.

For `mount` and `umount2`, authorization precedes all argument reads. Authorized calls copy the source, target, and filesystem type from userspace into bounded kernel-owned strings, checking each mapped page and requiring a NUL byte within 4096 bytes. Invalid pointers return `EFAULT`; unterminated strings return `ENAMETOOLONG`. A NULL source or target is an invalid pointer. The filesystem type may be NULL, as on Linux, for a remount, bind, move, or propagation change. This keeps a root caller's bad pointer from becoming an unchecked kernel dereference.

Both architectures map mount and unmount directly to the shared VFS syscall handlers. Kernel boot and storage code uses `mount_at_root()` with kernel-created arguments; it is not a userspace entry path.

For an authorized caller, `umount2` detaches the mount at its target, and returns `EINVAL` when nothing is mounted there.

This policy is a starting point for more specific permissions, not an isolation boundary between processes that still run as root. Vinix currently starts processes with UID 0 and every capability; the capability sets are what let a container runtime take some of them away. There are no per-process selector grants. Applications that drop their credentials cannot perform the listed operations. The policy does not install or use the JavaScript SBP runtime in the kernel.

## Desktop selector worlds

The desktop compositor has a separate selector boundary for pointer actions. It records whether each hit target came from compositor UI or a decoded application tree. The compositor interprets its own selectors only for compositor targets; application selectors are opaque and are routed to the app window under the pointer through that app's RPC pipe. An app can use any action name, including one that resembles a window or Start-menu command, without gaining that command. This is a per-application dynamic fallback similar to SBP's star selector, not a shared global selector registry. The optional `vinix-desktop --trace-selectors` switch logs routed pointer selectors with their world for runtime inspection.

The compositor has narrow, explicit bridges to the Files context menu and Capture service. Other application selectors do not trigger desktop commands. This boundary applies to desktop UI actions; it does not mediate arbitrary system calls or provide per-process capabilities.

## Authenticated UEFI images

[`tools/verified-boot`](../tools/verified-boot/README.md) builds a Limine 12.8
UEFI boot tree using an administrator-supplied signing key and certificate.
The configuration hash is embedded in the loader before its PE signature is
made. That configuration pins the command line, kernel, initramfs overlays and
optional device tree. Firmware Secure Boot must be enabled and trust the
signing certificate for the loader itself to be authenticated. Verification
uses a trusted certificate supplied separately from the image.

The profile starts from the authenticated initramfs and rejects disk-root and
persistence command-line overrides. Initial root contents are authenticated;
the resulting tmpfs is writable at runtime. This supplies neither dm-verity
for an ext2 root nor executable authentication at page-fault time. The normal
image builders remain development paths, and the new unsigned mode explicitly
reports that boot is unauthenticated. Apple m1n1 and BIOS boot are outside this
UEFI trust chain. Key enrollment and revocation remain deployment choices.

## Application confinement

[`vinix-sandbox`](../tools/sandbox/README.md) launches a command only after
installing its required restrictions. It sets `no_new_privs`, drops capability
sets and privileged identities, restricts inherited descriptors/environment,
locks explicitly unveiled paths, and installs pledge exec promises. Setup
failure prevents execution. Filesystem and syscall permissions are explicit;
the launcher does not silently retry an unconfined command.

The native calculator applies a smaller profile after loading its initial
model: anonymous credentials, no capabilities or privilege gains, an empty
locked filesystem view, and the `stdio` promise. Its existing compositor RPC
descriptors remain available. Startup fails if any restriction cannot be
installed. Other application profiles need their own measured access needs;
the privileged compositor and general Files/Settings applications do not gain
this calculator profile. This is application confinement using existing kernel
interfaces, not a general labeled mandatory access-control framework.

## Durable selected seccomp records

The kernel retains 128 selected seccomp decisions in its bounded allocation-free
producer ring. `/proc/security_audit` requires initial-user-namespace effective
root and `CAP_AUDIT_READ` on every read. Its header includes a stable 128-bit
boot identity to distinguish sequence domains across collector restarts.
That identifier is not an authentication token.

[`vinix-security-audit`](../tools/security-audit/README.md) collects snapshots
into a root-owned append log, fsyncs changed batches, records delayed syscall
completions separately, and reports exact missing sequence ranges. It refuses
unsafe log ownership, writable ancestors, symlinks and hardlinks. Userland and
desktop builds package both utilities, including compact and cached desktop
roots. Desktop init starts the collector supervisor before applications.
Logs survive reboot when `/var/log` is backed by
persistent storage. An initramfs-only root has volatile logs.

The ring can overwrite events before collection; persistence does not make it
lossless. Privileged software can alter the local log. Login/session attribution,
Linux's audit ABI, remote tamper-resistant collection and coverage of all
security decisions remain separate work.

## Initial x86 speculation controls

The kernel uses compiler and handwritten-dispatch retpolines, fences SWAPGS
paths, and fills the return predictor before thread dispatch. Each CPU enables
enhanced IBRS, STIBP and SSBD only when advertised. Supported CPUs run IBPB
before a thread is dispatched, including dispatch from idle. Applications
cannot turn these controls off.

[`tests/speculation-policy`](../tests/speculation-policy/README.md) checks
feature selection and MSR gating. These controls do not establish that a CPU
is free from speculative side channels. KPTI, BHI, CPU-specific return and
sampling mitigations, legacy IBRS entry programming and ARM firmware policies
remain unimplemented here. See [Intel's enumeration](https://www.intel.com/content/www/us/en/developer/articles/technical/software-security-guidance/technical-documentation/cpuid-enumeration-and-architectural-msrs.html)
and [Linux's mitigation guidance](https://docs.kernel.org/admin-guide/hw-vuln/spectre.html)
for the hardware distinctions.

Vinix remains pre-alpha. These tested mechanisms narrow specific gaps; they
do not establish security parity with a maintained, well-configured Linux
system or prove every kernel and application path secure.
