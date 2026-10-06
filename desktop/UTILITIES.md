# Desktop utility inventory and macOS feature gaps

Original audit: 2026-10-05. Storage, productivity, tools and document workflow
follow-ups: 2026-10-06.
This document records the original inventory, implemented utility work,
and the remaining work.
It does not claim complete macOS parity.

The native utilities are Files, Activity Monitor, Settings, Text Editor,
Calculator, Calendar, Clock, Capture, Disk Usage, Terminal, Preview, Console,
System Information, Archive Utility, Disk Utility, Backup, Notes, Reminders,
Grapher, Color Meter and Dictionary. Both desktop image builders install their
executable names as clients of the multicall desktop. Files Settings, Quick Look,
Quick Launch and the notification area are supporting surfaces rather than
additional utility payloads.

The macOS comparison uses Apple's [included-app inventory](https://support.apple.com/en-gb/guide/mac-help/mchl110b00b7/26/mac/26)
and the individual guides linked below. Priorities and implementation plans are
Vinix engineering proposals based on the inspected code.

## Existing applications

| Vinix utility / macOS counterpart | Present before this change | Implemented in this change | Remaining gaps |
| --- | --- | --- | --- |
| Files / Finder | List, Finder and Miller-column views, dual-pane mode, sorting, current-folder search, navigation history, sidebar, tags, Quick Look, rename/copy/cut/paste/permanent delete and view preferences | Get Info for the selected file, including POSIX metadata and symbolic-link targets; persistent personal Trash with move, browse, restore without overwriting and confirmed emptying | Trash for other volumes/outside Home and recursive emptying of nonempty folders; restoration of file tags; multiple selection and batch operations; file-operation undo; tabs; recursive/content/metadata search; file associations and Open With; drag-and-drop file operations; permission editing; shared folders |
| Activity Monitor / Activity Monitor | Process search, application/owner/activity filters, process trees, selectable sortable columns, inspector, terminate/force-quit/suspend/resume/priority controls; CPU/per-core, memory, disk, network, GPU submission and battery histories; refresh control, process diagnostic reports and startup apps | Inactive, other-user and selected-process filters; CSV export of the visible process list; clear resource/GPU/power graph history without discarding counter baselines; startup toggles and launch timings cover the complete application catalog; per-user saved sort/direction, filter, tree, columns, refresh interval, main view and resource tab | Per-process network, energy, GPU and wakeup accounting; actual process stack sampling and hang/crash reports; CPU history in taskbar; compressed-memory/swap accounting if those facilities are introduced |
| Settings / System Settings | Appearance, date/time display preferences, language, theme, wallpaper, Wi-Fi radio/scan/status, backlight/display scaling, battery history and keyboard layouts | About pane reading the actual kernel version, reported CPU/architecture, physical memory and uptime, with Refresh and unavailable-data states; localized search across 27 options with keyboard navigation into their actual panes | Clock/timezone setters; user management; accessibility; audio devices/volume; Bluetooth; printers; IP/DNS/proxy configuration; GUI package/update management; sleep/power policies |
| Text Editor / TextEdit | Plain-text UTF-8 open/edit/save, cursor navigation and paste; byte-preserving handling of invalid UTF-8 | Bounded undo/redo; exact Find with next/previous and wrapping; highlighted matches; Replace and Replace All, with size checks and undo; unsaved-change guards for close/New/Open, failed-Open draft preservation and exclusive Save As; UTF-8 document selection, mouse caret/drag selection, bounded guest clipboard copy and acknowledged cut, and selection replacement with undo | Field selection, file picker, autosave/recovery/versions, wrapping, rich text, spelling, printing and larger documents |
| Calculator / Calculator | Pointer-operated basic decimal arithmetic, percent, sign and powers | Keyboard arithmetic and backspace, validated numeric/scientific-notation paste, memory register, relative percentages, bounded result history with paging and recall; Basic/Scientific selection, DEG/RAD, square root/reciprocal/square/cube/cube root, trig/inverse trig, ln/log10/log2/exp and pi/e, with domain/finite errors and scientific operation history; exact unsigned 64-bit Programmer mode with DEC/HEX/OCT/BIN entry/readouts, modular arithmetic, bitwise operations, logical shifts, independent history and preserved Basic/Scientific memory; acknowledged guest clipboard result copy in every mode | Further scientific controls (nth-root, hyperbolic/inverse-hyperbolic, random and EE entry); signed or variable-width programmer arithmetic, a bit editor, RPN, expression parsing, unit/currency conversion, Math Notes integration, result selection, configurable precision/grouping and history persistence |
| Calendar / Calendar | Month navigation, selected dates, localized weeks and Today | Persistent local all-day/timed events with titles and locations; creation/editing/deletion; marked dates and selected-date agenda; strict ICS import/additive merge and exclusive export for one-day all-day or floating local minute-precision events | Broader ICS semantics (timezones, recurrence, durations, alarms, extra fields), stable imported identities, duration/multiday events, day/week/year views, recurrence, search, reminders/notifications, multiple calendars, CalDAV/accounts and invitations |
| Clock / Clock | Local time and a monotonic stopwatch with pause/resume/reset | Bounded lap/split/total records; countdown timer, duration presets/adjustment, pause/resume/reset and visible expiry | World clocks and timezone database; scheduled/repeating alarms; multiple named timers; sound/notifications; persistence and a service that continues after the app closes |
| Capture / Screenshot and screen recording | Full-desktop PNG, delay, self-hiding, 5/10 fps AVI recording, stop/cancel and status | Recording-delay controls on the Video page; Enter to start and Escape to stop/cancel | Window/region selection, output-location chooser, clipboard capture, cursor toggle, capture hotkeys, thumbnail/reveal workflow, audio and compressed video |
| Disk Usage / Storage settings | Resumable size inventory, largest-folder/file rankings, hard-link deduplication, symlink avoidance, drill-down, parent navigation, stop and rescan | Editable scan root and report destination, keyboard input, raw-byte CSV report with proper text escaping and overwrite protection | Capacity/free-space/mount overview, allocated versus logical size, storage categories, treemap, reveal in Files and guarded cleanup; disk management belongs in a separate utility |
| Terminal / Terminal | Real PTY/Zsh, VT cursor/alternate-screen support, UTF-8 cells, bounded scrollback, paste and rebuild handoff | Find in scrollback/live screen with next/previous and wrap, match-row highlighting, and clear scrollback preserving live/alternate-screen contents; UTF-8 mouse selection across physical output rows, acknowledged guest clipboard Copy/Cmd-C and preserved Ctrl-C shell input | Word/line/rectangular selection, wide and combining character cell widths, logical-line reflow, tabs/split panes, profiles/fonts/colours, configurable history, complete ANSI colours/attributes, hyperlinks and command bookmarks |
| Preview / Preview | Quick Look inside Files; no standalone viewer | Standalone PNG/JPEG viewer with editable paths, fit/actual-size/zoom, panning, quarter-turn rotation, all eight JPEG EXIF orientations composed with manual rotations, rectangular selection/cropping with alpha-preserving PNG export, and exact original-file copying without overwriting | Crop undo/recovery and image resampling; PDF rendering and page navigation; annotations, additional selection tools, colour profiles/adjustments, broader metadata inspection, additional formats, printing and a file picker |
| Console / Console | Application logs existed as files; no native viewer | Read-only bounded log tails, application-log presets, literal row filtering, follow/paging, recent logs and matching-row export without overwriting | Central log collection/retention, severity/metadata filters, structured crash reports and kernel-log capture; desktop output currently goes to `/dev/console` |
| System Information / System Information | Small About pane in Settings | Native overview, hardware, storage and package reports from real system sources; bounded UTF-8 search across row values, translated labels and categories with token/case/accent matching; refresh, paging and complete text export without overwriting | Broader device/driver APIs, structured property inspection and remote reports; unavailable sources are labelled explicitly |
| Archive Utility / Archive Utility | Terminal archive tools only | Native TAR browsing, creation and whole/selected extraction with entry/folder checkboxes, choices fixed during extraction, bounded streaming work, progress/cancel, new destinations and rejection of traversal, links and special entries | ZIP/gzip and other compressed formats; file picker and Files associations; encryption and larger archives |
| Disk Utility / Disk Utility | Disk Usage rankings and System Information mount reports | Read-only block-device and mounted-volume inventory, selectable details, valid capacity, refresh/paging and exclusive report export | Physical device/partition hierarchy, health/SMART, disk images, mount/unmount privilege workflow; formatting, repair and partition changes need filesystem tools and explicit destructive-operation UI |
| Backup / Time Machine workflow | No native backup workflow | Versioned local folder copies, completed-version browsing, explicit restore to a new folder and bounded progress/cancel | Scheduled backups, retention/free-space policy, permission/timestamp preservation, incremental deduplication, encryption, network destinations and system/filesystem snapshots; links and special files are refused |
| Notes / Notes and Stickies | A static demo window, without a note store | Persistent bounded UTF-8 titles and plain-text bodies, title/body search, debounced autosave, explicit deletion and exclusive text export; damaged records and conflicting saves preserve existing data; failed final saves block ordinary window/session closing, with keep-editing and confirmed-discard choices | Rich text, attachments, folders/tags, sync/sharing, import, printing, locked notes and undo/recovery; floating sticky windows |
| Reminders / Reminders | No native task workflow | Persistent local tasks, optional local due dates/times, edit/complete/reopen, confirmed deletion, literal title search, all/open/completed/overdue filters and exclusive text/CSV export | Background alerts, recurrence, multiple lists, priorities/tags/subtasks, attachments, calendar integration and account sync/sharing |
| Grapher / Grapher | Calculator arithmetic only | Bounded explicit `y=f(x)` expressions, real-domain gaps, axes and finite editable ranges, zoom/reset, versioned `.vgraph` documents with validated Open and exclusive Save As, and separate sampled CSV export using the existing native UI protocol | Autosave/recovery and file picker; multiple/implicit/parametric equations, 3D plots, PNG/vector export, animations, integration/intersection tools and graph styling |
| Color Meter / Digital Color Meter | No native screen-colour workflow | Compositor sampling in physical pixel coordinates, pointer tracking and freeze, a 9×9 magnifier, 1×1/3×3/5×5/9×9 aperture averages, hex/RGB display and text copy to the guest session clipboard | ICC/display colour profiles and colour-space conversion, extended-range values, independent horizontal/vertical locking, image copy and host clipboard writing |
| Dictionary / Dictionary | No offline lexical utility | Native offline WordNet 3.0 lookup with 147,306 headwords, ASCII case folding and phrase/prefix suggestions, bounded Back/Forward history, UTF-8 definition wrapping/paging, exclusive text export and acknowledged guest clipboard copy of the full headword and unwrapped definition | Pronunciation/audio, morphology, full Unicode case folding, multiple/language sources, encyclopedic articles, definition selection, lookup from selected text and persistent history |

Relevant macOS references: [process browsing](https://support.apple.com/en-ie/guide/activity-monitor/actmntr1001/mac)
and [diagnostics](https://support.apple.com/guide/activity-monitor/run-system-diagnostics-actmntr2225/mac),
[Settings search](https://support.apple.com/en-ie/guide/mac-help/mchl8d10839d/mac),
[copy/cut/paste](https://support.apple.com/en-us/102553),
[TextEdit search/replace](https://support.apple.com/guide/textedit/find-and-replace-text-txtef6cfde1a/mac),
[Calculator modes](https://support.apple.com/guide/calculator/choose-the-right-mode-calc22d50970/mac)
and [scientific controls](https://support.apple.com/guide/calculator/use-the-scientific-calculator-calcf964141e/mac),
[Calendar events](https://support.apple.com/en-gb/guide/calendar/icalwr13-events/mac)
and [calendar interchange](https://support.apple.com/guide/calendar/import-or-export-calendars-icl1023/27.0/mac/27),
[Clock](https://support.apple.com/en-mide/guide/clock-mac/welcome/mac),
[Terminal shortcuts](https://support.apple.com/en-bh/guide/terminal/trmlshtcts/mac),
[screenshot targets](https://support.apple.com/en-ie/102646),
[Preview documents and images](https://support.apple.com/en-ca/guide/preview/prvw846b61d3/mac),
[Preview image cropping](https://support.apple.com/guide/preview/crop-resize-or-rotate-an-image-prvw2015/mac),
[CIPA EXIF layout and orientation](https://www.cipa.jp/std/documents/e/DC-X008-Translation-2019-E.pdf),
[Console log messages](https://support.apple.com/guide/console/log-messages-cnsl1012/mac)
and [System Information reports](https://support.apple.com/guide/system-information/welcome/mac),
[archive compression/extraction](https://support.apple.com/en-lk/guide/mac-help/mchlp2528/mac),
[Disk Utility devices and volumes](https://support.apple.com/en-ca/guide/disk-utility/dskud6b39edb/mac)
and [Time Machine restore](https://support.apple.com/en-au/guide/mac-help/mh11422/mac),
[Notes import/export](https://support.apple.com/en-asia/guide/notes/not201900c07/mac),
[Reminders tasks and due dates](https://support.apple.com/en-ie/guide/reminders/remndc729e28/mac),
[Grapher graphs and equations](https://support.apple.com/guide/grapher/create-a-graph-and-add-equations-gcalcd405d09/mac),
[Digital Color Meter](https://support.apple.com/en-ca/guide/digital-color-meter/welcome/mac)
and [Dictionary](https://support.apple.com/en-hk/guide/dictionary/welcome/mac).

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

These 21 entries plus the twenty-one native utilities account for the complete
42-entry application catalog. Vim and shell tools installed in the userland
are terminal programs, not additional native desktop applications.

The Start menu's All Programs and search results use readable 34-pixel rows
with Previous/Next page controls and PageUp/PageDown navigation. Search covers
all catalog entries; Enter launches the first result on the visible page.

## Missing utility applications to implement

The macOS names below identify the comparison. The milestones are proposed
Vinix applications, with dependencies made explicit. Existing terminal tools,
Disk Usage, Quick Look or a browser do not supply the corresponding complete
desktop workflow. Thirteen utility applications remain below. Notes supplies
the local note-taking milestone; independent floating Stickies windows remain
a feature gap in that application.

| Priority | Utility / macOS comparison | First useful milestone | Dependencies or boundary |
| --- | --- | --- | --- |
| P2 | Font Book | Preview installed fonts, inspect metadata and install/remove per-user fonts | Runtime font discovery/rendering; the desktop currently relies on baked coverage atlases. |
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

AirPort/base-station management, Apple account services, FaceTime, Find My and
Boot Camp depend on vendor services or platform-specific hardware; they are
not proposed as general Vinix utility ports.

## Using the implemented workflows

- **Files:** select an entry, use Get Info or Ctrl-G, and close with Escape.
  Delete in Files or on the desktop now moves ordinary Home items to personal
  Trash. Open Trash from the Files footer, select a row and Restore Selected
  to its original location; an existing destination is preserved. Empty Trash
  requires a second confirmation and removes only files, leaf links and empty
  folders. A nonempty folder or damaged record blocks the whole preflight;
  restore nonempty folders to manage their contents. Items outside Home,
  protected app records, symlink parents and cross-filesystem moves are refused.
  This milestone has 256 rows and uses atomic moves rather than copy/delete.
- **Activity Monitor:** the filter control cycles the process groups. Export
  (Ctrl-E) writes `Activity-Monitor-Processes.csv` in the user's home. In tree
  mode it includes visible context ancestors. Clear History (Ctrl-L) resets
  resource/GPU/power graphs while retaining rate baselines; battery charge
  history remains the shared battery service's history. View choices are saved
  in the active user's `.vinix-activity-settings`, with private atomic writes.
  Search, pause, selection and scroll remain transient; the selected-process
  filter reopens as All to avoid reused PIDs. Damaged records and conflicting
  saves preserve existing data and show a warning.
- **Editor:** Ctrl-Z/Ctrl-Y undo/redo; Ctrl-F opens Find; Ctrl-G finds the next
  match. Find is an exact UTF-8 byte search at character boundaries. Replace
  All is one undoable action. History is bounded and not a recovery journal.
  Close, New and Open protect dirty documents with Save, Keep editing and
  two-step Discard choices. Save As creates a new file and refuses existing
  paths, including leaf symlinks. A failed Open preserves the draft and the
  original Save destination. Forced termination bypasses the close guard;
  autosave/recovery and file pickers remain future work. Drag text to select,
  Ctrl-A selects the document, and Ctrl-B toggles marking with ordinary arrows
  on the guest keyboard. Ctrl-C copies and Ctrl-X cuts after the compositor
  acknowledges the copy; Ctrl-V pastes into and replaces a selection. Selection
  respects UTF-8 boundaries and raw document bytes; copy is bounded to 64 KiB.
  Copies stay in the guest session clipboard. An older compositor without this
  capability reports unavailable and preserves text. Field selection is future
  work. Mouse scrolling no longer forces the view back to the caret.
- **Calendar:** select a date, choose New event, enter a title and optionally
  a time/location, then Save. Select an agenda event to edit/delete it. Events
  are local to the user's home and do not sync or issue alerts. Import / Export
  opens the ICS path fields. Import validates the whole file before additive
  merge; identical date/time/title/location events are skipped. Accepted events
  are one-day all-day dates or floating local times at minute precision, with
  title and optional location. Unsupported timezone, recurrence, alarm, duration
  or extra-field semantics are refused, preserving the saved calendar. UID and
  UTC DTSTAMP are validated but not retained; exports generate fresh identities
  and timestamps and never replace an existing file. See the onscreen scope.
- **Clock:** record laps while the stopwatch runs; use the Timer tab for a
  countdown. Expiry is visible in this app; there is no background alarm.
- **Calculator:** use digits/operators/Enter and Backspace, memory buttons,
  or click a recent result to recall it. Select Scientific for unary functions
  including cube, cube root and log2, and pi/e; choose DEG or RAD for trig and
  inverse trig. Ctrl-S switches modes and Ctrl-D switches angle units in
  Scientific mode. Functions transform the displayed operand, including the
  right operand of a pending calculation.
  A new digit replaces a scientific result; repeated equals repeats the last
  binary operation. Domain errors and non-finite results are shown explicitly.
  Scientific mode accepts a finite number pasted in exponent notation.
  History is bounded to 20 results and includes function arguments/angle units.
  Select Programmer (Ctrl-P) for exact unsigned 64-bit values. Ctrl-B changes
  the input base; prefixed numeric paste accepts `0x`, `0o` and `0b`. Full-sized
  windows display all four bases together; compact windows show the selected
  base. The bitwise keyboard controls are `&`, `|`, `^` and `~`. Addition,
  subtraction and multiplication wrap modulo 2^64; shifts are logical with
  counts 0–63. Overflowing input and division by zero preserve the value and
  report an error. Programmer history is separate; Basic/Scientific state and
  memory are preserved while switching modes. Signed arithmetic and variable
  bit widths remain work. Copy result or Ctrl-C snapshots the displayed number
  in Basic/Scientific, or the exact selected-base digits in Programmer.
  Copy is limited to 64 KiB and shows success only after the compositor
  acknowledges it; unavailable, invalid or failed copies preserve the guest
  clipboard. It does not write the host clipboard.
- **Terminal:** click Find, type an exact query, use the arrows or Enter to
  advance, and Escape to return keyboard input to the shell. Matches are
  physical output rows, including scrollback; Clear scrollback keeps the
  current terminal screen. Drag over output to select UTF-8 cells, then choose
  Copy or Cmd-C. Selection covers physical rows, including the alternate
  screen; copied rows are separated by newlines rather than joined into
  logical wrapped lines. Copies are bounded to 64 KiB and acknowledged by the
  guest clipboard service; oversized copies are refused without truncation.
  When keyboard input is directed to the shell, Ctrl-C reaches the PTY for
  the shell/program to handle as an interrupt.
  Output changes and resizing clear selection so stale cells are not copied.
- **Disk Usage:** edit Folder and Scan; edit Report and Export CSV. Existing
  report files are preserved. Export a completed or cancelled scan; cancelled
  scans are explicitly marked partial by their phase. Reports contain the
  retained rankings rather than every file.
- **Capture:** Video now exposes the recording delay. Enter starts the chosen
  operation and Escape stops/cancels it.
- **Settings:** choose About and Refresh to read system-reported information.
  Missing data is labelled unavailable. Click Search or Ctrl-F, enter localized
  category/control words, and use arrows, page keys and Enter to open a matching
  pane. Words match together with case/accent folding; language names and scale
  percentages are included. Escape clears/dismisses search. Search operates on
  the implemented controls rather than external or unavailable settings.
- **Preview:** enter an image path and Open; choose Fit, 100%, zoom or Rotate.
  JPEG EXIF orientation applies automatically, including all mirrored forms.
  Fit, pan and manual rotations use the oriented image. Choose Select (S), drag
  a rectangle over the displayed image and choose Crop or Enter to keep it.
  Selection follows the displayed orientation, zoom and pan. Pan (P) restores
  drag-to-pan; Clear or Escape removes the selection, and Ctrl-A selects the
  whole image. Crop changes the in-memory pixels and preserves alpha; Export
  PNG writes the current crop and rotation. The source file is preserved.
  Bounded metadata parsing supports both TIFF byte orders and ignores
  malformed/unsupported orientation records. Original Copy
  keeps the exact cached encoded input, including its metadata, even after
  cropping, manual rotations or a later source-file change. Enter a new output
  path because neither export overwrites. Successful opens appear in the app's
  Recent Items. Crop undo/recovery, resampling and PDF support remain work.
- **Console:** choose a log preset or enter an absolute regular-file path.
  Follow Tail refreshes once per second; paging suspends follow. The exact,
  case-sensitive filter and Export Rows apply to all retained rows, including
  those outside the viewport. Snapshots keep at most the last 128 KiB.
  Missing logs stay unavailable until their producer creates them.
- **System Information:** choose a report category and Refresh to collect
  current system data. Click Search or Ctrl-F and enter a bounded UTF-8 query.
  Space-separated words match across row values, translated labels and category
  names with case/accent folding; matching rows retain paging. Escape clears
  and dismisses search. Refresh reapplies the query to current data, and
  changing language updates translated matches. Enter a new export path to
  save the complete report across all categories. Data comes
  from Vinix's procfs, CPU topology, GPU reports, mount capacity and package
  databases; absent facilities are reported as unavailable. Broader device and
  driver inventory still needs real backend sources.
- **Archive Utility:** enter an uncompressed TAR path and Browse. Enter a new
  Extract folder and Extract for the whole archive, or toggle entry checkboxes
  and choose Extract selected. A folder checkbox also selects its descendants;
  Select all and Clear operate across pages. Choices are fixed once extraction
  starts. With no selected entries, Extract selected creates no destination.
  To create an archive, enter a regular-file/folder Source and new Output TAR
  and Create TAR. Cancel removes an unfinished TAR output; an
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
  action, with Keep note to cancel. Export text creates a new file. An ordinary
  window close or desktop exit tries one final save; a failed save keeps Notes
  open with its draft. Keep editing cancels the close request. Save again or
  export the draft; to discard it, choose Discard draft, then Confirm discard,
  and retry closing. Forced process termination bypasses this guard, and there
  is no recovery journal.
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
  The graph-document path is a separate field, initially `graph.vgraph` in the
  canonical home directory. Enter a new absolute path and Save As to store the
  current expression and four range fields in a versioned record. Existing
  paths are refused; choose a new name for each saved revision. Open or Enter
  in the document-path field validates the whole record and all five fields
  before replacing and plotting the graph. Missing, truncated, malformed or
  oversized records, invalid expression syntax and invalid ranges preserve
  the current fields and plot. Typed paths refuse symbolic links in every
  component. Documents are bounded to 1 KiB; this is a Vinix format, and graph
  edits are not autosaved. Save changes before opening another document.
  Domain failures leave gaps; sampling is bounded and does not prove a
  function is continuous between samples. Plots use the native child-process
  UI protocol and resize with the window.
  Expressions are limited to 256 bytes/operations, 32 parser levels and 16
  floor/ceil calls. Each plot uses 513 samples. Range magnitudes cannot exceed
  `1e12`, and each span must be at least `1e-9`.
- **Color Meter:** choose Live to follow the pointer at 100 ms intervals, or
  enter physical framebuffer X/Y coordinates and Sample (Enter). Freeze,
  Space or Escape holds the current sample. The 9×9 magnifier marks the chosen
  1×1, 3×3, 5×5 or 9×9 aperture; RGB channels average the valid pixels in that
  aperture. The sampled pixels exclude the compositor's drawn cursor using
  its saved backing pixels. Copy HEX (Ctrl-C) or Copy RGB freezes the sample
  and copies text within the current guest session. Ctrl-V, Cmd-V or
  Shift-Insert pastes this guest text into a supported focused field; use
  Ctrl-Shift-V to request the host clipboard instead. The default window is
  620×540, with full controls at a content size of at least 584×506. Samples
  are displayed pixel values; colour-space/ICC conversion, image copy and
  host clipboard writing remain unavailable.

- **Dictionary:** enter an English word or phrase and Look up (Enter). The
  left column lists prefix matches; arrows/Previous/Next navigate the visible
  matches, and Back/Forward follows at most 32 successful lookups. PageUp and
  PageDown keys page prefix matches; the Page up and Page down buttons scroll
  a wrapped definition. Export definition writes the current headword
  and text to a new path. Copy definition or Ctrl-C copies the full headword,
  a blank line and the complete unwrapped definition, independent of paging.
  This acknowledged guest clipboard copy is limited to 64 KiB; an oversized
  entry is refused as a whole and preserves the previous clipboard. Success,
  failure and unavailable-service states are visible. Data is installed offline
  with the complete WordNet license; only its index, headwords and the current
  definition stay in memory.
  Failed loads or changed/malformed sources preserve the last successful lookup.
  Custom files must use the bounded VNXDICT1 format documented in
  [the Dictionary data guide](../build-support/dictionary/README.md).

The image builders install `vinix-preview`, `vinix-console` and
`vinix-system-information`, `vinix-archive`, `vinix-disk-utility` and
`vinix-backup`, `vinix-notes`, `vinix-reminders`, `vinix-grapher`,
`vinix-color-meter` and `vinix-dictionary` as native multicall clients.
Dictionary also needs `/usr/share/vinix/dictionary/dictionary.vnd` and the
neighboring `LICENSE.WordNet`; both image builders install them from a pinned,
verified host archive. Existing guest images need the new executable names
installed as well as the updated desktop binary before the new menu entries
can launch them.

## Validation

`desktop/tools/test-utility-parity.sh` stages the actual desktop and ui2 model
and runs the new utility behavior tests together, using the production V
frontend with `-gc none -manualfree`. It is also called by
`desktop/tools/test-utilities.sh`, whose existing cases exercise native app IPC,
Files, UTF-8 editing/terminal rendering and the application catalog. Run
`desktop/tools/test-settings.sh` for preference/device and translation checks,
and `desktop/tools/test-activity.sh` for process controls and resource lifetimes.
`desktop/tools/test-new-utilities.sh` covers the eleven new utility models and
document workflows, catalog/search integration, translations/fonts, owned-memory
cleanup and real native-process IPC. It uses Clang for the image decoder and heap
checks.
`tests/desktop-perf/run.py --scenarios=utilities` adds a guest startup/rendering
scenario for Preview, Console and System Information; `--scenarios=storage`
starts Archive Utility, Disk Utility and Backup; `--scenarios=productivity`
starts Notes, Reminders and Grapher; `--scenarios=tools` starts Color Meter,
Calculator and Notes; `--scenarios=workflows` starts Dictionary, Text Editor,
Calendar and Files and overlays explicitly supplied local Dictionary data.
Each utility scenario requires the compositor and every requested native
client, and installs its multicall aliases in older guest images.

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

The startup catalog fix passes 53 Activity Monitor behavior cases and seven
tracked-memory cases. Every installed application can be parsed, timed,
toggled, saved, reloaded and rendered in Startup Apps, including the last
catalog entry. Repeated full-catalog timing refresh, bottom-row rendering and
model cleanup retain zero owned bytes. Fixed buffers reserve 64 entries, and
a catalog-capacity regression guards future expansion.

The committed productivity desktop (`67583889`) cross-builds as a static
AArch64 ELF with Clang and passes QEMU `idle,apps,productivity,drag` checks.
Productivity runs exactly four processes: the compositor and all three native
clients. A separate screenshot run brings each utility to the front and
verifies readable controls, Grapher's plotted curve and personal export paths
for the registered guest user. The drag marker and screenshot confirm actual
System-window movement. These five-second guest samples check startup and
rendering; persistence/export correctness and owned-memory cleanup are the
host assertions described above, not long-running guest performance results.

### Tools follow-up validation (2026-10-06)

The utility runner passes 195 behavior cases, 51 tracked-memory cases and the
real multicall IPC fixture under V3/Clang with `-gc none -manualfree`.
All measured repeated paths retain zero owned bytes after persistent frame
capacities are warmed. Coverage includes physical/HiDPI screen samples,
cursor backing, edge aperture averages, request/report validation, session
clipboard copy/paste, every held shortcut fragment boundary, scientific
functions and errors, Notes failed-save close/session refusal, confirmed
discard, and all 41 application entries through readable Start-menu pages.
The final held-coordinate correction passes 8 focused Color Meter behavior
cases and 3 tracked-memory cases; live IPC also passes on that final source.

The shared message readers, service-request interface wrapper, window
reordering, fragmented clipboard parser and native keyboard dispatch were
measured and traced through generated C before their ownership fixes were
reviewed. Repeated requests, declining close/session checks, complete app
init/resize/close cycles, and paste fragments now retain zero owned bytes.
The latest 41-entry catalog also passes 53 Activity Monitor behavior cases and
seven tracked-memory cases. Host clipboard/UTF-8 checks and all 22 Python
runner cases pass.

The final tools desktop (`d5145c46`) cross-builds as a static AArch64 ELF with
Clang and passes QEMU `idle,apps,tools,drag` checks. Tools runs exactly four
processes: the compositor, Color Meter, Calculator and Notes. Screenshots
verify live framebuffer colour sampling, readable scientific controls and
the Notes window; the drag screenshot confirms System-window movement.
These five-second guest samples check startup and rendering. Persistence,
clipboard behaviour and owned-memory cleanup are covered by the host and
native-process IPC assertions above, rather than long-running guest samples.

The document workflow follow-up passes 234 combined behavior cases and 68
tracked-memory cases across 20 modules, with zero retained owned bytes. The
prepared full WordNet corpus is exercised in the behavior suite; its host data
encoder also passes five Python cases. The separate utility-parity suite passes
60 behavior and six memory cases. Activity Monitor passes 53 behavior and seven
memory cases, including startup toggles, reload/render and memory ownership for
the last app in the complete 42-entry catalog. The Linux-only separate-device
Trash fixture is skipped on the macOS host; cross-filesystem moves remain an
explicitly refused operation.

Real native-process IPC verifies Dictionary lookup/history/export and malformed
source preservation; supported Calendar ICS import, exclusive export, rejected
recurrence preserving both the live model and saved record, and reopened event
semantics; editor window/session close refusal, Save As collision/retry and
failed Open preserving the original Save destination; and Trash restore
conflicts, confirmation/cancel, emptying and reopening. The host runners derive
the software presenter's header and object from committed V sources using
`stage_host_gpu.py`, so the headless tests also work after the presenter port.
Clipboard/UTF-8 checks and all 29 Python performance-runner cases pass.

The feature desktop (`995badf8`) cross-builds as a static AArch64 ELF and passes
QEMU `idle,apps,workflows,drag` checks. Workflows measures exactly five native
processes: the compositor, Dictionary, Text Editor, Calendar and Files. The
prepared 147,306-headword corpus and unchanged license are overlaid into the
cached guest image without guest network access. Additional screenshots verify
the actual computer definition, individual windows, Save As, Calendar
interchange and the Trash pane. These five-second guest samples verify startup
and rendering; operation, persistence and repeated-use ownership are checked by
the host and real-process assertions above.

Calendar's final interchange explanations wrap into borrowed UTF-8 rows because
the desktop label renderer draws only one line. Fourteen focused behavior cases
and six tracked-memory cases pass, including every word in all three languages
at supported window widths and repeated rendering with zero retained bytes.
The final static AArch64 desktop (`5115a9e7`, including Calendar `189407bd`) is
published for Files, Activity Monitor and Settings. Its QEMU workflows rerun
passes with five native processes; final screenshots confirm the loaded corpus,
Save As and Trash panes, and the complete wrapped Calendar explanations.

### Search, selection and saved-view follow-up (2026-10-06)

Activity Monitor now retains eight view choices in the active user's private
settings record. Parsing, atomic replacement, competing windows, unsafe paths,
short writes, bounded reads and repeated opening/closing are covered by 63
behavior and 11 memory checks. Transient search, pause and PID selection are
not saved. Calculator's Programmer mode uses unsigned 64-bit integers directly,
with exact four-base readouts, modular arithmetic, logical shifts, invalid-input
and domain handling, independent history and preserved Basic/Scientific
state. Its 18 behavior and six memory checks cover values beyond floating-point
precision, maximum integers, overflow and repeated rendering/cleanup.

Text Editor now supports character-boundary document selection, mouse caret and
dragging, select-all and keyboard marking, selection replacement, and guest
clipboard copy/cut. Cut requires a successful matching acknowledgement and an
unchanged document revision/range; failed or stale requests preserve text.
Copied controls remain literal document data, while Start-menu paste treats them
as search text rather than navigation or launch commands. Fragmented CSI/SS3
navigation is bounded and a bare Escape is resolved after 100 milliseconds.
The focused Editor checks pass 44 behavior cases and nine memory cases.

The combined utility suite passes 254 behavior cases and 76 memory cases across
21 modules, including the prepared WordNet corpus. The parity suite passes 80
behavior and 14 memory cases. Settings passes 166 behavior/localization cases,
nine general-memory checks and three search-memory checks. These checks include
all indexed localized options, real-pane navigation, fragmented keyboard/paste
input, visible placeholder/focus states, complete translation keys and supported
font glyphs. All measured repeated paths retain zero owned bytes after warming
persistent frame capacities.

The broader redraw checks exposed allocations in named window-chrome element
appends, native interface dispatch wrappers and Files' repeated row-path builder.
Generated C and tracked allocations identified the sites. Field transfer,
explicit wrapper ownership and the existing path semantics under a distinct
helper name reduce the four-window fixture from 1,120 retained bytes per redraw
to zero. The regression now checks every visible-window count, both themes,
post-frame hit identities and repeated Start-menu redraws. An additional 27
Files/compositor behavior cases pass, and each new lifetime was reviewed.

The complete real-process IPC fixture passes on the host, including the new
Programmer, Editor selection/clipboard/pointer and Settings search workflows.
Activity's host branch skips when `/dev/processes` is absent. A focused static
AArch64 entry built from `18d82f0b` runs the same four feature-check functions
unchanged inside Vinix and requires that real device; Activity's saved record
and reopened selected view pass there. The guest entry excludes the host
fixture's unrelated zero-deadline pipe
readiness expectation. Clipboard/UTF-8 checks and all 29 Python performance
runner cases also pass.

The final static AArch64 desktop (`bea41f8e`, including the Settings placeholder
fix `836de41c` and compositor ownership fix `12ab25a7`) is published for Files,
Activity Monitor and Settings. A fresh QEMU boot passes idle, apps, utility-view
and window-drag scenarios with five-second samples. The utility-view scenario
runs the compositor and all four real native app processes. Keyboard/pointer
screenshots show Editor keyboard/drag selection and acknowledged cut, localized
Settings search opening Keyboard, all four exact maximum-integer readouts and
wrap to zero, and a newly reopened Activity Monitor retaining Resources/Network.
Build hashes, source revisions, test logs and guest screenshots are retained
under `build/utility-view-validation/`.

### Clipboard and image-orientation follow-up (2026-10-06)

The combined utility suite passes 276 behavior cases and 86 tracked-memory
cases across 23 modules; the parity suite passes 96 behavior and 21 memory
cases. Settings passes 166 behavior/localization cases plus 12 memory cases.
Every measured repeated-use group passes its zero-retention assertion. Clipboard/UTF-8 checks
pass 27 cases, with another nine Terminal UTF-8/rebuild regressions passing.
A separate seven-case Dictionary run executes the full 147,306-headword
corpus and the new copy tests (109 assertions), without skipping corpus data.

The complete host IPC fixture and its focused utility entry pass. The latter
also runs as a static AArch64 executable inside Vinix with `--require-vinix`,
requiring the actual `/dev/processes` device. It checks complete Dictionary
copying, exact Calculator copies in all four integer bases and both decimal
modes, scientific controls and error preservation, live Terminal UTF-8
selection and independently seeded Cmd-C copying, and EXIF-oriented PNG
exports, composed rotation and byte-exact Original Copy. New lifetimes and
the IPC assertions received independent reviews.

The static desktop from `cdcdcc4a` is published for Files, Activity Monitor
and Settings. Its 5,903,976-byte artifact has SHA256
`164e62067fddb6e1788e85b618e90ab90d6495a655952799d90e306d53bbafce`;
all three published copies match. Production sources remain identical through
the IPC test commit `5c942611`. A fresh QEMU utility scenario runs all five
native app clients, the compositor and Terminal's shell. Inspected screenshots
show Terminal, Calculator and Dictionary copies pasted into Editor, exact
Programmer readouts with acknowledged copying, and an EXIF-oriented portrait
composed with a manual quarter-turn. The cached test image emits its existing
Zsh/ZLE module diagnostic; shell input and the Terminal IPC checks still pass.
The final GUI run uses longer simulated key holds and paste settling after
an initially inconclusive paste screenshot. Logs, both GUI observations,
frozen source manifests, binary hashes and final screenshots are retained in
`build/utility-copy-validation/`.
