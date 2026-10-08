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
| Memory pressure | Cache reclaim, pressure reporting, allocation reserves and process OOM recovery | Swap/compression, broader reclaim and resource charging; exhausting kernel-owned resources still needs protection. See [OOM behavior and limits](tests/oom/README.md). |
| Storage and installation | ext2, persistent VM roots, block drivers, flush paths, optional verified root and an M1 installer | Crash-safe filesystem, encryption, snapshots, autonomous disk boot, recovery and physical storage qualification. See [image installation](README.md#download-an-image), [M1 installer](installer/macos/README.md) and [ANS limits](docs/apple-ans-rw-root.md). |
| Native desktop | Window management, tiling, overview, workspaces, taskbar, Settings, Files and 21 native utilities | Multiple displays, full desktop services, accessibility and remaining utility workflows. See [window experience](desktop/WINDOW_EXPERIENCE.md), [utility inventory](desktop/UTILITIES.md) and [Settings](desktop/SETTINGS.md). |
| Networking and peripherals | Ethernet networking, IPv4/IPv6, selected USB/input paths, sound playback, experimental M1 Wi-Fi and Apple drivers | General hotplug/classes, wireless IP connectivity, Bluetooth, recording, peripheral coverage and power management. See [networking status](docs/openbsd-feature-implementation.md#networking), [Wi-Fi limits](docs/apple-wifi.md) and [M1 audio](docs/m1-speakers.md). |
| Graphics | Native framebuffer composition, X11, an AArch64 Hyprland path, VirtIO graphics work and Apple/Intel bring-up | Qualified hardware GPU/display pipelines, complete driver integration, resets and interoperable composition. See [i915 integration](docs/linux-i915.md#remaining-driver-integration) and [M1 AGX](docs/m1-agx-bringup.md). |
| Applications | Package frontend, browsers, office/media ports, Wine, x86 translation and iOS/Android subsets | Broad compatibility qualification, consistent desktop integration and macOS desktop runtime work. See [packages](README.md#packages-on-aarch64), [Wine](docs/wine.md), [iOS](docs/ios.md) and [Android](docs/android.md). |
| Security and sessions | Capabilities, mount policies, confinement mechanisms, selected audit collection, optional authenticated UEFI/root and a persistent desktop profile | Real multiuser login and unprivileged sessions, secure default launch policy, credential services and complete deployment lifecycle. See [security scope](docs/security.md) and [single-user registration](desktop/registration_store.v). |
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

- [ ] Add disk-backed anonymous paging, encrypted swap, memory compression and
  pageout/refault with correct shared/private mapping behavior.
- [ ] Finish dirty/reference tracking and reclaim for mapped file pages; retain
  correct writeback through unmap, unlink, truncation and storage failures.
- [ ] Extend current OOM recovery to bounded, charged kernel resources, including
  files, descriptors, sockets, IPC, mappings and process/thread creation.
- [ ] Complete resource groups: memory/CPU/I/O/PID limits, pressure notifications,
  workload accounting and predictable recovery from quota exhaustion.
- [ ] Qualify fork/exec/exit, vfork/clone semantics, signals, timers, futexes and
  job control under SMP, cancellation, rapid process churn and resource pressure.
- [ ] Improve run-queue and allocator scalability, priority inheritance, workload
  QoS, heterogeneous-core placement and deadline-driven idle/timer coalescing.
- [ ] Complete architecture-specific address-space/TLB work and large-page
  support where useful; verify protection and teardown during concurrent access.
- [ ] Eliminate measured per-operation retention and close unresolved kernel
  stress failures; audit generated V-to-C allocations and every new lifetime.

Acceptance: repeated workloads stop growing memory after warmup, resource abuse
does not panic the machine, and the desktop remains usable during pressure.

### 3. Filesystems, storage and data protection

- [ ] Ship a crash-safe primary filesystem with journaled or copy-on-write
  recovery; cover metadata ordering, rename/replace and mapped write durability.
- [ ] Add volume management, storage pools/RAID, full-disk encryption, key recovery,
  online capacity management, TRIM/discard and storage health/error reporting.
- [ ] Implement filesystem snapshots, clones/reflinks, version restoration and
  incremental backup primitives with explicit consistency guarantees.
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
- [ ] Provide common device enumeration, driver binding/removal, firmware loading,
  DMA mappings, IOMMU isolation and safe timeout/reset infrastructure.
- [ ] Support the common storage, Ethernet, wireless, graphics and audio device
  families needed by the reference PC/laptop set; identify vendor dependencies.
- [ ] Implement CPU idle/frequency control, thermal management, fan/sensor APIs,
  battery/charging policy and accurate remaining-time/energy reporting.
- [ ] Add reliable suspend/resume, lid behavior, wake sources, screen sleep,
  hibernation and shutdown/reboot that flushes storage and quiesces devices.
- [ ] Restore all device and security state after sleep, firmware errors and
  hotplug; keep recovery possible when a driver fails.

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
- [ ] Provide authenticated privilege elevation through narrow services; move
  routine applications and desktop operations out of unrestricted root contexts.
- [ ] Apply measured default sandbox profiles to native apps, browsers, ports
  and compatibility runtimes; mediate files, network, devices and IPC.
- [ ] Add a permission UI for camera, microphone, location, screen capture,
  notifications and sensitive filesystem access, with revocation and auditing.
- [ ] Ship an encrypted credential/key store, certificate management, secure
  unlock, password changes/recovery and hardware-backed credentials where available.
- [ ] Complete production verified boot/root policy, executable/package trust,
  signing-key enrollment/revocation, antirollback and recovery-key lifecycle.
- [ ] Complete architecture hardening and mitigation coverage, including x86
  isolation/speculation gaps and ARM PAC/BTI where supported; document residual risk.
- [ ] Extend mandatory policy and audit coverage to general IPC/network/security
  decisions, with session attribution, durable collection and retention controls.
- [ ] Review kernel/userland parsers, drivers, privileged services and isolation
  boundaries; establish fuzzing, vulnerability reporting and a security-update process.

Acceptance: an ordinary desktop user cannot administer the machine or read
another user's private data; revoked permissions and failed confinement take effect.

### 9. Desktop shell, windows and session services

- [ ] Extend existing tiling/overview/workspaces with configurable workspace
  management, coordinated layouts, app groups and multiple-display window policy.
- [ ] Persist window placement and session restoration; recover gracefully from
  display changes, compositor restarts and crashed or hung applications.
- [ ] Implement system notifications, notification history, quiet/focus modes,
  progress/status integration and alarms that continue after an app closes.
- [ ] Provide supervised system/user services with dependency ordering, restart
  policy, logs, clean shutdown and reliable clock/time synchronization.
- [ ] Provide shared file/folder dialogs, MIME associations, Open With, URI handlers,
  drag-and-drop, rich clipboard/history and secure app-to-app data exchange.
- [ ] Complete system settings for sound, Bluetooth, printers, users, network,
  privacy, storage, updates, accessibility, clock/timezone and power policies.
- [ ] Add consistent shortcut customization, gestures/hot corners, help,
  startup/session services, recent items and an application/service action API.

Acceptance: native and hosted applications share the same everyday workflows;
settings control real services and report unavailable capabilities accurately.

### 10. Files, search and document workflows

- [ ] Extend Files with tabs, multiple selection, batch operations, file-operation
  undo, drag-and-drop, permission editing and network/removable-volume navigation.
- [ ] Complete per-volume Trash, recursive removal, restoration of metadata and
  safe behavior when destinations conflict or devices disappear.
- [ ] Add cancellable background file operations with progress, retry, conflict
  choices, resumable large copies and clear failure results.
- [ ] Implement indexed file/content/metadata search with permission-aware results,
  removable/network-volume policy and a system-wide launcher/search interface.
- [ ] Extend Quick Look and previews to PDFs, office documents, media and common
  archives; integrate thumbnails, tags, recent documents and default apps.
- [ ] Provide autosave, recovery, document versions and safe atomic saving through
  shared document services instead of independent application-specific hacks.

Acceptance: organize, find, preview, edit, copy, undo, delete and restore a real
mixed document tree across local, removable and network storage.

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

- [ ] Build an ABI coverage matrix for both architectures, including syscalls,
  ioctls, signals, threading, filesystem behavior, proc/sysfs and runtime expectations.
- [ ] Complete missing semantics required by mainstream musl and glibc software;
  use real error behavior and conformance tests rather than placeholder success.
- [ ] Support ordinary Linux desktop and CLI application installation, including
  service integration, sandbox/portal requirements and required packaging runtimes.
- [ ] Qualify native/translated x86-64 and 32-bit application paths on AArch64,
  including atomics, SIMD, TLS, JITs, debugging and memory/page-size assumptions.
- [ ] Run application-driven regression suites for browsers, office/media tools,
  language runtimes, databases, servers and games; publish unsupported dependencies.

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
