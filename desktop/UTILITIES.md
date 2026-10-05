# Desktop utility inventory and macOS feature gaps

Original audit: 2026-10-05. Storage and productivity follow-ups: 2026-10-06.
This document records the original inventory, implemented utility work,
and the remaining work.
It does not claim complete macOS parity.

The native utilities are Files, Activity Monitor, Settings, Text Editor,
Calculator, Calendar, Clock, Capture, Disk Usage, Terminal, Preview, Console,
System Information, Archive Utility, Disk Utility, Backup, Notes, Reminders
and Grapher. Both desktop image builders install their executable names as
clients of the multicall desktop. Files Settings, Quick Look, Quick Launch
and the notification area are supporting surfaces rather than additional
utility payloads.

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
| Preview / Preview | Quick Look inside Files; no standalone viewer | Standalone PNG/JPEG viewer with editable paths, fit/actual-size/zoom, panning, quarter-turn rotation, PNG export and original-file copying without overwriting | PDF rendering and page navigation; annotations, selections/cropping, EXIF orientation, colour profiles/adjustments, metadata, additional formats, printing and a file picker |
| Console / Console | Application logs existed as files; no native viewer | Read-only bounded log tails, application-log presets, literal row filtering, follow/paging, recent logs and matching-row export without overwriting | Central log collection/retention, severity/metadata filters, structured crash reports and kernel-log capture; desktop output currently goes to `/dev/console` |
| System Information / System Information | Small About pane in Settings | Native overview, hardware, storage and package reports from real system sources; refresh, paging and text export without overwriting | Broader device/driver APIs, searchable structured properties and remote reports; unavailable sources are labelled explicitly |
| Archive Utility / Archive Utility | Terminal archive tools only | Native TAR browsing, creation and extraction with bounded streaming work, progress/cancel, new destinations and rejection of traversal, links and special entries | ZIP/gzip and other compressed formats; file picker and Files associations; selective extraction; encryption and larger archives |
| Disk Utility / Disk Utility | Disk Usage rankings and System Information mount reports | Read-only block-device and mounted-volume inventory, selectable details, valid capacity, refresh/paging and exclusive report export | Physical device/partition hierarchy, health/SMART, disk images, mount/unmount privilege workflow; formatting, repair and partition changes need filesystem tools and explicit destructive-operation UI |
| Backup / Time Machine workflow | No native backup workflow | Versioned local folder copies, completed-version browsing, explicit restore to a new folder and bounded progress/cancel | Scheduled backups, retention/free-space policy, permission/timestamp preservation, incremental deduplication, encryption, network destinations and system/filesystem snapshots; links and special files are refused |
| Notes / Notes and Stickies | A static demo window, without a note store | Persistent bounded UTF-8 titles and plain-text bodies, title/body search, debounced autosave, explicit deletion and exclusive text export; damaged records and conflicting saves preserve existing data | Rich text, attachments, folders/tags, sync/sharing, import, printing, locked notes, undo/recovery and close confirmation after failed saves; floating sticky windows |
| Reminders / Reminders | No native task workflow | Persistent local tasks, optional local due dates/times, edit/complete/reopen, confirmed deletion, literal title search, all/open/completed/overdue filters and exclusive text/CSV export | Background alerts, recurrence, multiple lists, priorities/tags/subtasks, attachments, calendar integration and account sync/sharing |
| Grapher / Grapher | Calculator arithmetic only | Bounded explicit `y=f(x)` expressions, real-domain gaps, axes and finite editable ranges, zoom/reset and sampled CSV export using the existing native UI protocol | Multiple/implicit/parametric equations, 3D plots, saved graph documents, image/vector export, animations, integration/intersection tools and graph styling |

Relevant macOS references: [process browsing](https://support.apple.com/en-ie/guide/activity-monitor/actmntr1001/mac)
and [diagnostics](https://support.apple.com/guide/activity-monitor/run-system-diagnostics-actmntr2225/mac),
[TextEdit search/replace](https://support.apple.com/guide/textedit/find-and-replace-text-txtef6cfde1a/mac),
[Calculator modes](https://support.apple.com/guide/calculator/choose-the-right-mode-calc22d50970/mac),
[Calendar events](https://support.apple.com/en-gb/guide/calendar/icalwr13-events/mac)
and [calendar interchange](https://support.apple.com/guide/calendar/import-or-export-calendars-icl1023/27.0/mac/27),
[Clock](https://support.apple.com/en-mide/guide/clock-mac/welcome/mac),
[screenshot targets](https://support.apple.com/en-ie/102646),
[Preview documents and images](https://support.apple.com/en-ca/guide/preview/prvw846b61d3/mac),
[Console log messages](https://support.apple.com/guide/console/log-messages-cnsl1012/mac)
and [System Information reports](https://support.apple.com/guide/system-information/welcome/mac),
[archive compression/extraction](https://support.apple.com/en-lk/guide/mac-help/mchlp2528/mac),
[Disk Utility devices and volumes](https://support.apple.com/en-ca/guide/disk-utility/dskud6b39edb/mac)
and [Time Machine restore](https://support.apple.com/en-au/guide/mac-help/mh11422/mac),
[Notes import/export](https://support.apple.com/en-asia/guide/notes/not201900c07/mac),
[Reminders tasks and due dates](https://support.apple.com/en-ie/guide/reminders/remndc729e28/mac)
and [Grapher](https://support.apple.com/guide/grapher/welcome/mac).

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

These 21 entries plus the nineteen native utilities account for the complete
40-entry application catalog. Vim and shell tools installed in the userland
are terminal programs, not additional native desktop applications.

## Missing utility applications to implement

The macOS names below identify the comparison. The milestones are proposed
Vinix applications, with dependencies made explicit. Existing terminal tools,
Disk Usage, Quick Look or a browser do not supply the corresponding complete
desktop workflow. Fifteen utility applications remain below. Notes supplies
the local note-taking milestone; independent floating Stickies windows remain
a feature gap in that application.

| Priority | Utility / macOS comparison | First useful milestone | Dependencies or boundary |
| --- | --- | --- | --- |
| P2 | Font Book | Preview installed fonts, inspect metadata and install/remove per-user fonts | Runtime font discovery/rendering; the desktop currently relies on baked coverage atlases. |
| P2 | Digital Color Meter | Pick framebuffer colours, magnify the sample and copy RGB/hex values | Compositor sampling IPC and a guest clipboard copy service. |
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
- **Preview:** enter an image path and Open; choose Fit, 100%, zoom or Rotate.
  Export PNG saves the current rotation with alpha; Original Copy keeps the
  exact encoded input. Enter a new output path because neither overwrites.
  Successful opens appear in the app's Recent Items. PDF support remains work.
- **Console:** choose a log preset or enter an absolute regular-file path.
  Follow Tail refreshes once per second; paging suspends follow. The exact,
  case-sensitive filter and Export Rows apply to all retained rows, including
  those outside the viewport. Snapshots keep at most the last 128 KiB.
  Missing logs stay unavailable until their producer creates them.
- **System Information:** choose a report category and Refresh to collect
  current system data. Enter a new export path to save the report. Data comes
  from Vinix's procfs, CPU topology, GPU reports, mount capacity and package
  databases; absent facilities are reported as unavailable.
- **Archive Utility:** enter an uncompressed TAR path and Browse. Enter a new
  Extract folder and Extract, or enter a regular-file/folder Source and new
  Output TAR and Create TAR. Cancel removes an unfinished TAR output; an
  unfinished extraction keeps its partial files and reports that state. TAR
  snapshots are immutable after loading, bounded to 64 MiB and 2,048 entries.
  Traversal, links, special entries and conflicting names are refused. ZIP,
  gzip and extended TAR records remain unsupported.
- **Disk Utility:** select Devices or Volumes, click a row or use arrow/page
  keys to inspect it, and Refresh to read current metadata. Export report saves
  both inventories to a new path. Device sizes come from block-node metadata;
  capacity is reported only when filesystem counters are valid. Storage
  inspection reads metadata; formatting and mount changes remain future work.
- **Backup:** enter existing, separate Source folder and Backup folder paths,
  then Back Up. Choose Versions to list completed copies, select a version and
  enter a New restore folder before Restore. Each copy preserves the relative
  folder/file layout and contents; it does not preserve all POSIX metadata or
  provide an atomic filesystem snapshot. Links and special files are refused.
  Cancel/failure keeps a visibly incomplete folder, never a completed version.
  No existing restore destination is overwritten. Paths and every traversed
  component refuse symbolic links.
- **Notes:** choose New note, enter a title and write plain text. Search matches
  titles and bodies with case sensitivity. Ctrl-N creates a note; Ctrl-S saves;
  Ctrl-A selects the active field. Notes autosaves after a typing pause. A
  failed save keeps the draft in the open window and blocks note switching;
  export it before reopening after a conflict. Delete requires a second Delete
  action, with Keep note to cancel. Export text creates a new file. Closing
  tries one final save, but there is no recovery journal or close confirmation;
  if that save fails, closing discards the draft. Export an unsaved draft
  before closing.
  Storage is limited to 128 notes, 160-byte titles, 16 KiB bodies and a 1 MiB
  complete record. The user's home alias is resolved once and storage remains
  anchored to that directory; record and lock names refuse symbolic links.
- **Reminders:** choose New task, enter a title and optionally `YYYY-MM-DD` or
  `YYYY-MM-DD HH:MM`, then Save task. Select a task to Edit, Complete/reopen or
  confirm Delete. Search and filters apply to all retained tasks; export text
  or CSV writes the complete current view to a new path. Dates use local time;
  due-state display updates while the app is open. There are no background
  notification, recurrence or synchronization services in this milestone.
  Lists hold at most 256 tasks with 256-byte titles in a 128 KiB record. A
  conflicting save or damaged record preserves the previously saved file.
- **Grapher:** enter an explicit function of `x` and choose Plot. Arithmetic,
  powers, parentheses, `pi`/`e` and supported standard functions use radians.
  Edit finite x/y bounds or use Zoom/reset, then export samples to a new CSV.
  Domain failures leave gaps; sampling is bounded and does not prove a
  function is continuous between samples. Plots use the native child-process
  UI protocol and resize with the window.
  Expressions are limited to 256 bytes/operations, 32 parser levels and 16
  floor/ceil calls. Each plot uses 513 samples. Range magnitudes cannot exceed
  `1e12`, and each span must be at least `1e-9`.

The image builders install `vinix-preview`, `vinix-console` and
`vinix-system-information`, `vinix-archive`, `vinix-disk-utility` and
`vinix-backup`, `vinix-notes`, `vinix-reminders` and `vinix-grapher` as native
multicall clients. Existing guest images
need the new executable names installed as well as the updated desktop
binary before the new menu entries can launch them.

## Validation

`desktop/tools/test-utility-parity.sh` stages the actual desktop and ui2 model
and runs the new utility behavior tests together, using the production V
frontend with `-gc none -manualfree`. It is also called by
`desktop/tools/test-utilities.sh`, whose existing cases exercise native app IPC,
Files, UTF-8 editing/terminal rendering and the application catalog. Run
`desktop/tools/test-settings.sh` for preference/device and translation checks,
and `desktop/tools/test-activity.sh` for process controls and resource lifetimes.
`desktop/tools/test-new-utilities.sh` covers the nine new utility models,
catalog/search integration, translations/fonts, owned-memory cleanup and real
native-process IPC. It uses Clang for the image decoder and heap checks.
`tests/desktop-perf/run.py --scenarios=utilities` adds a guest startup/rendering
scenario for Preview, Console and System Information; `--scenarios=storage`
starts Archive Utility, Disk Utility and Backup; `--scenarios=productivity`
starts Notes, Reminders and Grapher.

Cross-build and guest smoke results are recorded in the change handoff. Local
calendar records, timer expiry, undo/replace, exports and terminal search have
behavioral coverage; host tests alone do not verify new driver/service features.

The original compositor `memory_test.v` baseline with this compiler/ui2 found
three failures: eight idle redraws retain 8,960 bytes, Start-menu redraws
retain 10,206 bytes, and 100 idle polls retain 1,600 bytes. An isolated run of
unchanged HEAD `823aeb11` reproduced the same byte counts and allocation-size
maps. The storage follow-up fixes the idle-poll interface wrappers, and the
unchanged original idle-poll case now retains zero bytes. Child-process poll
replies also leaked 16 bytes per ordinary poll and 132 bytes per paced poll;
explicit interface receivers and a bounded reply buffer reduce both to zero.
Five new dispatch cases check the real reply bytes and compositor damage for
100/200 iterations, including minimized and closed windows. The two redraw
baselines remain separate follow-up work.

The Quick Look PNG-preview host test crashes with exit 139 under the default
host C backend, both before and after these changes. With `-cc clang`, the
backend used by the production cross-build, all four Quick Look cases pass
on both `823aeb11` and the updated sources. The image-decoding host runners now
select Clang explicitly.

The three new utilities pass 107 combined behavior cases and nine tracked
memory cases, with zero retained owned bytes. Native-process IPC verifies image
rotation/export, filtered log export and full system-report export. The
committed AArch64 software desktop passes QEMU idle, existing-app and new-utility
startup/rendering scenarios; an additional run verifies individual utility
windows and actual window dragging. The utility scenario starts all three real
native clients. PDF rendering, central log collection and broader hardware
discovery remain the feature gaps listed above.

The storage follow-up passes 132 combined behavioral cases and 22 tracked
memory cases, with zero retained owned bytes. Real native-process IPC creates,
validates and extracts a TAR; backs up, lists and restores a folder; exports a
storage report through a shortened UTF-8 path; and verifies that a button starts
polling immediately after a long idle hint. Archive security cases cover
traversal, links, conflicting names, changed sources and byte/entry/depth bounds.
Its recursive creation fixture keeps descriptor counts flat. Backup fixtures
cover completion markers, cancellation, conflicts, unsupported files, source
changes, bounded versions and incomplete destinations. Image builders install
all three new executable names; the optional storage scenario requires the
compositor and all three native clients to be present.

The committed storage desktop (`0dc43400`) cross-builds for AArch64 with Clang
and passes QEMU `idle,apps,storage,drag` startup/rendering checks. Storage runs
the compositor and three native clients; screenshots verify each new window
and show the real `/dev/vda` block-device size. The drag control marker is
received and its screenshot confirms that the System window moved. These
five-second guest samples are smoke checks; the copy/extract/restore behavior
and owned-memory assertions above are host checks, not long-running guest
performance measurements.

The productivity follow-up passes 163 combined behavioral cases and 33 tracked
memory cases, with zero retained owned bytes. Real native-process IPC exercises
Notes autosave, UTF-8 text export and reopening; Reminders completion, CSV
export and reopening; and Grapher domain gaps, samples and overwrite refusal.
The child processes use an isolated active-user home forwarded by the
compositor. Focused Notes resize checks cover widened and taller viewports,
visible text/caret and a shallow window's minimum text row. Model tests cover
malformed records, conflicting writers, anchored file paths, home aliases,
task date validation and graph discontinuities. The runner's 22 Python cases
and all modified shell-script syntax checks also pass.
