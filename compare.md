# Where Vinix can be better

Goal: combine Linux's openness, Windows' application reach and macOS's desktop
coherence in a smaller, understandable system that users control.

Comparison baseline: 9 October 2026. **Existing** means the implementation is
present; **measured** means a specific recorded comparison supports the claim;
**target** means an intended advantage that still needs implementation and proof.
Targets below are proposals for the [1.0 roadmap](roadmap.md), not guarantees.
Linux comparisons must name a distribution and desktop: many Linux systems
already provide these benefits, and a minimal Linux installation is a different
performance baseline from a full desktop.

## Existing strengths

| Strength | What Vinix offers | Where the advantage lies |
| --- | --- | --- |
| An operating system you can change | Kernel, native desktop and utilities are available in this repository, with first-party implementation moving to V. See [source license](LICENSE) and [kernel migration](docs/kernel-v-migration.md). | Direct control over the system's behavior. Linux shares the source-availability benefit; Vinix's opportunity is a simpler, more approachable implementation. This is not a claim of automatic memory safety. |
| One file browser for different working styles | Files includes list, Finder-style, Miller-column and dual-pane views. See [Files inventory](desktop/UTILITIES.md#existing-applications). | Choose a browsing or two-directory workflow inside the bundled application. This is a convenience advantage, not a claim that Files already exceeds Finder, Explorer or Linux file managers in completeness. |
| A combined window-management workflow | Tiling, Snap Assist, an arrangement chooser, window overview, workspaces, taskbar previews and hide-others actions in one native shell. See [window experience](desktop/WINDOW_EXPERIENCE.md). | Combine useful interaction patterns associated with the different desktops without replacing the shell or installing extensions. Individual features are not unique to Vinix. |
| Useful core apps without a vendor account | Local Notes, Calendar, Reminders, Backup, offline Dictionary and desktop registration work with local data. See [utility inventory](desktop/UTILITIES.md) and [registration](desktop/registration_store.v). | Basic work need not depend on cloud login or a subscription. Linux and macOS also support local workflows; the concrete setup contrast is Windows 11 Home below. |
| One desktop already hosting several application families | Native V apps, Alpine Linux applications, selected Wine programs and iOS/Android demonstrations have integration paths. See [Wine](docs/wine.md), [iOS](docs/ios.md) and [Android](docs/android.md). | A foundation for reducing the need to switch operating systems. Compatibility remains partial; macOS desktop apps are a separate unfinished target. |
| A desktop designed to avoid unnecessary work | Unchanged frames are skipped; pointer movement and window dragging can update damaged regions. The native desktop and kernel use explicit memory management. See [frame loop](desktop/main.v) and [desktop memory design](desktop/README.md#memory). | A foundation for lower idle cost and predictable resource use. Other systems also use damage tracking and native code; lower overall CPU, memory or battery use still requires matched measurements. |

Windows 11 Home's documented first-use setup requires internet access and a
Microsoft account. Vinix's existing local registration avoids that particular
dependency; production login, locking and multiple users remain roadmap work.
[Microsoft's setup requirements](https://learn.microsoft.com/en-us/windows/whats-new/windows-11-requirements).

Linux's Dolphin already provides split views, so dual-pane browsing is not a
unique advantage over Linux. The benefit to pursue is the complete combination
of views and file operations in the default application.
[Dolphin view documentation](https://docs.kde.org/stable_kf6/en/dolphin/dolphin/dolphin-view.html).

## Recorded performance wins

The archived v6 allocation campaign measured lower median elapsed time for
Vinix than **macOS Catalina 10.15.7** in all six workloads, in both cohorts and
their pooled samples. Pooled results use 14 samples per system per workload.
[Method and raw evidence](tests/alloc-bench/results/2026-10-03-userspace-v6/README.md).

| Workload | Vinix median, ns/pair | Catalina median, ns/pair | Lower elapsed time |
| --- | ---: | ---: | ---: |
| Hot 64-byte allocation/free | 228.85 | 387.65 | 41% |
| Mixed-size allocation batches | 313.80 | 777.99 | 60% |
| Allocate/touch/free 256 KiB | 1,537.30 | 18,458.80 | 92% |
| Map/unmap 4 KiB | 11,432.80 | 27,426.50 | 58% |
| Map/touch/unmap 256 KiB | 669,947.75 | 1,924,765.85 | 65% |
| Create/close a pipe | 29,889.35 | 70,205.85 | 57% |

These are archived x86-64 QEMU TCG measurements with common CPU/RAM settings,
not native hardware results or measurements of the current checkout. Compiler
minor versions and some VM peripherals differed. Allocation timings include
Vinix's modified musl runtime; they are not solely kernel performance results.
They do not establish superiority over current macOS, Linux or Windows, or
predict application, graphics or battery performance.
[Full comparison](tests/alloc-bench/results/2026-10-03-userspace-v6/comparison.md).

The archive's validator can recompute the results from all retained samples:

```sh
python3 tests/alloc-bench/results/2026-10-03-userspace-v6/recompute.py
```

## Advantages to build toward 1.0

Every row is a **target**, even where foundations already exist. The comparison
column identifies the opportunity, not a proven deficiency in every competing
system. Roadmap numbers identify the relevant implementation workstreams.

| Target advantage | What better should mean for the user | Comparison and roadmap work |
| --- | --- | --- |
| Lower total overhead | Faster boot and app launches, less idle CPU/RAM, fewer background wakeups and a responsive desktop on modest hardware. | Beat named full-desktop configurations on matched workloads; measure lean Linux separately. Roadmap 2, 4, 5 and release benchmarks. |
| More applications in one OS | Install Linux, Windows, macOS and supported mobile apps through one software manager, with managed runtimes and normal desktop windows. | Broader combined workflow coverage than any single native ecosystem, with less manual compatibility setup. Roadmap 14–16; no universal app-support promise. |
| Linux software without a second guest OS | Native Linux-compatible application paths, toolchains and services integrated with Vinix's own processes, storage and permissions. | Reduce guest administration for Windows/macOS users who need Linux tools; Linux already provides this natively. Roadmap 15 and 17. |
| Less desktop configuration work | One supported settings system, coherent defaults, discoverable features and equivalent GUI/CLI administration. | Reduce the steps needed to configure a named reference Linux desktop or Windows installation. macOS's integrated experience is a baseline to match. Roadmap 9 and 18. |
| Consistent behavior across app origins | Shared file dialogs, clipboard, drag-and-drop, fonts, notifications, shortcuts and accessibility across native and compatibility apps. | Reduce integration gaps when combining toolkits and runtimes. Every hosted app family must be tested. Roadmap 9–12 and 14–16. |
| Local operation by default | Offline setup and core tools, local search/documents and optional cloud accounts. | More independence from online setup and service availability; Linux already offers strong local operation. Roadmap 1, 8, 10 and 13. |
| Clear control over data collection | No behavioral telemetry or advertising in the proposed default system; explicit consent and an inspectable control for optional diagnostic uploads. | Easier-to-understand privacy defaults and fewer controls to manage. Validate network behavior; third-party apps retain their own policies. Roadmap 8 and 18. |
| User-chosen online services | Standards-based mail/calendar/contacts, storage and sync; export and migration without requiring one vendor's account. | Less switching cost between providers and operating systems. Linux often already supports these choices. Roadmap 7, 13 and 18. |
| Recoverable updates with less effort | Atomic activation, an obvious previous-version boot option, one-action rollback and user data preserved through recovery. | Beat reference systems on recovery time and steps, not merely the presence of rollback. Some Linux distributions already implement atomic updates. Roadmap 1, 3 and 14. |
| Permissions you can understand and revoke | A coherent view of files, devices, network and capture permissions across native, Linux and compatibility applications. | Reduce policy fragmentation and unmanaged legacy-app access while preserving useful workflows. Roadmap 8, 9 and 14–16. |
| Better behavior under pressure | Keep the desktop usable when an app exhausts RAM, disk, descriptors or CPU; explain the failure and recover resources. | Lower measured UI stalls and fewer system-wide failures under equivalent stress. Existing OOM recovery is a foundation, not a comparative win. Roadmap 2 and 18. |
| Easier backup and document recovery | Scheduled incremental backups, snapshots and file versions available in the normal document workflow, with verifiable restores. | Combine strong recovery with clear control over destination, retention and encryption. Time Machine and Linux snapshot tools are serious baselines. Roadmap 3, 10 and 13. |
| The same experience on PCs and Macs | A consistent desktop, app packaging and workflows across qualified x86-64 PCs and Apple Silicon machines. | More hardware choice for users who want a Mac-like integrated workflow. Linux already spans these platforms; Vinix must qualify its drivers. Roadmap 4–6. |
| Longer useful life for applications | Versioned runtimes and maintained translation paths keep supported older software working through CPU and OS changes. | Reduce avoidable application loss during upgrades, while documenting security and external-service limits. Roadmap 14–16. |
| Easier system development | Readable V-first components, reproducible builds and a supported path to build and debug Vinix inside Vinix. | Reduce the effort to understand or change the complete stack; Linux already supports self-hosting and modification. Roadmap 14, 17 and 18. |
| Diagnostics that explain failures | Join process, service, package, device and resource evidence in useful reports; show unavailable data explicitly. | Faster diagnosis without hunting across unrelated tools or guessing from incomplete counters. Roadmap 2, 8 and 18. |
| Accessible defaults across runtimes | Keyboard-only use, screen reading, magnification and international text work across the same application catalog. | Reduce gaps between native and hosted apps. Measure task completion against established accessibility support. Roadmap 9, 11 and 16. |
| A reproducible, inspectable release | Published build inputs, manifests, signatures and compatibility evidence make regressions traceable and fixes reviewable. | Give users and maintainers more direct evidence about what ships. Linux projects already offer comparable mechanisms. Roadmap 14, 18 and release gates. |

## What the other systems already do well

Vinix should compete with the real alternatives, including their existing
integration features:

- Linux and macOS can already run Windows applications through Wine. Vinix's
  opportunity is managed installation and consistent integration, not inventing
  that capability. [Wine's platform scope](https://www.winehq.org/).
- Windows already integrates Linux GUI apps through WSL, including launchers,
  window switching and clipboard. Vinix must demonstrate a benefit beyond just
  displaying a Linux window. [WSL GUI integration](https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps).
- macOS already translates Intel applications on Apple Silicon through Rosetta.
  Vinix must prove its own compatibility and performance rather than treating
  translation as unique. [Apple's Rosetta support](https://support.apple.com/en-us/102527).
- Atomic Linux systems already support transactional updates and rollback.
  Vinix's target is better usability and recovery qualification.
  [rpm-ostree administration](https://coreos.github.io/rpm-ostree/administrator-handbook/).
- Windows diagnostic controls vary by edition and policy; organization editions
  can disable diagnostic data. The proposed Vinix benefit is simple, explicit
  defaults, not a claim that every Windows installation is uncontrollable.
  [Microsoft's diagnostic policies](https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization).
- macOS has open-source components, including its kernel. Vinix's source-level
  advantage should be assessed across the complete native desktop stack.
  [Apple Open Source](https://opensource.apple.com/).

## How an advantage becomes a claim

- Name the competing release, Linux desktop/distribution, hardware and app versions.
- Match workloads, enabled features and security settings; retain raw results,
  failures and relevant differences between configurations.
- For performance, measure distributions of latency, throughput, memory and power.
  For usability, measure task completion, steps, errors and recovery time.
- For compatibility, complete real install/edit/save/update workflows and publish
  supported versions and failures. A launch screenshot is insufficient.
- For privacy, inspect actual connections and permissions; for reliability and
  accessibility, use the [roadmap qualification workflows](roadmap.md#qualification-workflows).

The priority is the combination: openness and control, broad app coverage,
coherent daily workflows and demonstrably low overhead. A stronger claim against
any of the three platforms needs evidence for that specific advantage.
