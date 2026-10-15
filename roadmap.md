# Vinix roadmap to 1.0

Planning baseline: 9 October 2026. This roadmap is based on the current repository
implementation and its status documents. It proposes work and release criteria;
it does not certify the existing implementations or promise release dates.

## Goal and definition of parity

Vinix 1.0 should be a complete daily-use operating system with feature parity
with macOS, mainstream desktop Linux, and Windows. A user should be able to
install it, connect devices, work, develop software, play games, protect their
data, and maintain the machine without relying on another operating system.

Parity means comparable capabilities and complete workflows across the union
of those platforms' features. It includes the kernel, hardware, desktop,
applications, administration, accessibility, interoperability, and developer
tools. Matching the appearance of a desktop or launching a demonstration app
does not establish parity.

Before implementation is marked complete:

- Select named macOS, Windows, and Linux distribution/desktop releases as
  reference systems and record their versions. Update the comparison at each
  milestone so the target remains explicit as those platforms evolve.
- Turn the backlog below into a feature matrix. Each item needs an owner,
  dependencies, implementation status, supported architectures/devices,
  acceptance workflow, and links to reproducible evidence.
- Use `open`, `partial`, `implemented`, and `qualified` states. Only `qualified`
  closes a 1.0 requirement. Host tests, VM tests, and physical hardware results
  must remain distinguishable.
- Provide a native capability or an integrated, maintained port. Users should
  have coherent settings, permissions, file dialogs, clipboard, notifications,
  accessibility, and lifecycle behavior regardless of the application's origin.
- Track proprietary services, restricted APIs, firmware, DRM, and anti-cheat
  dependencies explicitly. Provide interoperable alternatives where possible;
  disclose unavailable workflows instead of claiming universal compatibility.

Full feature parity does not require copying every private kernel API, supporting
every peripheral ever made, or reproducing a vendor's account infrastructure.
Hardware coverage must be published, application compatibility must be measured,
and equivalent user capabilities must be demonstrated. macOS desktop application
compatibility is a separate project from the existing iOS runtime.

All workstreams below are pre-1.0 targets. The milestones order the work; they
do not defer difficult parity requirements until after 1.0. If the agreed
feature matrix remains incomplete, Vinix should remain pre-1.0.

## Starting point

The repository already contains substantial implementation. These foundations
need extension and qualification rather than replacement with another prototype.
Existing status documents are dated evidence and must be reconciled with current
code; this roadmap does not reclassify their historical test results.

| Area | Existing foundation | Work still needed for parity |
| --- | --- | --- |
| Kernel and userland | x86-64 and AArch64 builds; Linux-compatible interfaces; Alpine/musl userland; SMP, NUMA and real-time scheduling | Complete ABI semantics, paging, scalability, hardening, lifetime and long-running reliability checks. See [kernel comparison status](docs/macos-xnu-implementation-status.md) and [integrated gap status](docs/openbsd-feature-implementation.md). |
| Memory pressure | Cache reclaim, mapped-file aging/writeback, pressure reporting, allocation reserves, compressed anonymous memory, encrypted swap, process OOM recovery and bounded creator-charged kernel resources | Resource groups, pressure notification policy and continued lifetime/stress qualification. See [anonymous paging](docs/anonymous-paging.md), [kernel resource limits](docs/kernel-resources.md) and [OOM behavior and limits](tests/oom/README.md). |
| Storage and installation | ext2, persistent VM roots, block drivers, flush paths, optional verified root and an M1 installer | Crash-safe filesystem, encryption, snapshots, autonomous disk boot, recovery and physical storage qualification. See [image installation](README.md#download-an-image), [M1 installer](installer/macos/README.md) and [ANS limits](docs/apple-ans-rw-root.md). |
| Native desktop | Window management, tiling, overview, workspaces, taskbar, Settings, Files and 21 native utilities | Multiple displays, full desktop services, accessibility and remaining utility workflows. See [window experience](desktop/WINDOW_EXPERIENCE.md), [utility inventory](desktop/UTILITIES.md) and [Settings](desktop/SETTINGS.md). |
| Networking and peripherals | Ethernet networking, IPv4/IPv6, selected USB/input paths, sound playback, experimental M1 Wi-Fi and Apple drivers | General hotplug/classes, wireless IP connectivity, Bluetooth, recording, peripheral coverage and power management. See [networking status](docs/openbsd-feature-implementation.md#networking), [Wi-Fi limits](docs/apple-wifi.md) and [M1 audio](docs/m1-speakers.md). |
| Graphics | Native framebuffer composition, X11, an AArch64 Hyprland path, VirtIO graphics work and Apple/Intel bring-up | Qualified hardware GPU/display pipelines, complete driver integration, resets and interoperable composition. See [i915 integration](docs/linux-i915.md#remaining-driver-integration) and [M1 AGX](docs/m1-agx-bringup.md). |
| Applications | Package frontend, browsers, office/media ports, Wine, x86 translation and iOS/Android subsets | Broad compatibility qualification, consistent desktop integration and macOS desktop runtime work. See [packages](README.md#packages-on-aarch64), [Wine](docs/wine.md), [iOS](docs/ios.md) and [Android](docs/android.md). |
| Security and sessions | Capabilities, mount policies, confinement mechanisms, accounts with an authentication service and a session manager, a record of security decisions, a credential store, optional authenticated UEFI/root and a persistent desktop profile | A desktop that logs in and runs as the person at it, secure default launch policy, and a complete deployment lifecycle. See [security scope](docs/security.md), [accounts](docs/accounts.md) and [single-user registration](desktop/registration_store.v). |
| Virtualization | Running as a VM guest; a small experimental Intel VT-x host interface; QEMU software emulation | General VM hosting, multiple vCPUs, practical memory sizes, additional architectures and device/lifecycle support. See [virtualization limits](docs/virtualization.md). |

Unchecked items below identify unfinished capabilities or acceptance work. They
do not imply that every component mentioned is absent from the current code.

## Milestones and dependency order

| Milestone | Deliverable | Exit criterion |
| --- | --- | --- |
| M0: establish the parity baseline | Versioned reference feature matrix, supported hardware list, reproducible builds and an inventory of current failures | Every requirement has an acceptance workflow; existing passing tests and unresolved failures are recorded against exact revisions. |
| M1: make the system safe to keep | Durable storage, recoverable installation/updates, real user identities, memory/resource recovery and production security defaults | Install, save, reboot, update, interrupt an update and recover without losing user data on each initial reference machine. |
| M2: finish the hardware platform | GPU/display, networking, audio, input, USB/Bluetooth and power management | A reference PC and M1 laptop complete the hardware workflows on physical devices, including repeated hotplug and sleep/resume. |
| M3: complete the everyday desktop | Desktop services, multiple displays, Files/search, accessibility, international text, media/printing and core applications | The full everyday workflow suite works through the UI for keyboard, pointer and assistive-technology users. |
| M4: complete the software ecosystem | Linux/Windows/macOS compatibility, application distribution, development, containers, VM hosting, remote work and organization integration | The published application and developer workload suites install and complete real tasks on each supported architecture. |
| M5: qualify 1.0 | Complete feature matrix, release engineering, audits, migration and performance/reliability qualification | All 1.0 gates below pass on a release candidate; no unresolved requirement is hidden behind a launcher, stub or unavailable service. |

Independent work can proceed together, but shared foundations come first:
durability before automatic updates and snapshots; identity before privileged
desktop services; device enumeration before settings; audio capture before
calling/recording; accessibility and text services before app-wide qualification;
isolation before containers and general VM hosting. Graphics, networking and
memory work must support application qualification on both architectures.

## Required workstreams

### 1. Installation, boot, updates and recovery

- [ ] Provide a guided installer for supported PCs and ARM machines: disk and
  partition selection, dual boot, encryption, users, locale and network setup.
- [ ] Boot an installed system from its own disk without keeping the installer
  ISO attached; support clean UEFI installs and preserve neighboring boot entries.
- [ ] Qualify the existing M1 installer, firmware handling and recovery route;
  publish exact supported models and installation prerequisites.
- [ ] Implement atomic, authenticated system updates with staged activation,
  interruption recovery, previous-version boot and rollback preserving user data.
- [ ] Manage configuration/schema migrations and package updates together, with
  visible progress, restart requirements and an offline update path.
- [ ] Ship recovery media and a recovery environment for filesystem checks,
  backup restoration, boot repair, account recovery and diagnostic collection.
- [ ] Add migration from Linux, Windows and macOS for supported files, accounts
  and settings, with conflict previews and a reversible import.

Acceptance: fresh install, dual boot, disk-only boot, upgrade, interrupted
upgrade, rollback and recovery are repeatable from published images.

### 2. Memory, process management and kernel reliability

- [x] Add disk-backed anonymous paging, encrypted swap, memory compression and
  pageout/refault with correct shared/private mapping behavior. See
  [implementation and limits](docs/anonymous-paging.md) and [acceptance tests](tests/paging/README.md).
- [x] Finish dirty/reference tracking and reclaim for mapped file pages; retain
  correct writeback through unmap, unlink, truncation and storage failures. See
  [implementation and limits](docs/mapped-file-paging.md) and [acceptance tests](tests/mapped-writeback/README.md).
- [x] Extend current OOM recovery to bounded, charged kernel resources, including
  files, descriptors, sockets, IPC, mappings and process/thread creation. See
  [implementation and limits](docs/kernel-resources.md) and [acceptance tests](tests/kernel-resources/README.md).
- [x] Complete resource groups: memory/CPU/I/O/PID limits, pressure notifications,
  workload accounting and predictable recovery from quota exhaustion. See
  [implementation and limits](docs/resource-groups.md) and [acceptance tests](tests/resource-groups/README.md).
- [x] Qualify fork/exec/exit, vfork/clone semantics, signals, timers, futexes and
  job control under SMP, cancellation, rapid process churn and resource pressure.
  See [implementation and qualification limits](docs/process-smp.md) and
  [acceptance tests](tests/process-smp/README.md).
- [x] Improve run-queue and allocator scalability, priority inheritance, workload
  QoS, heterogeneous-core placement and deadline-driven idle/timer coalescing.
  See [implementation and limits](docs/scheduler-qos.md) and
  [acceptance tests](tests/scheduler-qos/README.md).
- [x] Complete architecture-specific address-space/TLB work and large-page
  support where useful; verify protection and teardown during concurrent access.
  See [implementation and limits](docs/address-space-tlb.md) and
  [qualification](tests/tlb/README.md).
- [x] Eliminate measured per-operation retention and close unresolved kernel
  stress failures; audit generated V-to-C allocations and every new lifetime.
  See [implementation and qualification limits](docs/memory-retention.md) and
  [retention acceptance tests](tests/memory-retention/README.md).

Acceptance: repeated workloads stop growing memory after warmup, resource abuse
does not panic the machine, and the desktop remains usable during pressure.

### 3. Filesystems, storage and data protection

- [x] Ship a crash-safe primary filesystem with journaled or copy-on-write
  recovery; cover metadata ordering, rename/replace and mapped write durability.
  See [VJFS recovery guarantees and limits](docs/primary-filesystem.md) and
  [crash and lifetime acceptance tests](tests/fs-journal/README.md).
- [ ] Add volume management, storage pools/RAID, full-disk encryption, key recovery,
  online capacity management, TRIM/discard and storage health/error reporting.
  - [x] [Boot-local linear block volumes, raw capacity growth and I/O counters](docs/storage-volumes.md).
  - [x] [Protected raw TRIM/discard through volumes and partitions](docs/storage-volumes.md#trimdiscard).
  - [x] [Checksummed saved volume plans with verified disk identity and idempotent restore](docs/storage-volumes.md#saved-volume-plans).
  - [x] [Identity-based disk discovery and opt-in volume-plan restore before boot applications](docs/storage-volumes.md#discovery-and-boot-restore).
  - [x] [Multi-disk plan sets with global slot/extent preflight and boot replay](docs/storage-volumes.md#multi-disk-plan-sets).
  - [x] [Read-only AHCI ATA SMART identity, raw attributes and threshold health queries](docs/storage-volumes.md#ata-smart-health).
  - [x] [Read-only PCI NVMe controller identity, SMART/Health logs and critical-warning reporting](docs/storage-volumes.md#nvme-smarthealth).
  - [x] [Read-only Apple ANS controller identity and SMART/Health queries with pinned DMA and serialized shutdown](docs/storage-volumes.md#apple-ans-smarthealth).
  - [x] [Apple ANS namespace/partition I/O counters, shared physical identity and offline/error reporting](docs/storage-volumes.md#apple-ans-block-status).
  - [x] [Periodic storage health/error monitoring with counter deltas and persistent session exit status](docs/storage-volumes.md#periodic-storage-monitoring).
  - [x] [Periodic NVMe/ANS thermal and wear telemetry, full 128-bit hardware counter deltas and new media-error detection](docs/storage-volumes.md#nvme-and-ans-telemetry).
  - [x] [Atomic checksummed multi-disk plan bundles, complete-set publication and preflighted boot replay](docs/storage-volumes.md#atomic-multi-disk-bundles).
  - [x] [Offline capacity planning and explicit preflighted growth replay with stable generations and open descriptors](docs/storage-volumes.md#planned-capacity-growth).
  - [x] [Offline bundle inspection and read-only complete-set preflight with create/keep/grow action previews](docs/storage-volumes.md#bundle-inspection-and-preflight).
  - [x] [Offline mapping additions/removal with complete-set validation, atomic publication and separate live application](docs/storage-volumes.md#offline-mapping-configuration).
  - [x] [Offline disk enrollment and empty-member removal preserving desired mappings, atomic publication and live descriptors](docs/storage-volumes.md#offline-disk-membership).
  - [x] [Bounded aligned free-extent inspection and first-fit allocation preserving desired mappings and separate live protection](docs/storage-volumes.md#bounded-extent-allocation).
  - [x] [Explicit adoption of observed physical capacity growth with pinned identity verification, preserved desired mappings and new-tail allocation/replay](docs/storage-volumes.md#adopting-physical-capacity-growth).
  - [x] [Persistent multi-disk allocation pools with atomic membership, full-width free-capacity reporting and ordered contiguous allocation/replay](docs/storage-volumes.md#persistent-allocation-pools).
  - [x] [Pool eligibility expansion preserving allocation priority and bounded in-place desired mapping growth with durable retries and stable live descriptors](docs/storage-volumes.md#pool-expansion-and-mapping-growth).
  - [x] [Atomic ordered pool allocation batches with complete read-only placement previews, rollback on later failures and durable matching-row retries](docs/storage-volumes.md#atomic-pool-allocation-batches).
  - [x] [Nonblocking saved-plan writer locks covering source reads and atomic publication, pinned directory identity and automatic owner-exit recovery](docs/storage-volumes.md#saved-plan-writer-locking).
  - [x] [Atomic pool growth batches with complete read-only action previews, rollback on later failures and durable equal-size retries](docs/storage-volumes.md#atomic-pool-growth-batches).
  - [x] [Atomic pool eligibility expansion batches with complete read-only previews, rollback on later failures, preserved allocation priority and durable equal-end retries](docs/storage-volumes.md#atomic-pool-expansion-batches).
  - [x] [Atomic multi-disk physical capacity adoption with complete previews, pinned read-only devices, final identity/geometry rechecks and durable equal-capacity retries](docs/storage-volumes.md#atomic-physical-capacity-adoption-batches).
  - [x] [Atomic pool membership additions/removals with complete previews, preserved allocation priority, whole-set rollback and durable matching/absent retries](docs/storage-volumes.md#atomic-pool-membership-batches).
  - [x] [Explicit pool allocation priority with complete permutation previews, preserved bounds/mappings, atomic publication, durable retries and boot persistence](docs/storage-volumes.md#explicit-pool-allocation-priority).
  - [x] [Atomic cross-disk desired mapping removal with complete action previews, stable row/pool order, rollback, durable absent-slot retries and boot persistence](docs/storage-volumes.md#atomic-desired-mapping-removal-batches).
  - [x] [Atomic multi-disk snapshot enrollment with complete previews, pinned source rechecks, exact matching retries, preserved desired state/indices/pool priority and boot persistence](docs/storage-volumes.md#atomic-disk-enrollment-batches).
  - [x] [Atomic identity-based empty-disk removal with complete previews, stable compaction, remapped pool references, whole-set rollback, durable absent retries and boot persistence](docs/storage-volumes.md#atomic-disk-forgetting).
  - [x] [Atomic identity-based explicit mapping additions with complete previews, whole-set rollback, preserved row/pool order, durable exact retries across disk compaction and boot persistence](docs/storage-volumes.md#atomic-explicit-mapping-additions).
  - [x] [Atomic identity-based explicit mapping growth with complete previews, whole-set rollback, preserved offsets/modes/row/pool order, durable equal-size retries and boot persistence](docs/storage-volumes.md#atomic-explicit-mapping-growth).
  - [x] [Atomic identity-based pool eligibility contraction with protected occupied intersections, complete previews, whole-set rollback, preserved mappings/priority, durable equal-end retries and boot persistence](docs/storage-volumes.md#atomic-pool-eligibility-contraction).
  - [x] [Atomic cross-pool window resizing with two-sided occupied-byte protection, order-independent unused-capacity transfers, complete previews, whole-set rollback, durable equal-bound retries and boot persistence](docs/storage-volumes.md#atomic-cross-pool-window-resizing).
  - [x] [Atomic identity-based observed physical capacity contraction with protected desired mappings/pool bounds, pinned read-only probes and final rechecks, complete previews, whole-set rollback, durable retries and boot persistence](docs/storage-volumes.md#atomic-physical-capacity-contraction-batches).
  - [x] [Atomic ordered multi-pool allocations with independent member priority, complete previews, whole-set rollback, preserved matching placements, durable retries and boot persistence](docs/storage-volumes.md#atomic-multi-pool-allocation-batches).
  - [x] [Atomic in-place multi-pool mapping growth with per-request member bounds, complete previews, whole-set rollback, preserved starts/modes/priority, durable retries and boot persistence](docs/storage-volumes.md#atomic-multi-pool-growth-batches).
  - [x] [SHA-256 manifests for desired volume data, read-only identity-pinned hashing, complete corruption verification and persistent references across device reordering](docs/storage-volumes.md#data-checksum-manifests).
  - [x] [Complete read-only volume data scrubbing with all-mapping corruption findings, reference fingerprints, atomic durable reports, failed-scan rollback and boot persistence](docs/storage-volumes.md#complete-data-scrubbing).
  - [x] [Keyfile-based AES-256-XTS block volumes with native-sector encryption, stable growth/reopen, erased key lifetimes and plain-plan exclusion](docs/storage-volumes.md#keyfile-encrypted-block-volumes).
  - [x] [Authenticated volume-key backups and exact private recovery with independent recovery keys, no-overwrite publication, erased secret workspaces and ciphertext reopen after key loss/reboot](docs/storage-volumes.md#authenticated-volume-key-recovery).
  - [x] [Passphrase-sealed volume keys with bounded salted scrypt, authenticated private unseal, direct RW/RO unlock without raw keyfiles, erased KDF workspaces and reboot persistence](docs/storage-volumes.md#passphrase-sealed-volume-keys).
  - [x] [Authenticated sealed-key credential changes with fresh salt/nonce, no plaintext keyfiles, preserved envelopes, erased credential buffer reuse and reboot persistence](docs/storage-volumes.md#changing-sealed-key-credentials).
  - [x] [Authenticated encrypted-volume configurations binding disk identity, native sectors, slot/extent/mode and wrapped keys, pinned-device rechecks, private recovery and reboot persistence](docs/storage-volumes.md#authenticated-encrypted-volume-configurations).
  - [x] [Authenticated encrypted-volume credential changes preserving disk/mapping metadata and readonly mode, fresh salt/nonce, erased credential reuse, no raw keyfile or device access and reboot persistence](docs/storage-volumes.md#changing-encrypted-volume-configuration-credentials).
  - [x] [Authenticated identity-based encrypted-volume unlock with bounded discovery, physical-alias acceptance, duplicate refusal, erased credentials, pinned import, readonly preservation and reboot persistence](docs/storage-volumes.md#automatic-encrypted-volume-discovery).
  - [x] [Authenticated encrypted-volume extent growth and physical capacity adoption preserving key/start/slot/readonly mode, fresh wrapping, pinned rechecks, separate live application and ciphertext/reboot persistence](docs/storage-volumes.md#authenticated-encrypted-volume-growth).
  - [x] [Opt-in authenticated encrypted data-volume boot unlock with private root-owned pinned inputs, plain-set conflict preflight, identity discovery, readonly preservation, controlled recovery and reboot persistence](docs/storage-volumes.md#opt-in-encrypted-boot-unlock).
  - [x] [Bounded encrypted boot sets with independent credentials/keys, sorted pinned private inputs, complete authentication and physical preflight before application, shared-disk extent protection and multi-disk reboot persistence](docs/storage-volumes.md#multiple-encrypted-boot-volumes).
  - [x] [Authenticated encrypted-volume configuration backups and lost-credential recovery under independent recovery keys, exact metadata/key preservation, fresh passphrase wrapping, private no-overwrite publication and reordered boot persistence](docs/storage-volumes.md#encrypted-volume-configuration-recovery).
  - [x] [Direct authenticated recovery-key volume unlock with identity discovery, preserved readonly mode, erased credentials, no configuration publication and ciphertext rescue after credential loss/reordered reboot](docs/storage-volumes.md#direct-recovery-key-unlock).
  - [x] [Authenticated recovery-backup credential changes preserving disk/mapping metadata, volume key and readonly mode, fresh nonces, erased credential reuse, private no-overwrite publication and ciphertext rescue after old-key loss/reordered reboot](docs/storage-volumes.md#changing-recovery-backup-credentials).
  - [x] [Authenticated recovery volume extent growth and explicit physical capacity adoption with preserved key/identity/start/slot/readonly mode, secrets erased before pinned read-only probes, private publication, stable live descriptors and ciphertext rescue after expansion/reordered reboot](docs/storage-volumes.md#recovery-volume-growth-and-capacity-adoption).
  - [x] [Authenticated offline recovery-backup inspection and identity-based read-only physical discovery with exact metadata reports, erased secrets before reports/probes, ambiguity and changed-disk refusal, stable live descriptors and reordered boot persistence](docs/storage-volumes.md#authenticated-recovery-inspection-and-discovery).
  - [x] [Authenticated passphrase-protected volume configuration inspection and read-only identity discovery with exact metadata reports, bounded real-KDF lifetimes, erased secrets before reports/probes, stable live descriptors and reordered boot persistence](docs/storage-volumes.md#authenticated-encrypted-volume-inspection-and-discovery).
  - [x] [Read-only authenticated encrypted/recovery growth previews with explicit candidate capacity, exact keep/grow geometry reports, signed/native-sector bounds, erased secrets before pinned probes/output, no publication and stable live descriptors through expanded/reordered reboot](docs/storage-volumes.md#read-only-encrypted-growth-previews).
  - [x] [Encrypted ciphertext checksum references and complete extent verification through passphrase or recovery credentials, exact geometry binding, erased secrets before read-only streaming, private no-overwrite publication, corruption detection and stable live views/reordered reboot](docs/storage-volumes.md#encrypted-ciphertext-checksum-references).
  - [x] [Persistent complete encrypted ciphertext scrub findings with expected/observed digests and exact reference fingerprints, clean/changed/operational results, private no-overwrite publication, validated offline views, stable live descriptors and historical reports across reordered reboot](docs/storage-volumes.md#persistent-encrypted-ciphertext-scrub-findings).
  - [x] [Offline encrypted ciphertext scrub history comparisons with exact reference binding, stable/new-change/restored/changed-again findings, complete private input validation, operational error precedence and bounded lifetimes across reordered reboot](docs/storage-volumes.md#comparing-encrypted-ciphertext-scrub-history).
  - [x] [Authenticated identity-based automatic ciphertext scrubbing with secrets/reference validation before read-only discovery, alias acceptance and ambiguity refusal, preserved physical pin identity/mode, exact manual/automatic reports, bounded real-KDF lifetimes and reordered reboot](docs/storage-volumes.md#identity-based-automatic-ciphertext-scrubbing).
  - [x] [Authenticated identity-based automatic ciphertext checksum creation and verification with erased secrets and exact reference validation before read-only discovery, retained physical pin identity/mode, complete manual/automatic reference equality, corruption detection, bounded real-KDF lifetimes and reordered reboot](docs/storage-volumes.md#identity-based-automatic-ciphertext-checksums).
  - [x] [Offline ciphertext checksum reference inspection and comparison with complete private validation, exact saved mapping metadata, full-width digest/fingerprint reports, stable/changed/error precedence, unchanged inputs/live views and bounded lifetimes across reordered reboot](docs/storage-volumes.md#offline-ciphertext-reference-inspection-and-comparison).
  - [x] [Identity-based automatic plain multi-disk checksum creation, verification and complete scrubbing with original read-only pins, selected physical identity/mode rechecks, exact manual/automatic manifests and reports, failure cleanup and bounded lifetimes across reordered reboot](docs/storage-volumes.md#identity-based-automatic-data-checksums-and-scrubbing).
  - [x] [Offline plain multi-disk checksum reference comparisons with exact saved disk/mapping/pool metadata, all-row stable/changed digests, full reference fingerprints, operational error precedence, unchanged inputs/live views and bounded lifetimes across reordered reboot](docs/storage-volumes.md#offline-multi-disk-data-reference-comparison).
  - [x] [Validated offline plain multi-disk scrub report inspection with canonical bounded syntax, complete extent/order/slot and digest/count consistency, no partial scrub reports, pinned ordinary inputs and unchanged live views across reordered reboot](docs/storage-volumes.md#offline-multi-disk-scrub-report-inspection).
  - [x] [Offline plain multi-disk scrub history comparisons with exact reference/ordered row/expected digest binding, complete stable/new-change/restored/changed-again findings, full report fingerprints, operational error precedence and bounded lifetimes across reordered reboot](docs/storage-volumes.md#comparing-multi-disk-data-scrub-history).
  - [x] [Offline plain-data scrub binding to complete checksum references with exact native geometry, ordered rows and expected digests, full input fingerprints, historical findings, operational error precedence and bounded lifetimes across reordered reboot](docs/storage-volumes.md#binding-data-scrub-reports-to-checksum-references).
  - [x] [Offline ciphertext scrub binding to supplied checksum references with complete embedded reference equality, private inputs pinned through output, full binary input fingerprints, historical findings, operational error precedence and bounded lifetimes across reordered reboot](docs/storage-volumes.md#binding-ciphertext-scrubs-to-checksum-references).
  - [x] [Periodic complete plain-data checksum monitoring with one validated session reference, original read-only identity pins across intervals, restored-data status retention, late operational error precedence and bounded lifetimes across reordered reboot](docs/storage-volumes.md#periodic-pinned-data-checksum-monitoring).
  - [x] [Periodic authenticated ciphertext monitoring in passphrase/recovery domains with one authentication, secrets erased before reference/discovery, original private reference and read-only physical pins across intervals, restored-data status retention, late-error precedence and bounded real-KDF lifetimes across reordered reboot](docs/storage-volumes.md#periodic-authenticated-ciphertext-monitoring).
  - [x] [Offline complete plain-data monitor transcript verification with canonical sample/counter/latch checks, full reference binding and input fingerprints, per-mapping transition counts, no partial findings and bounded lifetimes across reordered reboot](docs/storage-volumes.md#offline-data-monitor-transcript-verification).
  - [x] [Offline complete ciphertext monitor transcript verification in both recorded source domains with canonical frame/source/counter binding, exact private reference geometry, full input hashes, transition summaries, fault precedence and bounded lifetimes across reordered reboot](docs/storage-volumes.md#offline-ciphertext-monitor-transcript-verification).
- [ ] Implement filesystem snapshots, clones/reflinks, version restoration and
  incremental backup primitives with explicit consistency guarantees.
  - [x] [Durable full and changed-chunk regular-file archives, exact full-base binding and no-overwrite content/mode/ownership/mtime restoration with explicit quiescence and consistency limits](docs/file-backups.md).
- [ ] Complete persistent permissions, ACLs, xattrs, ownership and disk quotas,
  with compatible behavior across normal, removable and shared filesystems.
- [ ] Support interoperable removable media, including FAT32/exFAT and NTFS;
  provide macOS data import/access paths and document APFS format/encryption limits.
- [ ] Add network filesystems and shares, including SMB and NFS, with reconnect,
  credential handling and consistent file-locking semantics.
- [ ] Complete mount/unmount/eject, removable-device discovery, partition tools,
  filesystem checking/repair and disk-image workflows in Disk Utility.
- [ ] Qualify AHCI/NVMe/VirtIO/Apple ANS with controller failures, device removal,
  cache flushes, reboot persistence and controlled power-loss tests.

Acceptance: recovery preserves acknowledged durable writes and produces a
consistent filesystem; backup restoration preserves content and metadata.

### 4. Hardware platform and power management

- [ ] Publish a qualification matrix for Intel and AMD PCs, base M1 machines,
  AArch64 VMs and x86-64 VMs; expand Apple Silicon and ARM coverage by actual model.
  - [x] [Matrix by machine and by device family, vendor dependencies and the
    physical checklist](docs/hardware-qualification.md). No machine is qualified
    yet: no checklist has been completed.
- [ ] Provide common device enumeration, driver binding/removal, firmware loading,
  DMA mappings, IOMMU isolation and safe timeout/reset infrastructure.
  - [x] [Device core, bounded waits and failure recovery, DMA domains, Intel VT-d
    and AMD-Vi (opt-in), firmware loader](docs/hardware-platform.md), tested in
    [QEMU guests](tests/hardware-platform/README.md) on both architectures.
  - [x] [PCI hotplug and rescan](docs/hardware-platform.md#pci-hotplug-and-rescan):
    PCI Express ports the kernel watches, devices firmware announces through
    ACPI, and addresses for what arrives. Only the e1000 can be taken out again.
  - [x] [USB keyboards and pointers on x86-64 as on AArch64](docs/hardware-platform.md#usb-keyboards-and-pointers):
    the root ports of one xHCI controller, polled, through every kind of
    sleep. Tested with QEMU's controller only.
  - [ ] A USB core -- hubs, hotplug, storage; Apple's drivers in the device
    list and behind the DMA layer; an IOMMU on by default once a PC has been
    tried; hotplug of bridges, and drivers other than the e1000 that let go
    of a device.
- [ ] Support the common storage, Ethernet, wireless, graphics and audio device
  families needed by the reference PC/laptop set; identify vendor dependencies.
  - [x] [What each machine class needs, the driver that is or is not there, and
    the vendor dependencies](docs/hardware-qualification.md#device-families-by-machine).
  - [ ] The drivers themselves: release-fit NVMe, the Ethernet and wireless cards
    PCs have, USB beyond a keyboard and a pointer, qualified graphics and
    audio.
- [ ] Implement CPU idle/frequency control, thermal management, fan/sensor APIs,
  battery/charging policy and accurate remaining-time/energy reporting.
  - [x] [Idle states and frequency policies with Intel, AMD and Apple drivers;
    thermal zones with the processor's sensors and energy counters; ACPI battery
    and charger with a smoothed time-left estimate and low/critical
    policy](docs/hardware-platform.md#power-supplies). Hardware registers are
    covered by host tests only.
  - [x] [ACPI thermal zones and the fans their active trips
    drive](docs/hardware-platform.md#thermal), tested against a scripted zone in
    QEMU.
  - [x] [An ACPI embedded controller
    driver](docs/hardware-platform.md#the-embedded-controller), tested against a
    simulated controller on the host and in QEMU. No physical controller has
    been tried.
  - [x] [Apple's SMC battery and charger as power supplies, its temperatures and
    fans in the thermal and hwmon classes, and the `CHWA` charge
    limit](docs/m1-battery.md), tested against a simulated SMC on the host and
    in QEMU. No physical run: nothing of this driver has been tried on a Mac.
  - [ ] Apple's SMC on the machine itself
    ([what to check first](docs/m1-battery.md#on-an-m1)); the `CHLS` charge
    limit of firmware without `CHWA`; a wake for the SMC's notifications, so
    that a battery running out during a sleep is noticed; the SoC's own
    temperature and the SMC's power sensors.
- [ ] Add reliable suspend/resume, lid behavior, wake sources, screen sleep,
  hibernation and shutdown/reboot that flushes storage and quiesces devices.
  - [x] [Suspend to idle with wake sources, an alarm and a rehearsal mode; lid
    and power button; power off and restart that flush storage and stop every
    device](docs/hardware-platform.md#sleep).
  - [x] [The screen dark for a sleep](docs/hardware-platform.md#sleep) where it is
    the boot framebuffer.
  - [x] [A backlight class, and the panels firmware can dim](docs/hardware-platform.md#sleep)
    (ACPI `_BCL`/`_BCM`): dimmest for a sleep, brightness keys acted on in
    the kernel. Tested against scripted panels in QEMU; none real.
  - [x] [PCI devices put into D3hot for a sleep](docs/hardware-platform.md#pci-power-states)
    and given their configuration again, where the driver can bring the
    device back from nothing. Tested with the one card QEMU powers down.
  - [x] [The lid, the buttons and the keyboard armed to end a suspend to
    RAM](docs/hardware-platform.md#suspend-to-ram-x86-64) as firmware describes
    them (`_PRW`). No machine has been woken that way: QEMU's cannot be.
  - [x] [Suspend to RAM on x86-64 (ACPI S3)](docs/hardware-platform.md#suspend-to-ram-x86-64):
    the processors, interrupt controllers, clocks, PCI configuration, IOMMUs
    and the display mode put back, tested in QEMU only and offered only where
    the kernel can bring the display back.
  - [x] [Suspend to disk on x86-64](docs/hardware-platform.md#suspend-to-disk-x86-64):
    an image of memory written to a device named on the kernel command line,
    the machine switched off, and the image gone back into at the next start
    before any filesystem is mounted -- or refused, with the reason, and
    discarded. Tested in QEMU only; the image is not encrypted.
  - [x] [The desktop's side](desktop/SETTINGS.md): battery state and time left
    from `/sys/class/power_supply`, Sleep and Restart in the Start menu, and
    Settings > Power with the lid action, the performance profile and two idle
    timeouts. Tested on the host only; the display is not turned off by default
    until that has run in a machine.
  - [ ] Suspend to RAM and suspend to disk on a physical machine, and for the
    drivers that cannot yet come back from a loss of power; an image that is
    encrypted, and one that is compressed; ACPI's S4; a suspend to disk on
    AArch64; a `disk` entry in the desktop; a backlight that needs the
    graphics driver, Apple's panel in the same class, the desktop using the
    class, and display power control; a screen lock, and a way for an
    application to keep the display on.
- [ ] Restore all device and security state after sleep, firmware errors and
  hotplug; keep recovery possible when a driver fails.
  - [x] [CPU protection registers compared across every sleep; e1000 and AHCI
    resumed and reset in place; a failing device reset, probed again or set
    aside without taking the machine down](docs/hardware-platform.md#waiting-and-recovery).
  - [x] [State after a sleep that powers devices down](docs/hardware-platform.md#suspend-to-ram-x86-64),
    for what QEMU's PC has: every processor's protection registers compared,
    PCI configuration and IOMMU units restored before a driver runs.
  - [x] [Suspend and resume in `nvme`, `ata` and `hda`](docs/hardware-platform.md#devices-and-drivers),
    so that no PCI driver an x86-64 kernel has refuses a machine a suspend to
    RAM; sound and an IDE disk are taken through all three kinds of sleep in
    QEMU, an NVMe disk on a debug kernel.
  - [ ] Suspend and resume in `xhci` and Apple's drivers.

Acceptance: each advertised machine completes a physical hardware checklist;
passing synthetic fixtures alone does not qualify a driver.

### 5. Graphics, displays and composition

- [ ] Finish Intel i915/Linux compatibility integration and qualify a real GPU;
  develop additional Intel/AMD/NVIDIA support with explicit supported-device scope.
- [ ] Finish Apple AGX firmware/submission and native DCP/KMS scanout integration;
  qualify command execution, display handoff and teardown on physical hardware.
- [ ] Provide usable OpenGL/Vulkan acceleration, synchronization, buffer sharing,
  GPU memory accounting, reset recovery and secure access for multiple clients.
- [ ] Complete X11 and Wayland integration: native windows, input, clipboard,
  display configuration, capture and application isolation.
- [ ] Support multiple displays, hotplug, mirroring/extension, rotation, resolution,
  refresh rate, mixed DPI, per-display scaling and arrangement recovery.
- [ ] Add color-managed rendering, ICC profiles, HDR and variable refresh on
  devices that advertise them, with accurate capability reporting.
- [ ] Provide accelerated video decode/encode and presentation without requiring
  a separate experimental image or an oversized RAM-backed runtime.

Acceptance: graphics workloads, monitor reconnects and GPU resets preserve a
responsive desktop; advertised APIs and display modes pass real-device tests.

### 6. Input, USB, Bluetooth and peripherals

- [ ] Finish general USB enumeration, hubs, hotplug, power and device classes:
  HID, storage, audio, cameras, printers, serial devices and mobile-device access.
- [ ] Support docks, USB-C/USB4/Thunderbolt and PCIe hotplug on advertised hardware,
  including display, charging, data paths and DMA isolation for external devices.
- [ ] Complete keyboards and pointer devices across native, X11 and Wayland apps,
  including modifiers, media keys, configurable shortcuts and remapping.
- [ ] Extend touchpads with scrolling, tap/secondary click, palm rejection,
  gestures, momentum and device settings; qualify Apple SPI input on hardware.
- [ ] Add Bluetooth controller support, pairing, reconnect, HID, audio and file
  transfer, with credentials protected by the system credential store.
- [ ] Add touch, stylus/tablet and game-controller support, mapping, calibration,
  hotplug and consistent access from native and compatibility applications.
- [ ] Provide camera/scanner import, mobile-device file transfer and peripheral
  status/configuration through discoverable desktop interfaces.

Acceptance: devices can be connected, configured, disconnected and reconnected
without restarting the desktop or requiring unsafe global device access.

### 7. Networking and connected operation

- [ ] Complete wireless data-plane/IP integration, including M1 Wi-Fi; support
  saved networks, WPA2/WPA3, enterprise authentication, roaming and reconnect.
- [ ] Finish network configuration services and Settings for DHCP/static IP,
  IPv6, DNS, routes, proxy, captive portals and connectivity diagnostics.
- [ ] Complete socket compatibility needed by mainstream applications, including
  ancillary/error queues, multicast extensions and interface administration.
- [ ] Add stateful firewalling, NAT, VPN interfaces/clients, per-app permission
  policy and network namespaces with meaningful traffic/accounting isolation.
- [ ] Support Ethernet/Wi-Fi transitions, hotspot/tethering, service discovery
  and reconnect after suspend without stale routes or lost credential state.
- [ ] Provide secure remote login and file transfer, file/printer sharing and
  consistent name resolution across local and organization networks.

Acceptance: browser downloads, calls, large transfers, VPN and local shares
continue or recover correctly across network changes and sleep.

### 8. Accounts, authentication and security

- [ ] Replace the single-user registration model with real users/groups,
  unprivileged desktop sessions, login/logout, locking and user switching.
  - [x] [Users, groups and passwords, the registered person imported as the
    first administrator, and homes only their owners can
    read](docs/accounts.md#accounts), tested in
    [QEMU guests](tests/accounts/README.md) on both architectures.
  - [x] [Sessions that are not root's, logins the kernel knows, and a seat
    that the display and input devices follow](docs/accounts.md#sessions).
  - [x] [A session manager: a login screen's own account, login, a logout
    that ends every process of the login, and switching by stopping the
    session that leaves](docs/accounts.md#the-session-manager), tested with
    stand-ins for the login screen and the desktop.
  - [ ] The desktop itself: a login screen and a lock screen, the compositor
    and its applications running as the person logged in, and init starting
    the session manager. Until then the desktop is root's and nothing above
    protects it.
- [ ] Provide authenticated privilege elevation through narrow services; move
  routine applications and desktop operations out of unrestricted root contexts.
  - [x] [An authentication service that runs listed actions as root for an
    administrator who gives their own password; no set-user-id
    programs](docs/accounts.md#the-authentication-service). Ten actions:
    power, the host name, accounts.
  - [ ] The desktop and its applications using it instead of being root, and
    actions for what they do as root today: packages, disks, the network,
    the clock.
- [ ] Apply measured default sandbox profiles to native apps, browsers, ports
  and compatibility runtimes; mediate files, network, devices and IPC.
  - [x] [Display, input and sound devices refused to whatever is not the
    session at the machine; disks, the console and serial lines refused to
    every account](docs/accounts.md#what-the-kernel-refuses-an-ordinary-account).
  - [ ] The profiles: nothing is measured and nothing is confined by default
    beyond Calculator. Network and IPC are not mediated per application.
- [ ] Add a permission UI for camera, microphone, location, screen capture,
  notifications and sensitive filesystem access, with revocation and auditing.
  - [ ] Not started. It needs applications that are not root and that the
    system can tell apart.
- [ ] Ship an encrypted credential/key store, certificate management, secure
  unlock, password changes/recovery and hardware-backed credentials where available.
  - [x] [A per-account credential store, opened at login with the password
    that was typed, with password change and a recovery
    key](tools/keyring/README.md).
  - [ ] Certificate management; keys held in hardware (there is no TPM or
    secure-enclave driver); the login and store passwords changed in one
    step; a place in the desktop for any of it.
- [ ] Complete production verified boot/root policy, executable/package trust,
  signing-key enrollment/revocation, antirollback and recovery-key lifecycle.
  - [ ] Not started beyond [what was there](docs/security.md#authenticated-uefi-images):
    an administrator's own key, no revocation, no antirollback, unsigned
    release images.
- [ ] Complete architecture hardening and mitigation coverage, including x86
  isolation/speculation gaps and ARM PAC/BTI where supported; document residual risk.
  - [x] [What not having pointer authentication and BTI leaves
    open](docs/security.md#arm-pointer-authentication-and-branch-target-identification),
    written down; the x86 gaps are those
    [already listed](docs/x86-cpu-mitigations.md).
  - [ ] Pointer authentication and BTI themselves, for the kernel and for
    programs; the x86 gaps closed.
- [ ] Extend mandatory policy and audit coverage to general IPC/network/security
  decisions, with session attribution, durable collection and retention controls.
  - [x] [A kernel record of security decisions attributed to the login,
    reports from trusted services, and a collector with exact loss accounting
    and retention settings](tools/security-events/README.md).
  - [ ] Mandatory policy for the network and for IPC in general; a record
    root cannot alter; the collector started at boot.
- [ ] Review kernel/userland parsers, drivers, privileged services and isolation
  boundaries; establish fuzzing, vulnerability reporting and a security-update process.
  - [x] [A fuzzer for the parsers that build on the host](tests/fuzz/README.md),
    [how to report a vulnerability](SECURITY.md), and
    [the process](docs/security-process.md), which also lists what has had no
    second reader.
  - [ ] The reviews themselves; fuzzing of the kernel's parsers of hostile
    input and of the system call interface; private reporting switched on
    for the repository; an update mechanism to deliver a fix with.

Acceptance: an ordinary desktop user cannot administer the machine or read
another user's private data; revoked permissions and failed confinement take effect.

### 9. Desktop shell, windows and session services

- [x] Extend existing tiling/overview/workspaces with configurable workspace
  management, coordinated layouts, app groups and multiple-display window policy.
- [x] Persist window placement and session restoration; recover gracefully from
  display changes, compositor restarts and crashed or hung applications.
- [x] Implement system notifications, notification history, quiet/focus modes,
  progress/status integration and alarms that continue after an app closes.
- [x] Provide supervised system/user services with dependency ordering, restart
  policy, logs, clean shutdown and reliable clock/time synchronization.
- [x] Provide shared file/folder dialogs, MIME associations, Open With, URI handlers,
  drag-and-drop, rich clipboard/history and secure app-to-app data exchange.
- [x] Complete system settings for sound, Bluetooth, printers, users, network,
  privacy, storage, updates, accessibility, clock/timezone and power policies.
- [x] Add consistent shortcut customization, gestures/hot corners, help,
  startup/session services, recent items and an application/service action API.

Acceptance: native and hosted applications share the same everyday workflows;
settings control real services and report unavailable capabilities accurately.

Implementation and API: [Desktop session services](desktop/SESSION.md). Device
controls use installed backends and accurately report missing drivers/tools.
Physical display hotplug and device/hosted-application workflows require guest
qualification with the corresponding hardware and applications.

### 10. Files, search and document workflows

- [x] Extend Files with tabs, multiple selection, batch operations, file-operation
  undo, drag-and-drop, permission editing and network/removable-volume navigation.
- [x] Complete per-volume Trash, recursive removal, restoration of metadata and
  safe behavior when destinations conflict or devices disappear.
- [x] Add cancellable background file operations with progress, retry, conflict
  choices, resumable large copies and clear failure results.
- [x] Implement indexed file/content/metadata search with permission-aware results,
  removable/network-volume policy and a system-wide launcher/search interface.
- [x] Extend Quick Look and previews to PDFs, office documents, media and common
  archives; integrate thumbnails, tags, recent documents and default apps.
- [x] Provide autosave, recovery, document versions and safe atomic saving through
  shared document services instead of independent application-specific hacks.

Acceptance: organize, find, preview, edit, copy, undo, delete and restore a real
mixed document tree across local, removable and network storage.

Implementation, provider requirements and tests:
[Files and document workflows](desktop/FILE_WORKFLOWS.md). Automated checks
include real cross-filesystem moves and undo. Physical removable-media removal,
network disconnects and external preview providers require guest qualification
with those devices and providers installed.

### 11. Accessibility, internationalization and text

- [ ] Expose accessible roles, names, values, focus, actions and live changes
  through the native UI protocol and bridges for hosted applications.
- [ ] Ship screen reading/speech, magnification, high contrast, scalable text,
  reduced motion, captions and complete keyboard-only navigation.
- [ ] Add sticky/filter keys, pointer alternatives, switch/voice control and
  configurable accessibility shortcuts with persistent per-user settings.
- [ ] Implement runtime font discovery/install, shaping, fallback, ligatures,
  combining marks, emoji, bidirectional text and correct wide-character layout.
- [ ] Support input methods, composition, dead keys, international layouts and
  selection/editing that respect grapheme boundaries across applications.
- [ ] Complete locale-aware date/time, timezone/DST, number/currency formatting,
  sorting/search and translated UI/help/error messages.
- [ ] Provide spelling, text services and dictation through shared interfaces;
  qualify Terminal text width, reflow and selection with international content.

Acceptance: a keyboard-only or screen-reader user completes installation and
daily work; multilingual documents retain correct text, layout and editing behavior.

### 12. Audio, media, capture and printing

- [ ] Provide an audio service with device discovery, mixing, per-app volume,
  routing, low-latency playback/capture and device switching.
- [ ] Add microphone/headset, USB/Bluetooth audio and Apple input/jack support;
  preserve speaker protection and restore device state after suspend.
- [ ] Support common media/container formats, streaming, subtitles, playlists,
  codec packaging and accelerated decode/encode on supported GPUs.
- [ ] Extend Capture with window/region selection, hotkeys, clipboard capture,
  destination selection, compressed recording and microphone/system audio.
- [ ] Provide webcam capture, camera permissions, video calls and screen sharing
  through consistent native/X11/Wayland/compatibility interfaces.
- [ ] Implement printer discovery/setup, spooling, job control, IPP/network and
  USB printing, print preview, PDF output and scanner integration.
- [ ] Add audio recording/editing utilities, MIDI devices/routing and color/font
  management utilities backed by real platform services.

Acceptance: join a call, switch a headset, share a window, record playback plus
microphone, print a document and scan/import a page without leaving Vinix.

### 13. Core applications and personal workflows

- [ ] Qualify Firefox/Chromium or equivalent browsers with sandboxing, downloads,
  accelerated media, WebRTC, password services, printing and default-browser handling.
- [ ] Complete office workflows with interoperable documents/spreadsheets/slides,
  clipboard, file dialogs, printing and accessibility in integrated suites.
- [ ] Extend Preview to PDF navigation/annotations, printing, metadata, additional
  image formats and color profiles; complete Editor rich text and recovery.
- [ ] Complete Calendar/Reminders with recurrence, timezones, notifications,
  multiple lists/calendars, imports, invitations and interoperable account sync.
- [ ] Add contacts and mail/account integration; integrate conferencing,
  messaging, cloud/network file sync and remote collaboration through usable clients.
- [ ] Complete scheduled/incremental Backup with retention, encrypted/network
  destinations, metadata preservation, snapshots and full-system restoration.
- [ ] Finish remaining utility gaps: compressed/encrypted archives, font management,
  credential management, automation, world clocks/alarms and persistent timers.
- [ ] Provide integrated photo/music/video organization, import, playback and
  editing; cover remaining reference-system capabilities in the feature matrix.

Acceptance: complete the published personal/office/media workflow set with real
files and accounts; local data remains usable when accounts or networking are offline.

### 14. Packages and application distribution

The [native V application store and Software manager](docs/application-distribution.md)
implement signed repositories, dependency planning, staged generations, rollback,
download recovery, atomic offline mirror exports, organization policy, authenticated repository
enrollment/revocation with retained replay history, and
[package/launch SDK 1](tools/packages/SDK.md). The original Alpine frontend still
manages system ports. Installed apps integrate with Start, Quick Launch and
shared MIME choices; an administrator-selected `launch_user` runs them through
an isolated ordinary account session. Release publisher enrollment, catalog migration,
graphical login/display-broker integration and broader guest/runtime qualification
remain required before this acceptance gate is complete. Host lifecycle/UI
fixtures and both target builds are available in
[the V qualification driver](tests/packages/distribution-check.v).

The [native SDK catalog](examples/package-catalog/README.md) now builds and pins
Hello, Counter and Memo for both architectures in one publisher workspace,
retaining their permissions, protocol versions and notices. Its
[qualification](tests/packages/native-catalog-check.md) exercises signed native
application maintenance; the broader catalog and graphical acceptance gate
above remains open.

- [ ] Harden the existing package frontend with trusted repositories, dependency
  resolution, reproducible metadata and consistent architecture support.
- [ ] Add transactional install/remove/upgrade, rollback, disk-space checks,
  interrupted-download recovery and coherent persistent package state.
- [ ] Provide a graphical software manager with search, descriptions, provenance,
  permissions, progress, uninstall, updates and useful failure diagnostics.
- [ ] Package native, Linux, Windows and Apple-compatible apps with isolated
  runtimes, launcher/association registration and clean uninstall behavior.
- [ ] Establish a supported application SDK/protocol, stable public interfaces,
  package format, signing/publishing process and developer documentation.
- [ ] Support offline repositories/caches and organization-managed deployment;
  keep firmware, proprietary payload licensing and runtime updates explicit.

Acceptance: a clean installed system can acquire and maintain the advertised
application catalog without host-side image rebuilds or manual runtime surgery.

### 15. Linux and POSIX compatibility

- [x] Build an ABI coverage matrix for both architectures, including syscalls,
  ioctls, signals, threading, filesystem behavior, proc/sysfs and runtime expectations.
  See [the behavior matrix](docs/linux-posix-compatibility.md) and the generated
  [native syscall inventory](docs/linux-syscall-coverage.md); dispatch coverage
  is separate from semantic qualification.
- [ ] Complete missing semantics required by mainstream musl and glibc software;
  use real error behavior and conformance tests rather than placeholder success.
- [ ] Support ordinary Linux desktop and CLI application installation, including
  service integration, sandbox/portal requirements and required packaging runtimes.
- [ ] Qualify native/translated x86-64 and 32-bit application paths on AArch64,
  including atomics, SIMD, TLS, JITs, debugging and memory/page-size assumptions.
- [x] Run application-driven regression suites for browsers, office/media tools,
  language runtimes, databases, servers and games; publish unsupported dependencies.
  See the [generated application results and dependency limits](docs/linux-application-coverage.md).
  Browser failures and unsupported runtime paths remain visible; running the
  regression catalog does not close the installation/sandbox acceptance gate.

- [x] Integrate a bounded Linux foreground-service unit subset with the native
  Services chooser and qualify HTTP start/restart/configuration restore/removal
  plus authorization and unsupported-directive refusals on both architectures.
  See [the unit contract and receipts](docs/linux-posix-qualification.md#linux-service-unit-integration).

- [x] Replace placeholder BPF/openat2 success with explicit errors and enforce
  faccessat2 empty-path permissions, with regression checks on both architectures.
- [x] Implement bounded futex REQUEUE/CMP_REQUEUE transfers, shared word keys,
  wake counts, bitsets and exact argument/timeout errors; qualify both native
  architectures plus real Go/OpenJDK threading workloads. See the
  [futex qualification receipts](docs/linux-posix-qualification.md#futex-requeue-and-shared-word-offsets).
- [x] Establish V build/guest/application qualification tools and publish native
  and translated x86-64 TLS/atomic/SIMD/JIT/page-size results plus SQLite/HTTP
  workload receipts and unsupported dependencies. See the
  [qualification report](docs/linux-posix-qualification.md).
- [x] Enforce openat2 NO_SYMLINKS, NO_MAGICLINKS and NO_XDEV, including bind
  mount identities, creation and procfs descriptor jumps; qualify O_PATH link
  handles, trailing-slash errors and exclusive creation on both architectures.
- [x] Qualify AArch64 Go compilation/execution and OpenJDK compilation,
  threaded file/network workloads and JAR execution with recorded runtime
  hashes and the required privileged Java launch policy. Installation, updates
  and desktop integration remain unqualified.
- [x] Retain the original open description through complete readv/writev calls;
  qualify blocked pipe close/dup2 races, untouched replacement data and final
  reference release as root/UID 1000 on both native architectures, with flat
  storage measurements. See [the vector lifetime receipts](docs/linux-posix-qualification.md#vectored-io-descriptor-lifetime).
- [x] Import readv/writev headers once, retaining the original addresses/lengths
  through concurrent header mutation/protection; qualify stack/heap vector
  storage, error cleanup and flat retention on both native architectures.
  See [the immutable iovec receipts](docs/linux-posix-qualification.md#immutable-iovec-imports).
- [x] Validate native readv/writev signed lengths and all canonical ranges
  before I/O, including invalid zero tails; enforce page-size transfer-count
  clamping and qualify EOF boundaries, unchanged file/pipe/socket data and
  flat error-path retention on both architectures. See [the range/count receipts](docs/linux-posix-qualification.md#native-vector-ranges-and-transfer-counts).
- [x] Preserve native 64-bit positioned-vector offsets, ignore pos_h, reject
  negative v1 offsets and reserve the current-position -1 sentinel for v2;
  qualify sparse data above 4 GiB/across 8 GiB, negative error precedence,
  file/pipe cursor behavior and flat retention on both architectures.
  See [the positioned-offset receipts](docs/linux-posix-qualification.md#native-positioned-vector-offsets).
- [x] Import native positioned vectors once and retain one open description;
  validate descriptor/access/pipe/socket errors before headers and complete
  original ranges and signed positions before I/O. Qualify readonly headers,
  unchanged data/cursors/queues, copied prefixes and flat retention on both
  architectures, with independent lifetime review. See [the positioned-import receipts](docs/linux-posix-qualification.md#native-positioned-vector-imports-and-errors).
- [x] Validate native preadv2/pwritev2 access, imported vectors and explicit
  positions before unknown flag errors; preserve valid empty transfers and
  low-32-bit flag decoding without changing data, cursors or pipe/socket queues.
  Qualify both credential groups and flat storage on both architectures. See
  [the vector-flag receipts](docs/linux-posix-qualification.md#native-vector-flags-and-error-precedence).
- [x] Decode lower-32-bit descriptors in all six native vector syscalls while
  preserving full-width counts and the existing single descriptor owner.
  Qualify real data/cursors/pipe queues, import/seek/access errors and negative
  positions as root/UID1000, with flat retention on both architectures. See
  [the descriptor-width receipts](docs/linux-posix-qualification.md#native-vector-descriptor-words).
- [x] Scatter one available pipe/socket receive across native readv and v2
  current-position vectors; qualify UNIX record boundaries, truncation, next
  messages and 1 MiB payloads as root/UID1000 on both architectures, with flat
  retention and published destination-fault limits. See
  [the stream-vector receipts](docs/linux-posix-qualification.md#native-stream-vector-receives).
- [x] Retire selected native UNIX datagram/seqpacket records on vector copy
  faults and return EFAULT even after copied prefixes; qualify empty queues,
  empty/short records, import refusals and flat storage on both architectures.
  See [the record-fault receipts](docs/linux-posix-qualification.md#native-unix-record-vector-copy-faults).
- [x] Refuse lseek on O_PATH handles and aliases before policy/type/argument
  errors; qualify metadata, private permissions and ordinary sparse seeks as
  root/UID1000 on both architectures, with flat descriptor cleanup storage.
  See [the pathname-seek receipts](docs/linux-posix-qualification.md#native-o_path-seek-access).
- [x] Decode native scalar read/write/pread64/pwrite64/lseek/close descriptor
  and seek-selector words while retaining full-width counts and signed offsets;
  qualify real bytes/cursors/queues, closure, sparse data and flat storage on
  both architectures. See [the scalar-word receipts](docs/linux-posix-qualification.md#native-scalar-syscall-argument-words).
- [x] Return native lseek invalid-selector errors after descriptor validation
  and before pipe/socket/device type errors; qualify unchanged aliases,
  metadata, bytes/cursors/queues/readiness and flat storage on both architectures.
  See [the selector-error receipts](docs/linux-posix-qualification.md#native-seek-selector-error-precedence).
- [x] Support generic native SEEK_DATA/SEEK_HOLE reporting and real ENXIO
  boundaries; qualify signed64 sparse positions, shared aliases, retained
  bytes/metadata/blocks, bounded backup-style copies and flat storage on both
  architectures. See [the DATA/HOLE receipts](docs/linux-posix-qualification.md#generic-native-data-and-hole-seeks).
- [x] Validate native ftruncate descriptor eligibility before policy/growth;
  enforce O_PATH EBADF and nonregular/readonly/mode3 EINVAL, qualifying real
  shrink/grow bytes, metadata, aliases, queued data and flat storage on both
  architectures. See [the ftruncate receipts](docs/linux-posix-qualification.md#native-ftruncate-descriptor-eligibility).
- [x] Decode native ftruncate descriptors from the lower 32 register bits;
  preserve signed64 lengths and existing ownership, qualifying real resizing,
  access/type/negative errors, bytes, aliases, queued data and flat storage on
  both architectures. See [the descriptor-word receipts](docs/linux-posix-qualification.md#native-ftruncate-descriptor-words).
- [x] Reject native truncate nonregular pathname targets before policy/growth,
  preserving directory EISDIR and other-type EINVAL independently of prior
  errors; qualify symlink targets, real resizing, aliases, metadata, queued
  bytes and flat storage on both architectures. See [the pathname receipts](docs/linux-posix-qualification.md#native-pathname-truncate-type-errors).
- [x] Decode native readlink/readlinkat sizes as signed32 and reject nonpositive
  sizes before lookup/copying; qualify exact target prefixes, musl zero-size
  scratch behavior, real errors, retained descriptor state and flat storage on
  both architectures. See [the readlink receipts](docs/linux-posix-qualification.md#native-readlink-size-words).
- [x] Read symlink targets through empty-path readlinkat handles, including
  unlinked and private O_PATH descriptions; retain descriptor ownership through
  real lookup/copy errors and qualify aliases, metadata, queues and flat storage
  on both architectures. See [the empty-path receipts](docs/linux-posix-qualification.md#native-empty-path-readlink).
- [x] Return relative procfs self/thread-self targets for each reading process
  and thread; qualify inherited handles, alternate mounts, chroot resolution
  and flat native storage on both architectures. See [the procfs link receipts](docs/linux-posix-qualification.md#relative-procfs-self-and-thread-self-links).
- [x] Report selected task Pid/NSpid with process Tgid; qualify main/pthread
  readers, inherited root and own PID views, namespace columns and flat storage
  on both native architectures. See [the task-status receipts](docs/linux-posix-qualification.md#selected-task-status-identities).
- [x] Report selected task stat identity and scheduling fields; qualify FIFO/RR
  workers, named/numeric paths, root/own PID views and flat native storage on
  both architectures. See [the task-stat receipts](docs/linux-posix-qualification.md#selected-task-stat-identity-and-scheduling).
- [x] Report selected task stat CPU/minor-fault accounting using real counters
  and live snapshots; qualify positive demand faults, CPU work, process totals
  and flat native storage. See [the accounting receipts](docs/linux-posix-qualification.md#selected-task-stat-cpu-and-fault-accounting).
- [x] Report the selected task's procfs state even while a sibling runs; qualify
  real pipe-backed sleeping readers, stopped/zombie controls and flat native
  storage on both architectures. See [the state receipts](docs/linux-posix-qualification.md#selected-procfs-task-states).
- [x] Report selected task names, including empty names and status escapes;
  implement bounded prctl name copies and qualify fork/exec inheritance,
  exact native bytes/errors and flat storage. See [the name receipts](docs/linux-posix-qualification.md#selected-procfs-task-names).
- [x] Serialize native exec name/path replacement with procfs readers;
  qualify concurrent old/new records, real child execs and flat observer
  retention on both architectures. See [the exec receipts](docs/linux-posix-qualification.md#procfs-metadata-publication-during-exec).
- [x] Validate native statx requests and argument words before lookup/output;
  qualify real metadata, NULL descriptors, exact errors and flat retention
  against Linux on both architectures. See [the statx receipts](docs/linux-posix-qualification.md#native-statx-requests-and-error-precedence).
- [x] Correct native fstat/newfstatat descriptor words, flag errors and NULL queries;
  qualify metadata, libc/legacy controls and flat retention against Linux
  on both architectures. See [the stat receipts](docs/linux-posix-qualification.md#native-stat-descriptor-words-and-flag-errors).
- [x] Validate native dup/dup3 argument words and reject unknown flags;
  preserve x86 dup2 self calls and qualify alias/target state, real errors
  and flat retention against Linux. See [the duplicate receipts](docs/linux-posix-qualification.md#native-descriptor-duplication-errors-and-words).
- [x] Finalize duplicate descriptor flags before publication; qualify concurrent
  flag observers, fork snapshots and close/reuse with isolated scheduling controls
  on both architectures. See [the publication receipts](docs/linux-posix-qualification.md#descriptor-flags-before-publication).
- [x] Decode native fcntl words and scalar arguments without narrowing pointers;
  preserve EINVAL for invalid duplicate minima, EBADF for invalid sources and
  EMFILE for valid exhausted requests. See [the fcntl receipts](docs/linux-posix-qualification.md#native-fcntl-words-and-duplicate-minima).
- [x] Refuse non-pathname fcntl commands on O_PATH handles before pointer copies
  or state changes; qualify allowed operations, aliases, exact errors and flat
  retention on both architectures. See [the command receipts](docs/linux-posix-qualification.md#o_path-fcntl-command-refusals).
- [x] Implement F_DUPFD_QUERY using real open-description identity and exact
  invalid-descriptor errors; qualify aliases, reopened files, native argument
  words and flat retention on both architectures. See [the identity receipts](docs/linux-posix-qualification.md#fcntl-duplicate-description-queries).
- [x] Implement F_CREATED_QUERY with the actual per-open creation result shared
  by aliases and fork; qualify reopens, symlinks, unlink/recreation, ignored
  arguments and flat retention on both architectures. See [the creation receipts](docs/linux-posix-qualification.md#fcntl-file-creation-queries).
- [x] Preserve open-time O_SYNC/O_DSYNC across F_SETFL changes; qualify shared
  append/nonblocking state, native words, exact refusals, descriptor replacement
  and flat retention on both architectures. See [the status receipts](docs/linux-posix-qualification.md#fcntl-synchronization-status-preservation).

- [x] Implement real native open-description record locks, including POSIX
  conflicts, own-lock queries, range conversion and final-alias/fork lifetime;
  qualify blocking unlock/downgrade/EINTR and flat storage on both architectures.
  See [the lock receipts](docs/linux-posix-qualification.md#native-open-description-record-locks).

- [x] Accept native record-lock ranges through INT64_MAX and preserve Linux
  normalized endpoint/query/error behavior; qualify all six POSIX/OFD commands,
  boundary splits/merges, aliases, unchanged file state and flat storage.
  See [the range receipts](docs/linux-posix-qualification.md#native-signed-record-lock-ranges).

- [x] Enforce native advisory-lock access and exact flock operations, including
  mode3/O_PATH errors and low32 descriptor/operation words; qualify all six
  record commands, aliases, retained locks/file state and flat storage.
  See [the access receipts](docs/linux-posix-qualification.md#native-advisory-lock-access-and-words).

- [x] Preserve same-kind flock ownership without release/reacquisition; qualify
  queued contenders, regular/directory aliases, real conversions/final close,
  ordinary/private scheduling-window kernels and flat storage on both architectures.
  See [the repetition receipts](docs/linux-posix-qualification.md#same-kind-flock-ownership).

- [x] Qualify native F_SETSIG/F_GETSIG configuration against Linux, including
  signal boundaries, upper words, aliases, ignored arguments, descriptor
  limits/replacement, retained file/queue state and flat storage.
  See [the signal-control receipts](docs/linux-posix-qualification.md#native-fcntl-signal-configuration).

- [x] Correct native F_SETOWN/F_GETOWN command mapping and reject invalid owner
  targets with Linux errors before state changes; qualify raw/musl aliases,
  getters, descriptor limits/replacement and flat storage on both architectures.
  See [the owner-control receipts](docs/linux-posix-qualification.md#native-fcntl-owner-commands-and-target-errors).

- [x] Map native fcntl owner getters to attached task kinds and caller PID
  namespaces; qualify reaped/joined targets, surviving groups, aliases and flat
  storage on both architectures. See
  [the getter receipts](docs/linux-posix-qualification.md#native-fcntl-owner-task-kinds-and-namespaces).

- [x] Invalidate selected cached procfs task paths after thread removal/reaping;
  qualify live siblings, zombie leaders, aliases, one-level PID views and flat
  repeated lookup storage on both architectures. See
  [the task-path receipts](docs/linux-posix-qualification.md#cached-procfs-task-path-invalidation).

- [x] Invalidate cached numeric procfs process roots after reap while keeping
  live/zombie and static/dot paths reachable; qualify aliases, one-level PID
  views, exact errors and flat repeated lookup storage on both architectures.
  See [the process-root receipts](docs/linux-posix-qualification.md#cached-procfs-process-root-invalidation).

- [x] Decode native faccessat2 flag words and assign anonymous pipe creator
  ownership before publication; qualify real permission/errors, aliases and
  retained state as root/UID1000 with flat storage on both architectures.
  See [the access receipts](docs/linux-posix-qualification.md#native-faccessat2-flag-words-and-pipe-owners).

- [x] Decode native pipe2 flag words, reject unknown bits before pointers and
  refuse unimplemented packet/notification modes; qualify ordinary pipe aliases,
  transfers, errors and flat storage as root/UID1000 on both architectures.
  See [the pipe receipts](docs/linux-posix-qualification.md#native-pipe2-flag-words-and-errors).

- [x] Construct native pipe endpoints privately and publish both descriptor slots
  together; qualify EMFILE cleanup, lowest-slot selection, transfers and retained
  state under descriptor pressure, with flat storage on both architectures.
  See [the construction receipts](docs/linux-posix-qualification.md#native-pipe-construction-under-descriptor-pressure).

- [x] Return native pipe2 descriptor-limit errors before nil-output faults;
  qualify exact EMFILE/EFAULT precedence, untouched descriptor state, ordinary
  transfers and flat pressure-cohort storage on both architectures.
  See [the error receipts](docs/linux-posix-qualification.md#native-pipe2-null-output-error-precedence).

- [x] Return native EBADF for pipe-only fcntl commands on nonpipe
  descriptions; qualify real pipe/FIFO capacities, aliases, words, descriptor
  limits/reuse, retained data and flat storage on both architectures.
  See [the type-error receipts](docs/linux-posix-qualification.md#native-pipe-only-fcntl-type-errors).

- [x] Normalize native pipe capacities to the architecture page size, reject
  overflowing unsigned requests with EINVAL, and apply the growth ceiling
  using effective CAP_SYS_RESOURCE; qualify aliases, retained bytes, errors
  and flat resize storage on both architectures and same-ELF Linux.
  See [the rounding and capability receipts](docs/linux-posix-qualification.md#native-pipe-capacity-rounding-and-capability-ceilings).

- [x] Decode signed32 native legacy scheduler PID/policy words and match
  parameter error precedence; qualify guarded buffers, retained policy/priority,
  real transitions and flat storage on both architectures and same-ELF Linux.
  Publish musl wrapper refusals and the AArch64 multi-CPU QoS blocker.
  See [the scheduler receipts](docs/linux-posix-qualification.md#native-scheduler-scalar-words-and-error-precedence).

- [x] Report native SCHED_EXT priority bounds as Linux metadata while retaining
  real errors for invalid policies; qualify raw/libc words, unchanged policy
  and priority, and flat query storage on both architectures and same-ELF Linux.
  Keep SCHED_EXT/BPF class installation and runtime support explicitly separate.
  See [the priority metadata receipts](docs/linux-posix-qualification.md#native-sched_ext-priority-metadata).

- [x] Decode native RR interval PID words and resolve targets before output
  faults; qualify guarded raw/musl calls, real RR intervals, retained state
  and flat query storage on both architectures and identical-ELF Linux.
  Keep scheduler-dependent durations and remaining policy/foreign gaps explicit.
  See [the interval receipts](docs/linux-posix-qualification.md#native-rr-interval-pid-words-and-output-errors).

- [x] Match native scheduling-attribute query PID words, input errors and exact
  short-buffer prefixes; validate full advertised user ranges before copying.
  Qualify RR/BATCH state, native page bounds, guarded outputs and flat storage
  on both architectures and identical-ELF Linux; publish reference setup limits.
  See [the attribute-query receipts](docs/linux-posix-qualification.md#native-scheduling-attribute-query-prefixes-and-errors).

- [x] Match native scheduling-attribute input layouts, PID words and real errors,
  including size-zero compatibility, exact short imports, zero extensions and
  best-effort E2BIG size writebacks. Qualify root/UID1000 state, guarded inputs
  and flat storage on both architectures and identical-ELF Linux; retain setup
  and oracle failures separately. See [the import receipts](docs/linux-posix-qualification.md#native-scheduling-attribute-import-contract).

- [x] Match native affinity PID/length words, short CPU masks and stable-peer
  owner/CAP_SYS_NICE permissions with real errors and retained state. Qualify
  guarded raw/musl calls, worker/peer targets and flat storage on both architectures
  and identical-ELF Linux; measure bitmap widths and retain placement/security/race/foreign gaps.
  See [the affinity receipts](docs/linux-posix-qualification.md#native-affinity-masks-argument-words-and-stable-peer-permissions).

- [x] Normalize native sched_attr nice, enforce target RLIMIT_NICE and effective
  CAP_SYS_NICE admission, preserve nonfair nice and default nice limits to zero.
  Qualify 29,310 single-thread process-leader checks per architecture with Linux
  references, real state/restoration, flat storage and independent lifetime review.
  See [the bounded nice contract](docs/linux-posix-qualification.md#native-scheduling-attribute-nice-normalization-and-admission).

- [x] Enforce native target RLIMIT_RTPRIO admission, retain/lower existing RT
  priority and require privilege for a zero-limit RT policy switch. Qualify
  31,118 process-leader controls per architecture against identical-ELF Linux,
  with real errors/state/restoration, flat storage and independent lifetime review.
  See [the realtime admission contract](docs/linux-posix-qualification.md#native-realtime-scheduling-admission).

- [x] Enforce target current-nice/RLIMIT_NICE admission before leaving IDLE,
  including ordinary, batch and realtime destinations with real owner/capability
  permissions. Qualify 25,008 leader controls per architecture against identical-ELF
  Linux, guarded inputs, actual state/restoration and flat storage; retain setup gaps.
  See [the idle scheduling contract](docs/linux-posix-qualification.md#native-idle-scheduling-exit-permissions).

- [x] Return zero scheduling-attribute nice for FIFO/RR while retaining actual
  task nice and ordinary/IDLE query values. Qualify 24,016 leader controls per
  architecture against identical-ELF Linux, guarded prefixes, peer queries,
  exact errors/state and flat repeated-query storage, with independent review.
  See [the realtime query contract](docs/linux-posix-qualification.md#native-realtime-scheduling-attribute-queries).

- [x] Decode native process-priority selector/target/nice words as signed32
  and return ESRCH for missing/negative process targets. Qualify 13,214 leader
  controls per architecture against identical-ELF Linux, real raw/musl state,
  exact errors and flat repeated-call storage, with independent lifetime review.
  See [the priority-word contract](docs/linux-posix-qualification.md#native-priority-argument-words-and-missing-target-errors).

- [x] Enforce PRIO_PROCESS setpriority using effective CAP_SYS_NICE and the
  target's RLIMIT_NICE; qualify UID0/no-capability restrictions, non-root
  capability grants, owner/error ordering, genuine musl calls, retained state,
  upper argument words and flat repeated-path storage against Linux on
  both native architectures. See the
  [capability/limit receipts](docs/linux-posix-qualification.md#native-priority-capability-and-target-limit-admission).

- [x] Reject incompatible getrandom RANDOM/INSECURE flags with EINVAL before
  zero-count handling or user copies; qualify raw/musl calls, guarded buffers,
  exact errors and valid controls against identical-ELF Linux on both native
  architectures, with flat repeated-path storage. See the
  [random-flag receipts](docs/linux-posix-qualification.md#native-getrandom-flag-validation).

- [x] Return positive getrandom short counts after partial output faults;
  qualify guarded PROT_NONE/read-only/unmapped suffixes, raw/musl calls, root
  and UID1000, native page/chunk boundaries and exact repeated native copying
  on both architectures against identical-ELF Linux references. See the
  [partial-copy receipts](docs/linux-posix-qualification.md#native-getrandom-partial-copy-faults).

- [x] Cap getrandom requests and reject complete out-of-userspace ranges
  before output, including invalid zero-count addresses; qualify guarded
  low/high arenas, raw/musl calls, real errors/partial data and flat storage
  on both native architectures against identical-ELF Linux. See the
  [request-range receipts](docs/linux-posix-qualification.md#native-getrandom-request-ranges).

- [x] Return completed page prefixes when signals interrupt large seeded
  getrandom transfers, give cooperative timers a scheduling point, and honor
  blocked signals, SA_RESTART and complete small requests. Qualify both native
  architectures against identical-ELF Linux references; retain the initial
  AArch64 failure and flat repeated-call storage. See the
  [signal-interruption receipts](docs/linux-posix-qualification.md#native-getrandom-signal-interruption).

- [x] Normalize signed 32-bit process/group arguments and return Linux negative
  getpgid/getsid/setpgid errors with correct precedence; qualify both native
  architectures against identical-ELF Linux, including real group changes,
  retained sessions, zombie/reaped queries and flat repeated-call storage. See
  [the group/session receipts](docs/linux-posix-qualification.md#native-process-group-and-session-argument-words).

- [x] Resolve live worker TIDs in native getpgid/getsid and reject nonleader
  setpgid targets with EINVAL; qualify independently retired TID errors, actual
  child group changes and worker callers as root/UID1000 in initial and one-level
  PID namespaces on both architectures, with flat storage and lifetime review.
  See [the task-lookup receipts](docs/linux-posix-qualification.md#native-worker-process-group-and-session-lookup).

- [x] Check native setpgid child-session eligibility before executed-child
  refusal; qualify real exec, child/grandchild error ordering, group mutations
  and retained identities as root/UID1000 in initial and one-level PID namespaces
  on both architectures, with identical-ELF Linux references and flat storage.
  See [the session/exec receipts](docs/linux-posix-qualification.md#native-process-group-session-and-exec-error-precedence).

- [x] Admit completed zombie setpgid targets and zombie-only destination groups
  until reap, preserving incomplete-teardown exclusion and exact errors. Qualify
  real mutations, wait-group selection, live joins and reaped identities as
  root/UID1000 in initial/one-level PID namespaces on both architectures, with
  flat storage and lifetime review. See [the zombie-group receipts](docs/linux-posix-qualification.md#native-completed-zombie-process-groups).

- [x] Import native wait4/waitid scalar arguments from low32 register words;
  preserve option-error priority and reject wait4 INT_MIN with ESRCH. Qualify
  live/zombie selection, WNOWAIT, ignored outputs and reaped errors as root/UID1000
  in initial/one-level PID namespaces on both architectures, with flat storage.
  See [the wait ABI receipts](docs/linux-posix-qualification.md#native-wait-selectors-and-scalar-argument-words).

- [x] Match native waitid empty/error siginfo writes, preserving padding/tail
  and giving output EFAULT priority over selector errors. Qualify NULL/unused
  pointers, mapped and split-field guard output, WNOWAIT/reaped controls as
  root/UID1000 in initial/one-level PID namespaces on both architectures.
  See [the empty/error output receipts](docs/linux-posix-qualification.md#native-waitid-empty-and-error-siginfo-output).

- [x] Report the child real UID in native waitid stop, continuation, exit and
  signal-death results. Qualify distinct real/effective/saved identities, high
  unsigned UIDs, selectors, raw/musl calls, WNOWAIT/consuming controls and flat
  storage for root/ordinary callers in initial/one-level PID namespaces.
  See [the child real-UID receipts](docs/linux-posix-qualification.md#native-waitid-child-real-uid).

- [x] Match native waitid child-event siginfo field writes and preserve padding
  and unused payload. Qualify aligned/unaligned and guard-page results, ordered
  field faults, NULL/valid outputs, four child states and credential profiles,
  raw/musl calls and flat storage in initial/one-level PID namespaces.
  See [the child-event output receipts](docs/linux-posix-qualification.md#native-waitid-child-event-siginfo-writes).

- [x] Copy native waitid rusage before siginfo, preserving Linux output and
  EFAULT ordering. Qualify untouched siginfo after rusage faults, preceding
  rusage after siginfo faults, overlapping layouts, four child states, raw/musl
  calls and flat storage as root/ordinary callers in both PID namespace views.
  See [the rusage/siginfo order receipts](docs/linux-posix-qualification.md#native-waitid-rusage-and-siginfo-copyout-order).

- [x] Consume native wait4/waitid child events after copyout faults, retaining
  waitid WNOWAIT events. Qualify four states, bad status/siginfo/rusage pointers,
  raw/musl calls, selectors and flat fork/fault/reap/close storage as root and
  ordinary callers in both PID namespace views, with independent lifetime review.
  See [the consuming-fault receipts](docs/linux-posix-qualification.md#native-wait-copyout-fault-event-consumption).

- [x] Preserve native wait4 status bytes on stable split-page EFAULT, with valid
  cross-page stores, unaligned outputs, NULL/valid rusage and unused bad pointers.
  Qualify four child states, raw/musl calls, selectors and flat fork/store/reap
  storage as root/ordinary callers in both PID namespace views.
  See [the scalar-status receipts](docs/linux-posix-qualification.md#native-wait4-scalar-status-copyout).

- [x] Match native get_robust_list low32 PID imports and length-before-head
  scalar stores, including overlaps, NULL and stable split-page faults. Qualify
  self/leader/worker and retired targets, root/UID1000 in two PID namespace views,
  identical-ELF Linux comparisons and flat pipe-blocked-worker query storage.
  See [the robust-list query receipts](docs/linux-posix-qualification.md#native-robust-list-query-pid-words-and-ordered-scalar-output).

- [x] Complete pending non-PI robust unlock wakes and select one ordinary exit
  waiter while preserving PI queue separation and unchanged ownerless words.
  Qualify confirmed queues, real musl recovery and flat fork/requeue/exit cleanup
  as root/UID1000 in both PID namespace views, with identical-ELF Linux controls.
  See [the robust exit receipts](docs/linux-posix-qualification.md#native-robust-futex-pending-unlock-and-selective-exit-wakes).

- [x] Use real IDs and permitted capability subsets for native robust-list
  inspection, requiring effective CAP_SYS_PTRACE for privileged overrides.
  Qualify split credentials, target dumpability, process_vm payload/error
  behavior and flat caller/target cleanup in both credential/PID namespace views.
  See [the inspection receipts](docs/linux-posix-qualification.md#native-robust-list-and-process-memory-inspection-credentials).

- [x] Wake one shared futex waiter after a native thread clears its TID;
  qualify registration replacement/disable/aliasing, exact remaining queues,
  untouched guards, real musl joins and flat owner/worker cleanup as root/UID1000
  in both PID namespace views, with identical-ELF Linux controls.
  See [the TID exit receipts](docs/linux-posix-qualification.md#native-clear-child-tid-selective-exit-wakes).

- [x] Preserve one shared clear-child-tid wake when its zero store faults on
  a readable MAP_SHARED word; retain inaccessible/unmapped and read-only private
  anonymous queues. Qualify real access faults, guarded data, admitted waiters
  and flat three-waiter cleanup in both credential/PID namespace views.
  See [the TID fault receipts](docs/linux-posix-qualification.md#native-clear-child-tid-store-fault-notifications).

- [x] Suppress clear-child-tid stores and wakes for stable last-map-user exits,
  preserving one-waiter notification with a surviving thread or CLONE_VM
  process; qualify replacement/read-only aliases, queue isolation and cleanup
  on both native architectures against the identical ELF on Linux.
  See [the last-user receipts](docs/linux-posix-qualification.md#native-clear-child-tid-last-address-space-user).

- [x] Validate clone3 exit-signal words and reject forbidden thread/parent
  combinations before later admission errors; qualify import faults, protected
  layouts, SIGCHLD fork/reap and flat cleanup on both native architectures
  against identical probe ELFs on Linux.
  See [the clone3 signal receipts](docs/linux-posix-qualification.md#native-clone3-exit-signal-validation).

- [x] Reject clone3 cgroup descriptor words above INT_MAX with Linux EINVAL;
  preserve in-range EBADF, input-fault precedence and ignored-field fork/reap,
  with protected layouts and flat cleanup on both native architectures against
  identical probe ELFs on Linux.
  See [the cgroup descriptor receipts](docs/linux-posix-qualification.md#native-clone3-cgroup-descriptor-range).

- [x] Validate clone3 stack ranges before stack-pointer arithmetic; qualify
  wrapping/kernel intervals, valid-range admission without page access, input
  faults, inherited-stack forks and flat cleanup on both native architectures
  against identical probe ELFs on Linux.
  See [the stack range receipts](docs/linux-posix-qualification.md#native-clone3-stack-range-admission).

- [x] Validate clone3 flag words, rejecting unknown high bits, reserved legacy
  bits and conflicting shared/cleared handlers; stop unrequested child creation
  and qualify import precedence, recognized admission, fork/reap and flat
  cleanup on both native architectures against identical probe ELFs on Linux.
  See [the flag receipts](docs/linux-posix-qualification.md#native-clone3-flag-word-validation).

- [x] Honor clone3 CLONE_CLEAR_SIGHAND on both native architectures; qualify
  caught/default/ignored dispositions, cleared action metadata, ordinary
  inheritance, parent isolation, blocked masks, actual delivery and flat cleanup
  against identical probe ELFs on Linux.
  See [the disposition receipts](docs/linux-posix-qualification.md#native-clone3-cleared-signal-dispositions).

- [x] Import zero-filled clone3 argument extensions up to the native page limit;
  qualify exact nonzero/fault precedence, all older prefix lengths, protected
  layouts, real extended forks and flat cleanup on both native architectures
  against identical probe ELFs on Linux.
  See [the extensible import receipts](docs/linux-posix-qualification.md#native-clone3-extensible-argument-import).

- [x] Validate clone3 selected-TID pointer/count pairs before later admission;
  reject mismatched/oversized pairs, stop unintended children, and qualify
  counts 1–32 reaching permission checks, argument-import precedence, ordinary
  forks and flat cleanup on both native architectures against identical Linux
  probe ELFs. Requested-TID allocation remains separate.
  See [the pair validation receipts](docs/linux-posix-qualification.md#native-clone3-selected-tid-pair-validation).

Acceptance: published Linux workloads install, run, save, update and integrate
with the desktop on the advertised architecture/runtime combination.

### 16. Windows, macOS and mobile application compatibility

- [ ] Expand Wine support across Win32/Win64 and supported ARM/x86 paths;
  qualify installers, runtime libraries, fonts, COM, audio and document handling.
- [ ] Integrate Windows apps with file dialogs, clipboard, associations, printing,
  accessibility, permissions, process diagnostics and per-app runtime management.
- [ ] Qualify Direct3D translation and game workloads with GPU acceleration,
  controllers, networking, sound and save persistence; track DRM/anti-cheat blockers.
- [ ] Design and implement a macOS desktop compatibility path: Mach-O/dynamic
  linking, Darwin interfaces, Objective-C/Swift/C++ runtimes and required frameworks.
- [ ] Build AppKit/Foundation, graphics/text, audio, event/lifecycle and document
  integration from measured macOS application requirements; UIKit examples alone
  cannot satisfy this desktop target.
- [ ] Qualify representative macOS CLI and GUI applications on supported CPU
  architectures, including resources/bundles, permissions and desktop integration.
- [ ] Expand existing iOS/Android subsets with graphics, input, storage, lifecycle,
  notifications and platform APIs; measure them as additional compatibility tracks.
- [ ] Publish a versioned compatibility database with reproducible install/task
  results, performance, known failures and external-service restrictions.

Acceptance: compatibility is recorded per application/version/workflow, beyond
startup screenshots. Coverage must meet the agreed matrix before claiming parity.

### 17. Development, containers and virtualization

- [ ] Make Vinix self-hosting: build the kernel, desktop, userland and packages
  inside an installed Vinix system with documented, reproducible tooling.
- [ ] Qualify C/C++/V, Python, JavaScript/TypeScript, Rust, Go, Java and other
  reference toolchains, package managers, debuggers, IDEs and build systems.
- [ ] Complete tracing/debugging interfaces, core dumps, symbols, profiling,
  process stack sampling and hang/crash reports without bypassing authorization.
- [ ] Finish namespaces, resource groups, overlay storage and security semantics
  needed by OCI containers; qualify a mainstream runtime and rootless workflows.
- [ ] Expand VM hosting beyond the small VT-x interface: practical memory sizes,
  multiple vCPUs, interrupts/devices, Intel/AMD and ARM virtualization backends.
- [ ] Provide a maintained QEMU/backend integration or compatible host API,
  guest tools, snapshots, networking, shared folders and VM lifecycle management.
- [ ] Qualify local databases, web/server workloads, SSH development and CI;
  provide automation/scheduled jobs with credentials and permissions under control.

Acceptance: develop, debug, test and package a real project; run an isolated
container and a practical hardware-accelerated guest OS on supported hosts.

### 18. Remote work, administration and system observability

- [ ] Provide authenticated remote desktop and screen sharing, explicit consent,
  session locking and controlled clipboard/file/device redirection.
- [ ] Support organization identities/directories, certificate enrollment, policy,
  managed network configuration and remote application/update deployment.
- [ ] Complete Activity Monitor's per-process network/GPU/energy/wakeup accounting,
  historical diagnostics, exited-process accounting and resource-group visibility.
- [ ] Add structured system logs, crash/hang reports, bounded retention, boot/service
  diagnostics and export that protects sensitive data.
- [ ] Provide an administrative CLI/API for services, users, storage, networking,
  updates and policy, with discoverable help and auditable privilege boundaries.
- [ ] Establish release channels, reproducible image/package manifests, source and
  license provenance, migration notes, hardware documentation and maintenance policy.

Acceptance: a machine can be diagnosed, maintained and used remotely while
preserving the same identity, permission and data-protection guarantees.

## Qualification workflows

Every workflow must have automated checks where possible and a recorded manual
check for physical hardware, accessibility and third-party services. Use original
documents, real application behavior and independently checked outputs.

| Workflow | Required result |
| --- | --- |
| Install and maintain | Install to disk, boot without installer media, create users, update, interrupt an update, roll back and recover while preserving data. |
| Work all day | Browse, download, edit office/PDF documents, print, join a video call, share a window, receive reminders and back up the resulting files. |
| Use a laptop | Battery boot, Wi-Fi/VPN, Bluetooth headset, lid close/open, repeated sleep/resume and external-display reconnect restore usable devices and windows. |
| Manage documents | Import files from each reference OS; search, preview, copy between volumes/shares, resolve conflicts, undo, trash/restore and recover earlier versions. |
| Develop software | Clone, build and debug a project locally; run a container and VM; rebuild Vinix from the installed system. |
| Run existing apps | Install representative Linux, Windows and macOS applications and complete their documented tasks; exercise translated and mobile runtimes separately. |
| Use assistive technology | Install, log in, configure devices and complete document/browser work using keyboard-only navigation, screen reading and magnification. |
| Survive failure | Exhaust memory/disk/resources, kill apps/services, disconnect devices, reset a GPU and interrupt scratch-disk writes; recover without a machine panic or silent data loss. |
| Protect multiple users | Try unauthorized file/process/device/network access, permission revocation, elevation, confinement escape and untrusted package/update installation. |

## 1.0 release gates

These are proposed minimum qualification budgets. M0 should pin the exact
machines, workload sizes and performance targets; weakening a gate requires a
visible scope decision, not relabeling a failing test as completed.

- [ ] Every requirement in the agreed parity matrix is qualified with current
  evidence. All reference workflows above pass on each applicable platform.
- [ ] Both architecture production builds, userland/images, relevant kernel guest
  suites and desktop behavior suites pass against the exact release revision.
  Optional or unavailable features cannot substitute success markers for execution.
- [ ] A 72-hour mixed-workload soak completes on each reference machine without
  unexplained panic, deadlock, unbounded growth or lost durable data.
- [ ] At least 100 suspend/resume and display/device hotplug cycles complete on
  each applicable physical reference machine, preserving function and permissions.
- [ ] At least 100 controlled interruption/fault cycles on disposable test disks
  qualify storage, update and recovery behavior; verified durable data is preserved.
- [ ] Kernel repeated-path measurements are flat after explicit cache warmup or
  have a demonstrated finite bound. Run the existing `ops,churn,cache` measurements,
  allocation-site audit and desktop `idle,apps,drag` checks from isolated builds;
  track existing allowance/stress failures until resolved. See [kernel workflow](AGENTS.md#finding-memory-leaks-in-the-kernel)
  and [performance harness](tests/desktop-perf/README.md).
- [ ] Publish matched reference-system benchmarks for boot/login, idle CPU/memory,
  input/frame latency, app startup, storage, networking, builds, translation and
  battery life. Meet hardware-specific budgets, including a usable 4 GiB baseline
  desktop; large compatibility workloads have their own published requirements.
- [ ] Default installations use unprivileged user sessions, authenticated updates,
  working confinement and recovery. Security review has no unresolved critical or
  high-severity release blockers, and the vulnerability/update process is operational.
- [ ] No known blocker remains for data integrity, installation/recovery, advertised
  hardware, supported app workflows or accessibility; publish all lesser known issues.
- [ ] Release images, package sources, checksums/signatures, manuals, support matrix,
  migration guidance and rollback/recovery instructions are available and reproducible.

## First implementation priorities

1. Reconcile the existing kernel/desktop audits with current code and turn the
   feature matrix plus unresolved regression failures into tracked work.
2. Finish data durability, independent disk boot, recovery and atomic updates.
3. Introduce real unprivileged accounts/sessions and narrow privileged services.
4. Finish swap/reclaim and resource exhaustion handling; remove measured leaks.
5. Qualify M1 Wi-Fi IP connectivity, GPU/display, input, audio and suspend/resume,
   alongside a fully supported Intel/AMD PC hardware configuration.
6. Build shared accessibility, text, dialogs, clipboard, notifications and device
   services so remaining applications can integrate with one coherent platform.
7. Complete ordinary daily-use workflows, then broaden application/runtime,
   container and VM coverage against the same acceptance matrix.

Update this roadmap as requirements become qualified. Link each completed item
to its implementation and evidence; keep partial features and external blockers
visible until their acceptance workflows are satisfied.
