# Security process

How vulnerabilities are handled, how fixes reach machines, and what review
and testing the security-relevant code gets. This page was written on 11
October 2026 together with the first pieces it describes. **No report has
been through this process yet**; where a step depends on something that does
not exist, it says so.

## Reports

[`SECURITY.md`](../SECURITY.md) says how to report and what counts.

1. **Acknowledge.** Whoever receives a report answers within three working
   days, even if only to say it has been read.
2. **Reproduce and classify.** Against the current `master`, on the
   architecture reported. The classes:

   | Class | What it means | Example |
   | --- | --- | --- |
   | Critical | Someone with no account on the machine gets code running as root or in the kernel. | A packet that corrupts kernel memory. |
   | High | An account, a confined application or a container gets root, the kernel, another account's data, or out of its confinement. | A way around the seat; an action the authentication service runs for the wrong person. |
   | Medium | A boundary is weakened without being crossed, or crossing it needs something unusual to be true. | Reading metadata of another account's processes; a crash only an account can cause. |
   | Low | Hardening that is missing, or a record that is wrong. | A decision that is not logged. |

   The class is decided by what an attacker starts from and ends with, not
   by how the bug looks.
3. **Fix.** For Critical and High, in private: a branch that is not pushed
   to a public repository until the release that carries it. For the
   others, in the open like any other change. Every fix comes with a test
   that fails without it -- a scenario of `tests/accounts` or its like for
   a boundary, a fuzz target or a saved input for a parser -- so that the
   same hole cannot come back unnoticed.
4. **Look for the same mistake elsewhere.** A missing check in one system
   call is usually missing in its neighbours. The fix is not done until
   someone has looked.
5. **Release and say so.** See below.

Target times, from the report: a fix for Critical within 7 days, High
within 30, Medium within 90. They are intentions of a small project, not
promises; a reporter is told when one will be missed.

### Disclosure

The reporter is kept informed and is asked, not told, about timing. The
default is that details are public when a release with the fix has been out
for a week, and no later than 90 days after the report whether or not there
is a fix. An advisory says which revisions are affected, what an attacker
needed and got, how to tell whether a machine has the fix, and who found it.

Vinix has no CVE numbering authority and has not requested identifiers for
anything. An advisory on GitHub can request one; whether to is decided per
advisory.

## Getting a fix to machines

What exists:

- **Releases** are images built from a revision
  ([`README.md`](../README.md#download-an-image)). An image records its
  revision in `/etc/vinix-release`.
- **The desktop checks for a newer release** and says so: it compares
  `/etc/vinix-release` with the version published at `vinix-os.org`. It
  tells the user; it does not install anything.

What does not exist, and is why this cannot yet be called an update
process:

- **No update mechanism.** A fix reaches a machine by installing a newer
  image over the old one, or by rebuilding from source. There is no
  package-level update of the base system, no staged activation, no
  rollback ([roadmap section 1](../roadmap.md)).
- **No signed updates.** The verified-boot tooling can sign an image for a
  machine whose firmware trusts the key
  ([`docs/security.md`](security.md#authenticated-uefi-images)), but
  release images are not signed with a project key, and nothing checks a
  signature when an image is downloaded.
- **No security-only releases.** A release is the whole of `master` at a
  revision. A fix cannot be shipped without everything else that changed.
- **No supported old versions.** Only the newest release gets fixes.
- **No channel for telling users.** The release check carries a version,
  not a reason; someone who reads the advisories knows that an update is a
  security update, and nobody else does.

Until those exist, the honest instruction for a serious vulnerability is:
install the new image, or do not use the affected feature.

## Review

Code that decides who may do what gets a second reader before it is relied
on. What has had one and what has not:

| Area | State |
| --- | --- |
| Account database, authentication service, sessions (`tools/accounts`) | Written and tested in October 2026; **not reviewed by anyone but its author**. |
| Login sessions, the seat, the security event ring (`kernel/proc/login.v`, `kernel/security/events.v`) | The same. |
| pledge, unveil, signed signal frames, the kernel random generator, user-access protection (SMAP/PAN) | Described in [`docs/openbsd-security.md`](openbsd-security.md) with their tests; reviewed by their author. |
| Mandatory domains, seccomp, the seccomp audit ring | Described in [`docs/security.md`](security.md); the same. |
| System call argument handling | Checked copies everywhere since the user-access work; no systematic review of each call's semantics. |
| Parsers of hostile input in the kernel (ELF, ext2, tar, FAT, device tree, ACPI, network, USB, virtio) | **Not reviewed, not fuzzed.** |
| Drivers | Not reviewed as an attack surface. A device that lies -- a USB device, a disk, a network card under an attacker's control -- is outside what has been considered, except where an IOMMU confines it ([`docs/hardware-platform.md`](hardware-platform.md)). |
| The desktop compositor and its application protocol | Runs as root; the protocol's decoder has bounds but no fuzzing. |
| Containers and namespaces | Tested for function ([`tests/docker`](../tests/docker)); the isolation has not been attacked. |
| Third-party code (lwIP, uACPI, Mesa, Wine, browsers, packages) | Whatever its upstream did. Versions are not tracked against upstream advisories. |

"Reviewed" above never means an independent audit. There has been none.

### What a review is

For a change that adds or moves a boundary:

1. Someone other than the author reads it with one question: what can the
   less privileged side now cause the more privileged side to do?
2. Every new lifetime -- something freed that was not freed before, a
   pointer kept across a sleep -- is read for use after free
   ([`AGENTS.md`](../AGENTS.md), "Finding memory leaks in the kernel").
3. There is a test in which the less privileged side tries and is refused,
   run on both architectures.
4. What the change does not protect against is written in the document that
   describes it, next to what it does.

## Testing that guards boundaries

| What | Where | Run |
| --- | --- | --- |
| An account against the kernel and the account tools | [`tests/accounts`](../tests/accounts/README.md) | Boots both architectures in QEMU. |
| pledge, unveil, signal frames, immutable mappings | [`tests/openbsd-security`](../tests/openbsd-security/README.md) | QEMU. |
| Mandatory domains | [`tests/security-mac`](../tests/security-mac/README.md) | QEMU. |
| Kernel reads and writes of user memory | [`tests/user-access`](../tests/user-access) | QEMU, audit mode. |
| Verified boot and root | [`tools/verified-boot`](../tools/verified-boot/README.md), [`tools/verified-root`](../tools/verified-root/README.md) | QEMU. |
| x86 speculation controls | [`tests/cpu-mitigations`](../tests/cpu-mitigations/README.md) | QEMU; no physical processor. |
| Parsers | [`tests/fuzz`](../tests/fuzz/README.md) | The host. |

None of these runs automatically on every change. They are run by whoever
changes the area, and the documents record when.
