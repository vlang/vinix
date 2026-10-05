# Desktop utility inventory and macOS feature gaps

Audited against the sources in this repository on 2026-10-05. This document
records what was present, what this change implements, and the remaining work.
It does not claim complete macOS parity.

The native utilities are Files, Activity Monitor, Settings, Text Editor,
Calculator, Calendar, Clock, Capture, Disk Usage and Terminal. Both desktop
image builders install their executable names as clients of the multicall
desktop. Files Settings, Quick Look, Quick Launch and the notification area are
supporting surfaces rather than additional utility payloads.

The macOS comparison uses Apple's [included-app inventory](https://support.apple.com/en-gb/guide/mac-help/mchl110b00b7/26/mac/26)
and the individual guides linked below. Priorities and implementation plans are
Vinix engineering proposals based on the inspected code.

## Existing applications

| Vinix utility / macOS counterpart | Present before this change | Implemented in this change | Remaining gaps |
| --- | --- | --- | --- |
| Files / Finder | List, Finder and Miller-column views, dual-pane mode, sorting, current-folder search, navigation history, sidebar, tags, Quick Look, rename/copy/cut/paste/permanent delete and view preferences | Get Info for the selected file, including POSIX metadata and symbolic-link targets | Move to Trash, restore and empty Trash; multiple selection and batch operations; file-operation undo; tabs; recursive/content/metadata search; file associations and Open With; drag-and-drop file operations; permission editing; shared folders |
| Activity Monitor / Activity Monitor | Process search, application/owner/activity filters, process trees, selectable sortable columns, inspector, terminate/force-quit/suspend/resume/priority controls; CPU/per-core, memory, disk, network, GPU submission and battery histories; refresh control, process diagnostic reports and startup apps | Inactive, other-user and selected-process filters; CSV export of the visible process list; clear resource/GPU/power graph history without discarding counter baselines | Persistent view preferences; per-process network, energy, GPU and wakeup accounting; actual process stack sampling and hang/crash reports; CPU history in taskbar; compressed-memory/swap accounting if those facilities are introduced |
| Settings / System Settings | Appearance, date/time display preferences, language, theme, wallpaper, Wi-Fi radio/scan/status, backlight/display scaling, battery history and keyboard layouts | About pane reading the actual kernel version, reported CPU/architecture, physical memory and uptime, with Refresh and unavailable-data states | Settings search; clock/timezone setters; user management; accessibility; audio devices/volume; Bluetooth; printers; IP/DNS/proxy configuration; GUI package/update management; sleep/power policies |
| Text Editor / TextEdit | Plain-text UTF-8 open/edit/save, cursor navigation and paste; byte-preserving handling of invalid UTF-8 | Bounded undo/redo; exact Find with next/previous and wrapping; highlighted matches; Replace and Replace All, with size checks and undo | General selection/cut/copy, mouse caret/selection, Save As/file picker, unsaved-close/open confirmation, autosave/recovery/versions, wrapping, rich text, spelling, printing and larger documents |
| Calculator / Calculator | Pointer-operated basic decimal arithmetic, percent, sign and powers | Keyboard arithmetic and backspace, numeric paste validation, memory register, relative percentages, bounded result history with paging and recall | Scientific functions, programmer bases/bitwise operations, RPN, expression parsing, unit/currency conversion, selectable/copyable results, display precision/grouping and history persistence |
| Calendar / Calendar | Month navigation, selected dates, localized weeks and Today | Persistent local all-day/timed events with titles and locations; creation/editing/deletion; marked dates and selected-date agenda | Duration/multiday events, day/week/year views, recurrence, search, reminders/notifications, multiple calendars, ICS import/export, CalDAV/accounts and invitations |
| Clock / Clock | Local time and a monotonic stopwatch with pause/resume/reset | Bounded lap/split/total records; countdown timer, duration presets/adjustment, pause/resume/reset and visible expiry | World clocks and timezone database; scheduled/repeating alarms; multiple named timers; sound/notifications; persistence and a service that continues after the app closes |
| Capture / Screenshot and screen recording | Full-desktop PNG, delay, self-hiding, 5/10 fps AVI recording, stop/cancel and status | Recording-delay controls on the Video page; Enter to start and Escape to stop/cancel | Window/region selection, output-location chooser, clipboard capture, cursor toggle, capture hotkeys, thumbnail/reveal workflow, audio and compressed video |
| Disk Usage / Storage settings | Resumable size inventory, largest-folder/file rankings, hard-link deduplication, symlink avoidance, drill-down, parent navigation, stop and rescan | Editable scan root and report destination, keyboard input, raw-byte CSV report with proper text escaping and overwrite protection | Capacity/free-space/mount overview, allocated versus logical size, storage categories, treemap, reveal in Files and guarded cleanup; disk management belongs in a separate utility |
| Terminal / Terminal | Real PTY/Zsh, VT cursor/alternate-screen support, UTF-8 cells, bounded scrollback, paste and rebuild handoff | Find in scrollback/live screen with next/previous and wrap, match-row highlighting, and clear scrollback preserving live/alternate-screen contents | Selection and copy, tabs/split panes, profiles/fonts/colours, configurable history, complete ANSI colours/attributes, hyperlinks and command bookmarks |

Relevant macOS references: [process browsing](https://support.apple.com/en-ie/guide/activity-monitor/actmntr1001/mac)
and [diagnostics](https://support.apple.com/guide/activity-monitor/run-system-diagnostics-actmntr2225/mac),
[TextEdit search/replace](https://support.apple.com/guide/textedit/find-and-replace-text-txtef6cfde1a/mac),
[Calculator modes](https://support.apple.com/guide/calculator/choose-the-right-mode-calc22d50970/mac),
[Calendar events](https://support.apple.com/en-gb/guide/calendar/icalwr13-events/mac)
and [calendar interchange](https://support.apple.com/guide/calendar/import-or-export-calendars-icl1023/27.0/mac/27),
[Clock](https://support.apple.com/en-mide/guide/clock-mac/welcome/mac)
and [screenshot targets](https://support.apple.com/en-ie/102646).

### Hosted and installable applications

`available_apps` also registers the following entries. A launcher in the menu
does not establish that its external payload is installed: build flags,
staging directories and `pkg` determine that. They are audited as integrations;
their third-party application internals are outside the native-utility changes.

| Entries | macOS comparison and remaining integration work |
| --- | --- |
| Firefox, Chromium | Browser alternatives to Safari. Payload installation, default-browser/file associations, downloads/recent items and sandbox integration remain separate work. |
| Wine Calculator, Wine Notepad, Microsoft Word 2013 | Compatibility programs; native Calculator and Text Editor provide the utility baseline. Clipboard, associations, accessibility and translated-process integration remain incomplete. |
| VOffice Writer, VOffice Calc, LibreOffice | Optional office suites. Printing, document associations, clipboard and file-dialog integration are the relevant desktop gaps. |
| Blender, GIMP, OBS Studio | Graphics/media applications, rather than replacements for the small macOS utilities. Keep their upstream functionality; improve file dialogs, clipboard, audio and surface integration as those services become available. |
| Minecraft, DOOM, Steam, Gothic II, Roblox, Dota 2 | Games and stores, without a matching macOS system utility. Installation, graphics, sound, controller input and compatibility belong to their existing ports. |
| Vinix in QEMU | Virtual-machine integration; no bundled macOS utility equivalent. Guest input, clipboard, storage and session management remain integration work. |
| Android Calculator, iOS Calculator, iOS 2048 | Compatibility demonstrations. Platform API and lifecycle support belong to the Android/iOS layers. |

These 21 entries plus the ten native utilities account for the complete
31-entry application catalog. Vim and shell tools installed in the userland
are terminal programs, not additional native desktop applications.

## Missing utility applications to implement

The macOS names below identify the comparison. The milestones are proposed
Vinix applications, with dependencies made explicit. Existing terminal tools,
Disk Usage, Quick Look or a browser do not supply the corresponding complete
desktop workflow.

| Priority | Utility / macOS comparison | First useful milestone | Dependencies or boundary |
| --- | --- | --- | --- |
| P1 | Preview | Standalone image/PDF viewer, zoom, rotation, page navigation, save/export | Reuse image decoding and Quick Look; add a maintained PDF renderer. Annotations and printing follow. |
| P1 | Console | Browse and tail kernel/app logs, search/filter and export | Define log locations, retention and access controls; do not fabricate crash reports from ordinary logs. |
| P1 | System Information | CPU/memory/device, mount, driver and installed-package inventory with export | Start with real procfs/device/pkg reports. Settings About now supplies the small summary. |
| P1 | Archive Utility | Browse/extract/create common archives, progress/cancel and errors | Use available archive tools; reject path traversal and escaping links during extraction. |
| P1 | Disk Utility | Read-only disks/partitions/mounts/capacity overview, then mount/unmount | Block/mount discovery and privilege mediation. Formatting, repair and partition editing need explicit destructive-operation UI and filesystem tools. |
| P1 | Backup / Time Machine workflow | Versioned folder backup, browse versions and restore to a chosen destination | Durable destination handling, free-space limits and clear restore conflicts; system snapshots are later filesystem work. |
| P2 | Notes / Stickies | Persistent searchable notes with autosave and export | A local document store; sharing, rich text and sync can follow. |
| P2 | Reminders | Persistent tasks, due dates and completion | A notification/scheduling service is required for alerts when the app is closed. |
| P2 | Font Book | Preview installed fonts, inspect metadata and install/remove per-user fonts | Runtime font discovery/rendering; the desktop currently relies on baked coverage atlases. |
| P2 | Digital Color Meter | Pick framebuffer colours, magnify the sample and copy RGB/hex values | Compositor sampling IPC and a guest clipboard copy service. |
| P2 | Grapher | Plot mathematical functions with axes/ranges and export | Expression parser and plotting/export support. |
| P2 | Audio MIDI Setup | Output/input devices, formats, levels and test recording | Real audio-device enumeration and mixer/recording APIs; MIDI is a later dependency. |
| P2 | Voice Memos | Record, play, trim and save local audio | Capture/playback devices and codecs. |
| P2 | Passwords / Keychain Access | Local encrypted credential store, lock/unlock and export | Threat model, vetted cryptography and secure unlock/key storage; avoid a plaintext credential database. |
| P2 | Shortcuts / Automator | User-defined launch/file workflows with visible progress | Stable app actions, file pickers, cancellation and permissions for unattended actions. |
| P3 | Image Capture | Camera/scanner import, destination selection and transfer status | Camera/scanner discovery and device protocols. |
| P3 | Print Center | Printer setup and queued-job control | Printing/spooling service and drivers. |
| P3 | Screen Sharing | View/control another desktop | Remote display transport, authentication and explicit session control. |
| P3 | Bluetooth File Exchange | Paired-device file transfer | Bluetooth controller, pairing and transfer stack. |
| P3 | ColorSync Utility | Inspect/assign display/image colour profiles | ICC/profile parsing and a colour-managed rendering path. |
| P3 | Migration Assistant | Import supported user files and settings with a reviewable plan | Source-format adapters, conflict handling and rollback. |
| P3 | Directory Utility | Manage directory-service identities | Identity service, authentication and network-directory protocols. |
| P3 | VoiceOver Utility | Configure screen-reader/navigation behaviour | Accessibility tree exposure, focus navigation and speech output first. |
| P3 | Dictionary | Offline definitions and lookup | Redistributable dictionaries, indexing and text-selection integration. |

AirPort/base-station management, Apple account services, FaceTime, Find My and
Boot Camp depend on vendor services or platform-specific hardware; they are
not proposed as general Vinix utility ports.

## Using the implemented workflows

- **Files:** select an entry, use Get Info or Ctrl-G, and close with Escape.
- **Activity Monitor:** the filter control cycles the process groups. Export
  (Ctrl-E) writes `Activity-Monitor-Processes.csv` in the user's home. In tree
  mode it includes visible context ancestors. Clear History (Ctrl-L) resets
  resource/GPU/power graphs while retaining rate baselines; battery charge
  history remains the shared battery service's history.
- **Editor:** Ctrl-Z/Ctrl-Y undo/redo; Ctrl-F opens Find; Ctrl-G finds the next
  match. Find is an exact UTF-8 byte search at character boundaries. Replace
  All is one undoable action. History is bounded and not a recovery journal.
- **Calendar:** select a date, choose New event, enter a title and optionally
  a time/location, then Save. Select an agenda event to edit/delete it. Events
  are local to the user's home and do not sync or issue alerts.
- **Clock:** record laps while the stopwatch runs; use the Timer tab for a
  countdown. Expiry is visible in this app; there is no background alarm.
- **Calculator:** use digits/operators/Enter and Backspace, memory buttons,
  or click a recent result to recall it. History is bounded to 20 results.
- **Terminal:** click Find, type an exact query, use the arrows or Enter to
  advance, and Escape to return keyboard input to the shell. Matches are
  physical output rows, including scrollback; Clear scrollback keeps the
  current terminal screen.
- **Disk Usage:** edit Folder and Scan; edit Report and Export CSV. Existing
  report files are preserved. Export a completed or cancelled scan; cancelled
  scans are explicitly marked partial by their phase. Reports contain the
  retained rankings rather than every file.
- **Capture:** Video now exposes the recording delay. Enter starts the chosen
  operation and Escape stops/cancels it.
- **Settings:** choose About and Refresh to read system-reported information.
  Missing data is labelled unavailable.

## Validation

`desktop/tools/test-utility-parity.sh` stages the actual desktop and ui2 model
and runs the new utility behavior tests together, using the production V
frontend with `-gc none -manualfree`. It is also called by
`desktop/tools/test-utilities.sh`, whose existing cases exercise native app IPC,
Files, UTF-8 editing/terminal rendering and the application catalog. Run
`desktop/tools/test-settings.sh` for preference/device and translation checks,
and `desktop/tools/test-activity.sh` for process controls and resource lifetimes.

Cross-build and guest smoke results are recorded in the change handoff. Local
calendar records, timer expiry, undo/replace, exports and terminal search have
behavioral coverage; host tests alone do not verify new driver/service features.

The existing compositor `memory_test.v` has three baseline failures with the
current compiler/ui2: eight idle redraws retain 8,960 bytes, Start-menu redraws
retain 10,206 bytes, and 100 idle polls retain 1,600 bytes. An isolated run of
unchanged HEAD `823aeb11` reproduced the same byte counts and allocation-size
maps. The new utility heap checks retain zero bytes; the compositor failures
remain separate follow-up work.

The unchanged Quick Look PNG-preview host test also crashes with exit 139
after its text-preview case passes; the same test and normal compiler flags
reproduce this on `823aeb11`. The remaining utility checks, native IPC checks
and AArch64 QEMU idle/apps/drag smoke scenarios pass.
