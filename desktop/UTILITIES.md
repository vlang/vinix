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
| Calculator / Calculator | Pointer-operated basic decimal arithmetic, percent, sign and powers | Keyboard arithmetic and backspace, validated numeric/scientific-notation paste, memory register, relative percentages, bounded result history with paging and recall; Basic/Scientific selection, DEG/RAD, square root/reciprocal/square/cube/cube root, trig/inverse trig, ln/log10/log2/exp and pi/e, sinh/cosh/tanh and their inverses, editable EE exponents, binary nth-root and Rand operands in [0,1) with domain/finite or unavailable-source errors and scientific operation history; exact unsigned 8/16/32/64-bit Programmer mode with DEC/HEX/OCT/BIN entry/readouts, modular arithmetic, bitwise operations, logical shifts, labelled bit editing with compact paging, width-preserving history recall and preserved Basic/Scientific memory; acknowledged guest clipboard result copy in every mode | Signed programmer arithmetic, character-code readouts, RPN, expression parsing, unit/currency conversion, Math Notes integration, result selection, configurable precision/grouping and history persistence |
| Calendar / Calendar | Month navigation, selected dates, localized weeks and Today | Persistent local all-day/timed events with titles and locations; creation/editing/deletion; marked dates and selected-date agenda; strict ICS import/additive merge and exclusive export for one-day all-day or floating local minute-precision events; bounded UTF-8 title/location search across all stored events with chronological results and navigation into the actual event editor | Broader ICS semantics (timezones, recurrence, durations, alarms, extra fields), stable imported identities, duration/multiday events, day/week/year views, recurrence, reminders/notifications, multiple calendars, CalDAV/accounts and invitations |
| Clock / Clock | Local time and a monotonic stopwatch with pause/resume/reset | Bounded lap/split/total records; up to four independently named countdown timers, duration presets/adjustment and exact HH:MM:SS entry, pause/resume/reset and visible expiry | World clocks and timezone database; scheduled/repeating alarms; sound/notifications; persistence and a service that continues after the app closes |
| Capture / Screenshot and screen recording | Full-desktop PNG, delay, self-hiding, 5/10 fps AVI recording, stop/cancel and status | Recording-delay controls on the Video page; Enter to start and Escape to stop/cancel; pointer shown/hidden choice for PNG and AVI | Window/region selection, output-location chooser, clipboard capture, capture hotkeys, thumbnail/reveal workflow, audio and compressed video |
| Disk Usage / Storage settings | Resumable size inventory, largest-folder/file rankings, hard-link deduplication, symlink avoidance, drill-down, parent navigation, stop and rescan | Editable scan root and report destination, keyboard input, raw-byte CSV report with proper text escaping and overwrite protection; total/used/free/available snapshot for the filesystem containing the scan root, refreshed on each scan and included separately in CSV | Mounted-volume overview, allocated versus logical size, storage categories, treemap, reveal in Files and guarded cleanup; disk management belongs in a separate utility |
| Terminal / Terminal | Real PTY/Zsh, VT cursor/alternate-screen support, UTF-8 cells, bounded scrollback, paste and rebuild handoff | Find in scrollback/live screen with next/previous and wrap, match-row highlighting, and clear scrollback preserving live/alternate-screen contents; UTF-8 mouse selection across physical output rows, double-click word/triple-click physical-line selection and drag expansion, explicit Text/Block modes with rectangular copy and short-row padding, acknowledged guest clipboard Copy/Cmd-C and preserved Ctrl-C shell input | Modifier-key rectangular gestures, wide and combining character cell widths, logical-line reflow, tabs/split panes, profiles/fonts/colours, configurable history, complete ANSI colours/attributes, hyperlinks and command bookmarks |
| Preview / Preview | Quick Look inside Files; no standalone viewer | Standalone PNG/JPEG viewer with editable paths, fit/actual-size/zoom, panning, quarter-turn rotation, all eight JPEG EXIF orientations composed with manual rotations, rectangular cropping and alpha-weighted bilinear resizing with aspect lock and shared one-step Undo/Redo, alpha-preserving PNG export, and exact original-file copying without overwriting | Longer undo history/recovery; PDF rendering and page navigation; annotations, additional selection tools, colour profiles/adjustments, broader metadata inspection, additional formats, printing and a file picker |
| Console / Console | Application logs existed as files; no native viewer | Read-only bounded log tails, application-log presets, literal row filtering combined with All/Error/Warning/Info/Debug/Unmarked leading-marker filters, follow/paging, recent logs and matching-row export without overwriting | Central log collection/retention, structured metadata/property filters, structured crash reports and kernel-log capture; desktop output currently goes to `/dev/console` |
| System Information / System Information | Small About pane in Settings | Native overview, hardware, storage and package reports from real system sources; bounded UTF-8 search across row values, translated labels and categories with token/case/accent matching; refresh, paging and complete text export without overwriting | Broader device/driver APIs, structured property inspection and remote reports; unavailable sources are labelled explicitly |
| Archive Utility / Archive Utility | Terminal archive tools only | Native TAR browsing, creation and whole/selected extraction with entry/folder checkboxes, choices fixed during extraction, bounded streaming work, progress/cancel, new destinations and rejection of traversal, links and special entries | ZIP/gzip and other compressed formats; file picker and Files associations; encryption and larger archives |
| Disk Utility / Disk Utility | Disk Usage rankings and System Information mount reports | Read-only block-device and mounted-volume inventory, selectable details, valid capacity, refresh/paging and exclusive report export | Physical device/partition hierarchy, health/SMART, disk images, mount/unmount privilege workflow; formatting, repair and partition changes need filesystem tools and explicit destructive-operation UI |
| Backup / Time Machine workflow | No native backup workflow | Versioned local folder copies, completed-version browsing, explicit restore to a new folder and bounded progress/cancel | Scheduled backups, retention/free-space policy, permission/timestamp preservation, incremental deduplication, encryption, network destinations and system/filesystem snapshots; links and special files are refused |
| Notes / Notes and Stickies | A static demo window, without a note store | Persistent bounded UTF-8 titles and plain-text bodies, title/body search, debounced autosave, explicit deletion and exclusive text export; damaged records and conflicting saves preserve existing data; failed final saves block ordinary window/session closing, with keep-editing and confirmed-discard choices; bounded current-note title/body Undo/Redo that survives autosave; atomic one-file UTF-8 plain-text import with BOM/line-ending normalization | Rich text, attachments, folders/tags, sync/sharing, rich-format/batch/folder import, printing, locked notes and recovery/versions; floating sticky windows |
| Reminders / Reminders | No native task workflow | Persistent local tasks, optional local due dates/times, editable None/Low/Medium/High priorities with list badges, edit/complete/reopen, confirmed deletion, literal title search, all/open/completed/overdue filters, stable Added order/Priority/Due/Title sorting with independent session directions and exclusive text/CSV export in view order | Background alerts, recurrence, multiple lists, locale-aware sorting, saved sort preferences/manual reordering, tags/subtasks, attachments, calendar integration and account sync/sharing |
| Grapher / Grapher | Calculator arithmetic only | Bounded explicit `y=f(x)` expressions, real-domain gaps, axes and finite editable ranges, zoom/reset, versioned `.vgraph` documents with validated Open and exclusive Save As, separate sampled CSV export and exclusive 960×640 PNG image export with the same sampled curve/domain gaps and axes; exclusive standalone vector SVG with escaped text, clipped curves and domain gaps; compact Graph/Document/CSV/PNG/SVG pages and bounded tiny-window guidance | Autosave/recovery and file picker; multiple/implicit/parametric equations, 3D plots, additional export formats, animations, integration/intersection tools and graph styling |
| Color Meter / Digital Color Meter | No native screen-colour workflow | Compositor sampling in physical pixel coordinates, pointer tracking, freeze and independent physical X/Y locks, a 9×9 magnifier, 1×1/3×3/5×5/9×9 aperture averages, hex/RGB display and text copy to the guest session clipboard | ICC/display colour profiles and colour-space conversion, extended-range values, image copy and host clipboard writing |
| Dictionary / Dictionary | No offline lexical utility | Native offline WordNet 3.0 lookup with 147,306 headwords, ASCII case folding and phrase/prefix suggestions, bounded Back/Forward history, UTF-8 definition wrapping/paging, exclusive text export and acknowledged guest clipboard copy of the full headword and unwrapped definition | Pronunciation/audio, morphology, full Unicode case folding, multiple/language sources, encyclopedic articles, definition selection, lookup from selected text and persistent history |

Relevant macOS references: [process browsing](https://support.apple.com/en-ie/guide/activity-monitor/actmntr1001/mac)
and [diagnostics](https://support.apple.com/guide/activity-monitor/run-system-diagnostics-actmntr2225/mac),
[Settings search](https://support.apple.com/en-ie/guide/mac-help/mchl8d10839d/mac),
[copy/cut/paste](https://support.apple.com/en-us/102553),
[TextEdit search/replace](https://support.apple.com/guide/textedit/find-and-replace-text-txtef6cfde1a/mac),
[Calculator modes](https://support.apple.com/guide/calculator/choose-the-right-mode-calc22d50970/mac),
[scientific controls](https://support.apple.com/guide/calculator/use-the-scientific-calculator-calcf964141e/mac)
and [programmer bit editing](https://support.apple.com/en-bh/guide/calculator/calc8990e3ee/mac),
[Calendar events](https://support.apple.com/en-gb/guide/calendar/icalwr13-events/mac),
[Calendar search shortcuts](https://support.apple.com/en-sa/guide/calendar/ical002/mac)
and [calendar interchange](https://support.apple.com/guide/calendar/import-or-export-calendars-icl1023/27.0/mac/27),
[Clock](https://support.apple.com/en-mide/guide/clock-mac/welcome/mac)
and [multiple named timers](https://support.apple.com/guide/clock-mac/apdw3d5aebf9/mac),
[Terminal shortcuts](https://support.apple.com/en-bh/guide/terminal/trmlshtcts/mac),
[screenshot targets](https://support.apple.com/en-ie/102646),
[Preview documents and images](https://support.apple.com/en-ca/guide/preview/prvw846b61d3/mac),
[Preview image cropping and resizing](https://support.apple.com/guide/preview/crop-resize-or-rotate-an-image-prvw2015/mac),
[CIPA EXIF layout and orientation](https://www.cipa.jp/std/documents/e/DC-X008-Translation-2019-E.pdf),
[Console log messages](https://support.apple.com/guide/console/log-messages-cnsl1012/mac)
and [combined property filters](https://support.apple.com/en-mide/guide/console/cnslbf30b61a/mac),
[System Information reports](https://support.apple.com/guide/system-information/welcome/mac),
[archive compression/extraction](https://support.apple.com/en-lk/guide/mac-help/mchlp2528/mac),
[Disk Utility devices and volumes](https://support.apple.com/en-ca/guide/disk-utility/dskud6b39edb/mac),
[filesystem capacity details](https://support.apple.com/en-ie/guide/disk-utility/dskutl1005/mac)
and [Time Machine restore](https://support.apple.com/en-au/guide/mac-help/mh11422/mac),
[Notes text-file import](https://support.apple.com/en-ie/102223)
and [standard Undo/Redo shortcuts](https://support.apple.com/en-us/102650),
[Reminders tasks and due dates](https://support.apple.com/en-ie/guide/reminders/remndc729e28/mac)
and [list sorting](https://support.apple.com/en-ae/guide/reminders/remn922d0b42/mac),
[Grapher graphs and equations](https://support.apple.com/guide/grapher/create-a-graph-and-add-equations-gcalcd405d09/mac)
and [image export](https://support.apple.com/pt-br/guide/grapher/gcalc31bd60f/mac),
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
| Minecraft, DOOM, Steam, Gothic II, Roblox, Dota 2, PlayStation, PlayStation 2, Nintendo 64 | Games and stores, without a matching macOS system utility. Installation, graphics, sound, controller input and compatibility belong to their existing ports. |
| Vinix in QEMU | Virtual-machine integration; no bundled macOS utility equivalent. Guest input, clipboard, storage and session management remain integration work. |
| Android Calculator, iOS Calculator, iOS 2048, iOS PPSSPP | Compatibility demonstrations and mobile emulator integration. Platform API, graphics, input and lifecycle support belong to the Android/iOS layers. |

These 25 entries plus the twenty-one native utilities account for the complete
46-entry application catalog. PlayStation, PlayStation 2 and Nintendo 64
remain game integrations. Vim and shell tools installed in the userland are
terminal programs, not additional native desktop applications.

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
  Click Search or Ctrl-F to search all stored event titles/locations, including
  past and future months. All words must match with case/accent folding; results
  appear in chronological order and open the actual date and event editor.
  Clear or Escape returns to the month. Search does not interrupt editor or
  interchange drafts.
- **Clock:** record laps while the stopwatch runs; use the Timer tab for a
  countdown. Add timer creates another independent timer, up to four. Click its
  numbered selector and name field to rename it (48 UTF-8 bytes); Start/Stop,
  Reset and presets affect only that timer. `*` marks running timers and `!`
  marks finished ones. Pause before changing its duration or removing it.
  Set time opens a selected `HH:MM:SS` draft accepting one second through
  exactly 24 hours. Apply or Enter resets only that timer; Cancel or Escape
  preserves its duration. Invalid values leave the draft editable and the
  timer unchanged. Another timer expiring does not interrupt an active draft.
  Every running timer continues while another timer or the stopwatch is shown.
  Expiry is visible in this app; closing Clock cancels the timers. Names and
  timers are session-only, with no background alarm or sound.
- **Calculator:** use digits/operators/Enter and Backspace, memory buttons,
  or click a recent result to recall it. Select Scientific for unary functions
  including cube, cube root, log2, pi/e, sinh/cosh/tanh and their inverses;
  hyperbolic functions are independent of DEG/RAD. Choose DEG or RAD for trig and
  inverse trig. Ctrl-S switches modes and Ctrl-D switches angle units in
  Scientific mode. Functions transform the displayed operand, including the
  right operand of a pending calculation.
  EE, `e` or Shift-E starts an exponent: type its digits, use ± to change
  its sign, or Backspace to edit. An unfinished exponent cannot be used or
  copied. For an nth root, enter the radicand, choose root, enter its degree
  and press `=`. Negative radicands require an odd integer degree; degree
  zero is invalid. Negative degrees produce reciprocal roots when defined.
  A new digit replaces a scientific result; repeated equals repeats the last
  binary operation. Domain errors and non-finite results are shown explicitly.
  Scientific mode accepts a finite number pasted in exponent notation.
  Rand generates a fresh operand in [0,1) from bounded nonblocking system
  entropy reads. It preserves a pending calculation and memory, records history,
  and starts a new operand when you type a digit. Unavailable entropy preserves
  the current operand and shows a retry status.
  History is bounded to 20 results and includes function arguments/angle units.
  Select Programmer (Ctrl-P) for exact unsigned values and choose 8, 16, 32
  or 64 bits (64 by default). Ctrl-B changes
  the input base; prefixed numeric paste accepts `0x`, `0o` and `0b`. Full-sized
  windows display all four bases together; compact windows show the selected
  base. The bitwise keyboard controls are `&`, `|`, `^` and `~`. Addition,
  subtraction and multiplication wrap at the chosen width; NOT inverts that
  width only. Shifts are logical with counts smaller than the word width.
  Overflowing input and division by zero preserve the value and report an
  error. Narrowing drops high bits of current, pending and repeated operands;
  widening fills high bits with zero. AC keeps the selected width. Programmer
  history stores the original value and width, restoring both on recall without
  changing the selected base. Basic/Scientific state and memory are preserved
  while switching modes. Choose Bits to toggle the displayed operand: bit 0 is
  least significant, and full windows show all bits of the selected word.
  Compact windows page through eight labelled bits, retaining AC, equals and
  Copy. Keypad returns to numeric entry. Bit edits preserve pending/repeated
  operators and leave history unchanged until evaluation. Narrowing or recalling
  a narrower history value clamps the bit page; tiny windows show enlargement
  guidance. Signed arithmetic and character-code readouts remain work.
  Copy result or Ctrl-C snapshots the displayed number
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
  Double-click selects a word; triple-click selects a physical row and its
  newline when another row follows. Dragging extends whole words or rows,
  including backwards. Words use Unicode letters/numbers, underscore and common
  combining marks; whitespace forms runs, punctuation/symbols select one cell.
  Recognition uses successive clicks within 500 ms and five pixels. Wrapped
  output remains separate physical rows. Choose Block in the toolbar for a
  rectangle across physical rows; short or blank rows are padded with spaces
  to the selected width. Copies preserve internal spaces and UTF-8 cells,
  insert newlines between rows and omit a
  final newline. Block mode uses single-click dragging; Text restores word/row
  gestures. Switching modes clears selection and copy feedback. Modifier-key
  gestures and word-boundary preferences remain work. Output changes and
  resizing clear selection so stale cells are not copied.
- **Disk Usage:** edit Folder and Scan; edit Report and Export CSV. Existing
  report files are preserved. Export a completed or cancelled scan; cancelled
  scans are explicitly marked partial by their phase. Reports contain the
  retained rankings rather than every file. Choose Filesystem for the total,
  used, free and available space of the filesystem containing Folder. Rescan
  refreshes those figures; absent/invalid capacity data is labelled unavailable.
  Available excludes reserved space. These filesystem counters are separate
  CSV rows and do not change the logical file-content total of the inventory.
- **Capture:** Video now exposes the recording delay. Enter starts the chosen
  operation and Escape stops/cancels it. Click Pointer shown/hidden before
  starting to choose whether PNG screenshots and AVI frames contain the pointer.
  The choice is fixed during countdown/recording and applies to both pages;
  saved pixels beneath the pointer come from the compositor backing without
  erasing the live cursor. Older compositors keep the existing pointer-included
  behavior and omit this unsupported control.
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
  PNG writes the current edit and rotation. Width/Height accept pixel dimensions;
  Lock aspect ratio updates the other dimension. Resize uses alpha-weighted
  bilinear filtering in the displayed orientation, with at most 8192 pixels
  per side and 8 Mi pixels total. Undo/Ctrl-Z and Redo/Ctrl-Y restore the most
  recent crop or resize, including its orientation and view state. A new edit
  replaces that history step; successful Open clears it. Failed Open, invalid
  dimensions, allocation failure and no-op resizing preserve it. The source
  file is preserved. Two image buffers can occupy 64 MiB at rest; transactional
  resizing briefly allows 96 MiB, alongside the existing 40 MiB encoded-source
  limit and bounded viewport buffer.
  Bounded metadata parsing supports both TIFF byte orders and ignores
  malformed/unsupported orientation records. Original Copy
  keeps the exact cached encoded input, including its metadata, even after
  cropping, resizing, manual rotations or a later source-file change. Enter a
  new output path because neither export overwrites. Successful opens appear
  in the app's Recent Items. Longer edit history/recovery and PDF support
  remain work.
- **Console:** choose a log preset or enter an absolute regular-file path.
  Follow Tail refreshes once per second; paging suspends follow. The exact,
  case-sensitive filter and Export Rows apply to all retained rows, including
  those outside the viewport. Choose All, Errors, Warnings, Info, Debug or
  Unmarked to intersect a leading-level filter with the literal query. Levels
  recognize bare/bracketed tokens, colon-delimited bracket metadata, and Xorg
  markers after a numeric/ISO timestamp. ERROR/FATAL/CRITICAL map to Errors,
  WARN/WARNING to Warnings, INFO/NOTICE to Info and DEBUG/TRACE to Debug. Words
  inside an ordinary message do not infer a level. Filters stay selected on
  reload/source changes; exports retain source order. Snapshots keep at most
  the last 128 KiB. Small windows show enlargement guidance.
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
  Ctrl-A selects the active field. Notes autosaves after a typing pause. Each
  title/body edit can be undone with Undo or Ctrl-Z and redone with Redo or
  Ctrl-Y. The current note retains its last 32 edits, including whole pastes
  and selected deletions, across autosave. New edits replace the redo branch.
  Successful note switching, New, deletion or Reload clears this session
  history; failed saves and rejected text preserve it. Import or Ctrl-O opens
  a full text-file path; Enter imports one regular UTF-8 file as a new note,
  while Escape cancels. The basename supplies its title, stripping a nonempty
  case-insensitive `.txt` extension and truncating at a UTF-8 boundary. Optional
  UTF-8 BOM and CRLF/CR are normalized; the resulting body must fit 16 KiB.
  The current draft and new note are published together. Invalid text, size
  limits, busy storage and conflicting saves preserve the draft, history,
  selection and saved record. Source files are preserved; links and special
  files are refused. Rich-format, folder and multiple-file imports remain work.
  A failed save keeps the draft in the open window and blocks note switching;
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
  `YYYY-MM-DD HH:MM`, choose None/Low/Medium/High priority, then Save task.
  Select a task to Edit, Complete/reopen or confirm Delete. Search and filters
  apply to all retained tasks; export text or CSV writes the complete current
  view to a new path. Added order is the default; Priority puts High first,
  Due places earlier dates first with all-day before timed tasks on the same
  date and undated tasks last, and Title compares case-sensitive UTF-8 bytes.
  Direction reverses each selected sort, remembered independently in this
  window: Added oldest/newest, Priority high/low, Due earliest/latest and Title
  A–Z/Z–A. Undated tasks stay last in both Due directions. Ties keep added
  order. Sorting affects this window only, including exports;
  it preserves selected/edit/delete identities and never rewrites the saved
  task order. Tab to Sort and use Left/Right to cycle keys; on Direction,
  Right chooses reversed, Left chooses default, and Enter/Space toggles.
  Dates use local time;
  due-state display updates while the app is open. There are no background
  notification, recurrence or synchronization services in this milestone.
  Lists hold at most 256 tasks with 256-byte titles in a 128 KiB record. A
  conflicting save or damaged record preserves the previously saved file.
  Priority appears in each row and in text/CSV exports. Cancel keeps the saved
  priority; completing/reopening a task preserves it. Legacy version-1 records
  load with None and remain byte-identical until a successful task save, toggle
  or deletion publishes strict version 2. Older Vinix builds cannot read v2.
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
  Below a 600×452 content area, compact pages expose Graph, Document, CSV,
  PNG and SVG controls. Tab visits every field and reveals its page; Ctrl-L
  selects the equation. Changing pages by pointer stops edits to a hidden
  field. Below 280×320, enlarge the window to edit or export; Plot remains
  available where it fits, and hidden fields reject typing and paste until
  enlarged.
  PNG destination is a third, independent output field, initially `graph.png`
  in the canonical home directory. Export PNG or Enter in that field writes a
  new opaque 960×640 image with the expression, range labels, axes and the same
  sampled curve/domain gaps. Changed fields are replotted and validated first.
  Existing paths and symbolic-link components are refused; failed streams
  release their image/font buffers and remove only their own new file.
  SVG has a separate `graph.svg` destination and Export SVG action, also
  available through Enter in that path field. It creates a standalone 960×640
  vector image with expression/radian/range labels, axes, grid and the same
  sampled curve. XML text is validated and escaped; curve segments preserve
  gaps and clip at the range boundaries. It uses no embedded raster image.
  Existing files and symbolic-link components are refused. Validation or write
  failure preserves the graph/document fields and removes only its own new file.
  Expressions are limited to 256 bytes/operations, 32 parser levels and 16
  floor/ceil calls. Each plot uses 513 samples. Range magnitudes cannot exceed
  `1e12`, and each span must be at least `1e-9`.
- **Color Meter:** choose Live to follow the pointer at 100 ms intervals, or
  enter physical framebuffer X/Y coordinates and Sample (Enter). Freeze,
  Space or Escape holds the current sample. Lock X or Lock Y captures that
  physical coordinate from the last successful sample; Live follows only
  unlocked axes. Both locks keep the sampled location fixed. They remain
  independent across Freeze and Copy; manual Sample uses its entered
  coordinates. Unlock an axis to resume pointer tracking on it. If the live
  service does not reply within one second, Live stops with an explicit status
  and preserves the last sample. An explicit unavailable-framebuffer reply
  clears the sample. The 9×9 magnifier marks the
  chosen 1×1, 3×3, 5×5 or 9×9 aperture; RGB channels average its valid pixels.
  The sampled pixels exclude the compositor's drawn cursor using
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

### Document and selection follow-up (2026-10-06)

Preview now crops rectangular selections in the displayed image coordinates,
including EXIF orientation, manual rotation, zoom and panning. PNG export keeps
the cropped alpha values; Original Copy still preserves the source bytes.
Grapher saves versioned expression/range documents and validates an entire
document before replacing the current graph. Archive Utility extracts selected
TAR entries or folder descendants with choices fixed for the operation and the
existing whole-archive safety checks. System Information searches actual row
values, translated labels and categories without limiting the exported report.
Its Search caption remains visible in both themes, and result counts use the
English, Spanish and Russian plural forms.

The combined utility suite passes 295 behavior cases and 92 tracked-memory
cases across 23 modules. Every measured repeated-use group retains zero owned
bytes after warming persistent frame capacities. The Dictionary data encoder
also passes five Python cases. After the final search-caption change, System
Information passes its ten behavior and four memory cases again; the final
plural translations pass all 16 localization cases and another four memory
cases. New buffer ownership and the selection/document lifetimes received
independent reviews.

The complete host IPC fixture and its focused document entry pass against the
final production source. The same focused entry runs as a static AArch64
executable inside Vinix with `--require-vinix`, requiring the actual
`/dev/processes` device. It verifies every pixel of an independently seeded
2×2 crop, PNG export and byte-exact Original Copy; exclusive graph Save As and
restored fields/chart after Open; selected TAR descendants and omitted
similarly named siblings; and search, Unicode query transport, fragmented
navigation, polled Escape and complete unfiltered report export.

The final static AArch64 desktop (`38ee5040`) is published for Files, Activity
Monitor and Settings. Its 5,950,328-byte artifact has SHA256
`8c1a00173d59e08363faff21424184a5736d8d02ed213fd5dbe27d0142652ab7`;
all three published copies match. A fresh QEMU scenario runs the compositor
and the four real utility clients. Reviewed screenshots show a 200×120 crop
and successful PNG export, a saved graph changed to a parabola and restored by
Open, selective extraction with readable completion status, and search,
empty-result, report-save and Escape states. Guest output confirms the exact
saved graph fields, only the two selected archive files and all report
sections. These five-second samples verify startup and rendering; the
operation and repeated-use assertions above supply the functional and memory
checks. Corrected pointer coordinates and key mapping resolve the initial
inconclusive Grapher screenshots. Logs, both GUI observations, frozen source
manifests, binary hashes and final screenshots are retained in
`build/utility-document-validation/`.

### Crop recovery, event search and capacity follow-up (2026-10-06)

Preview has one-step crop Undo/Redo, restoring the pixels, orientation, zoom,
pan and selection without copying pixels during recovery. A new crop replaces
that history step. Successful Open releases it; failed Open/crop preserves it.
Calendar searches all stored event titles/locations with bounded UTF-8 input,
Latin/Cyrillic case and accent folding, chronological results, paging and
navigation into the actual event date/editor. Calculator adds six hyperbolic
and inverse-hyperbolic functions with domain/finite checks, independent of
DEG/RAD. Disk Usage reads total/used/free/available bytes from the filesystem
containing its scan root, refreshing the snapshot on scan and exporting these
counters separately from logical file-content totals.

The combined utility suite passes 319 behavior cases and 102 tracked-memory
cases across 25 modules. The parity suite passes 115 behavior and 28 memory
cases; the Dictionary data encoder passes five Python cases. Every measured
repeated-use group passes its zero-retention assertion after warming persistent
frame capacities. The shared compositor suite also passes nine checks,
including idle redraws, both window themes, Start-menu rendering, native polls
and remote trees.

Calendar's measured month/editor workflow initially retained 129 bytes per
fixture iteration: nested frame declarations deep-cloned borrowed strings when
appended as named values.
Generated C identified the shared `frame_child` append. Transferring declaration
fields preserves the existing ownership contract and reduces retention to
zero. The regression checks borrowed model text and owned frame labels retain
their pointer identity and are released by their existing owner. All helper
call sites and the new image-buffer lifetimes received independent
reviews.

The complete host IPC fixture and its focused recovery entry pass against the
final production source. The same focused entry, from test commit `666c5256`,
runs as a static AArch64 executable inside Vinix with `--require-vinix`. It
checks every original/cropped pixel after Undo/Redo and preserves exact source
bytes; all six scientific controls, domains, finite overflow boundaries and
mode state; Unicode event queries, chronological results, saved editor dates,
fragmented navigation and polled Escape; and capacity cards/raw CSV counters
separate from an isolated five-byte inventory, including unavailable sources.

The static AArch64 desktop (`1943e3dc`) is published for Files, Activity Monitor
and Settings. Its 5,997,720-byte artifact has SHA256
`8e8543bfd886de2a6c11fbc14c6b5cf97559ec6460cdfad9dc8aa13f87b21623`;
all three published copies match. Production inputs remain unchanged through
the regression-runner commit `811a090a`. A fresh QEMU scenario runs the
compositor and four real app processes. Nineteen reviewed screenshots show a
200×120 crop restored to 400×240 and redone, all three PNG exports, two matching
events in chronological order, the actual leap-day editor and preserved query,
empty results and Escape, correct cosh/asinh results, and filesystem capacity
with an unchanged five-byte inventory and saved report.

These five-second samples verify startup and rendering; the operation and
repeated-use assertions supply the functional and memory checks. The final
GUI harness checks the exact Calendar fixture in the user's persistent home
before startup and uses commands available in the cached guest image. Earlier
inconclusive seed observations, the final replay, source manifests, build
hashes, test logs and screenshots are retained under
`build/utility-recovery-validation/` and `build/utility-recovery-ipc-validation/`.
The inventory still covers all 42 catalog entries and the thirteen missing
utility proposals with their backend dependencies.

### Coordinate locks, graph images, note history and named timers (2026-10-06)

Color Meter now locks physical X and Y independently while Live follows each
unlocked axis. Existing wire commands and sizes remain compatible; appended
lock commands use the compositor's actual framebuffer and saved cursor backing.
Freeze, changed locks and timeouts fence stale replies. A one-second no-reply
timeout stops Live with a visible status and preserves the last successful
sample; an explicit unavailable-framebuffer reply clears it.

Grapher adds a separate PNG path and exclusive 960×640 export. The image uses
the same sampled strokes, clipping, domain gaps and axes as the displayed chart,
with expression, range and status labels. Dirty expression/range fields are
validated and replotted before export. Existing destinations, links and special
files are preserved; failed output removes only the newly created inode.

Notes keeps the current note's last 32 title/body edits across autosave, sharing
a bounded history between Undo and Redo. Paste and selected deletion each form
one edit. Failed saves, conflicts, rejected text and no-op edits retain history;
successful note changes and reload clear it. Undo/Redo controls remain bounded
in small windows, alongside the existing failed-save close choices.

Clock provides four independently named monotonic timers. Every running slot
continues while another timer or the stopwatch is displayed. Pause, reset,
duration changes and removal affect only the selected timer. Names accept up to
48 UTF-8 bytes; invalid or oversized paste preserves both the prior name and
its selection. Expiry never redirects an ongoing name edit. These timers remain
session-only; sound, scheduled alarms, persistence and a background service are
still gaps.

The final combined suite passes 351 behavior groups, including the full catalog
and last-entry taskbar pinning, and 109 zero-retention memory groups across 26
fixtures. Parity passes 120 behavior and 29 memory groups; the Dictionary data
encoder passes five Python cases. Validation uses an immutable production
snapshot, preserving another session's unfinished window-manager/language/font
edits. The final pin-table fix adds one static action for the previously added
iOS PPSSPP entry; it introduces no allocation or lifetime change. The inventory
now accounts for 43 entries: 21 native utilities and 22 integrations, with the
same thirteen missing utility proposals and their backend dependencies.

Both focused and complete host IPC workflows pass. The guest fixture is built
without V's `-prod` flag, which removes assertion statements in the native
compiler. Its generated C is checked for the required-Vinix assertion and
representative PNG pixel/gap, Notes history, Clock expiry and coordinate-lock
assertions before static linking. Earlier assertion-stripped guest builds and
logs establish execution/startup but cannot substantiate their stated value
checks; this assertion-enabled fixture supplies correctness evidence for the
four features in this batch.

The assertion-enabled static AArch64 fixture passes inside Vinix through actual
app processes, including independent locks at 2× scale, PNG dimensions/alpha
and domain-gap pixels, saved note history and independent named-timer expiry.
The final QEMU replay also passes review of all 18 screenshots: X stays fixed
while Y follows the pointer, both locks preserve the sampled location, PNG
export succeeds and refuses an existing destination, a whole clipboard paste
undoes/redoes atomically, and pausing Tea leaves Coffee running. The guest
record contains the exact `Undo demo` title and `Base#324A71` body; its exported
`/tmp/graph.png` is 2,458,493 bytes. The short process sample establishes
startup/rendering, not a performance or long-running leak result.

The published desktop build comes from production revision `2ccf7b3b`, is
6,038,504 bytes and has SHA-256
`eb7c4e8a36659319f0e557873deb7e89ab3a291d7851dd37d4ff3b2623dd82fa`.
Files, Activity Monitor and Settings published copies match that build. The
assertion-enabled guest fixture uses test revision `62815299`, is 5,768,856
bytes and has SHA-256
`7e244e28fa55272062cc284e37b8f42a0736cae8e9f1f3ec7abeadd8f53bbbbb`.
Source manifests, generated C and assertion checks, build commands, host/guest
logs, screenshot hashes and the independent review are retained under
`build/utility-controls-validation/`. Earlier assertion-stripped artifacts are
kept separately there as inconclusive correctness checks.

### Image resizing, scientific entry, compact graphs and exact timers (2026-10-06)

Preview adds bounded pixel dimensions, aspect lock and alpha-weighted bilinear
resampling in the displayed EXIF/manual orientation. Cropping and resizing share
one alternate image for Undo/Redo. Invalid dimensions, allocation failure and
no-op resizing preserve that history; original-copy bytes remain unchanged.
Calculator adds editable EE exponents and nth-root operations through its
existing pending/repeated calculation and history paths, with strict incomplete,
domain and finite-result checks. Numeric parsing preserves representable
subnormals, and formatting keeps finite maximum values finite on recall.
Grapher exposes compact Graph/Document/CSV/PNG pages and reveals the focused
field's page; tiny windows preserve graph state and block hidden edits. Clock
accepts exact one-second-through-24-hour drafts transactionally, preserving the
selected draft when another timer expires.

The immutable combined closure passes 219 behavior groups (7,045,263 assertions),
including all 98 groups for these four apps, and 43 memory groups (194,378
assertions) with zero retained allocations. It checks all six languages,
serialized controls, compact bounds, the complete catalog and taskbar pinning.
The behavior build retains two existing `os.execute` deprecation warnings and
one unused-parameter notice in older shared fixtures; the memory build reports
zero compiler errors, warnings or notices. Generated C and independent lifetime
reviews verify inline drafts, borrowed catalog slices and transactional image
ownership. Five font coverage cases pass: eight new characters are baked while
all 20,320 existing glyph masks and metrics remain identical across 16 faces.

Focused and complete host IPC and assertion-enabled guest IPC pass through
actual app processes. Legacy host fixtures now resolve crop coordinates from
the real viewport and verify usable, bounded scientific buttons rather than
the previous fixed button width, preserving their independent pixel and
numerical assertions. The guest checks the independent 2×2-to-1×1 resize's exact
RGBA(204,153,102,160), protected exports and exact Undo/Redo, EE arithmetic,
negative odd roots/domain errors, compact Grapher focus/export and independent
timer expiry. Its non-production V generation retains executable assertion
failure guards, verified in C before static linking. The guest fixture uses
test revision `24ee11ab`; subsequent legacy host-fixture geometry corrections
leave this focused guest entry unchanged.

The QEMU replay records 20 workflow screenshots plus the initial desktop:
256×256 aspect-locked resizing, export/Undo/Redo/protected overwrite,
Calculator results 0.01 and 2, all four compact graph pages with successful
PNG export and refusal to overwrite, and Clock's invalid draft, exact three
seconds and visible expiry. The Preview output is 262,488 bytes and the graph
image is 2,458,493 bytes. Short guest process samples establish startup and
rendering; retained-memory evidence comes from the heap fixtures. Original
failed harness observations are preserved, including the file-size parser's
SHA suffix mistake; its corrected whole-line parser revalidates the unchanged
serial record without another boot.

The published production revision is `52e332a9`; its AArch64 desktop is
25,408,600 bytes with SHA-256
`54fb70afa6c5c873e432ba5e9a598d037f9b2d9b3096b3d7d6bf216bd69c0760`.
Files, Activity Monitor and Settings copies match. The static assertion-enabled
guest fixture is 25,119,296 bytes with SHA-256
`174723b5e5764ac0251775c7b80d7391fcc882c77a073a3b974b76dc662bda5f`.
Frozen source manifests, generated C/assertion guards, build commands,
behavior/memory/IPC logs, font comparisons, QMP actions, serial bytes and
screenshot hashes/reviews are retained under `build/utility-next-validation/`.
The inventory remains 43 entries (21 native utilities and 22 integrations),
with thirteen missing utility proposals and their backend dependencies.

### Word selection, random operands, priorities and pointer capture (2026-10-06)

Terminal adds Unicode word and physical-row multi-click selection with whole
word/row drag expansion. Calculator adds Rand operands through the existing
pending arithmetic, memory, history and clipboard paths; bounded nonblocking
entropy failures preserve the current operand. Reminders adds four priorities,
list badges and export values. Strict version-1 records remain unchanged until
a successful mutation publishes version 2, preserving existing conflict and
corruption guards. Capture adds a shared pointer shown/hidden choice for PNG
and AVI, fixed during countdown/recording. Its negotiated wire flag preserves
the existing header sizes and pointer-included behavior on older compositors.
The compositor borrows saved cursor pixels synchronously without changing the
live canvas. Measured PNG-signature and grown AVI-index retention is also fixed.

Independent immutable focused stages pass 180 executed behavior groups
(2,740,688 assertions), including shared wire/catalog/language and native-close
regressions, and 29 memory groups (19,673 assertions) with zero retained bytes.
These totals count executed groups across the stages rather than a single
combined suite. Generated C and independent lifetime reviews cover the cursor
backing borrow, fixed PNG signature, single-owner AVI offsets, random operand
storage, priority drafts and allocation-free selection helpers. The shared
behavior fixture retains two existing deprecation warnings and one older
unused-parameter notice; its memory fixture reports no compiler warnings or
notices. Five font coverage cases pass: U+4E71 is added while all 20,448 existing
glyph masks and metrics remain identical across 16 faces.

Focused and complete host IPC pass through actual child processes. The fixture
checks pending Rand arithmetic and copy, legacy Reminders bytes and strict v2
priorities/exports, negotiated Capture flags and legacy peers, and Terminal
word/row clipboard contents from a completed output row. Its generated C retains
43 executable assertion failure guards across eight checked helpers. The guest
fixture uses committed test revision `a0aec349` and is generated without V's
assertion-stripping `-prod` flag.

The assertion-enabled guest IPC passes through actual Vinix app processes,
including exact Unicode word/physical-row clipboard contents and Cmd-C. The
final fixture waits for a stable shell prompt and emits Unicode through ASCII
printf escapes, retaining the independent byte expectations. This frozen
kernel has no trusted entropy, so guest IPC and the Rand screenshot verify
the recoverable unavailable-source path; the host checks the successful random
operand path. The first guest fixture's output-wait failure is preserved.

The QEMU replay records ten workflow screenshots plus the initial desktop:
pointer shown/hidden and successful PNG save, explicit Rand unavailability,
High priority draft/save, Medium draft/cancel retaining High, and exact word
and physical-row highlights. The PNG is 2048×1536 and 9,439,508 bytes; the
saved version-2 record contains the exact High-priority task. The compositor
and four native clients are present; each client has the compositor parent.
Terminal also starts Zsh.
Short process samples establish startup/rendering, while the heap fixtures
supply retained-memory evidence.

The guest runner exits successfully. Its original observer reports one parsing
failure because kernel exec/ELF diagnostics precede the reminder record header.
Separate strict post-run analysis passes against the preserved serial bytes:
it accepts only those known prefix lines before the header and requires the
exact record afterward. Unknown prefixes, changed priority, extra records and
diagnostics inside the record are rejected. The sealed observer and its failure
remain archived; no further guest boot is needed for this parsing correction.

The published production revision is `15c21a91`; its AArch64 desktop is
25,502,664 bytes with SHA-256
`dd7398f08bfe822ea0b332383505c1f9a2ab185e7f0df034ee3530e341b3eda7`.
Files, Activity Monitor and Settings published copies match that build.
The static assertion-enabled guest fixture is 25,208,288 bytes with SHA-256
`8794a1151c79f830e56d8fafd4ddc7b70d52bc0d166c24918c946148b0a6962e`.
Immutable source manifests, generated C and assertion guards, independent
lifetime/visual reviews, build commands, host/guest logs, font comparisons,
QMP actions, screenshot hashes and failed harness artifacts are retained under
`build/utility-input-validation/`, with app-specific focused evidence in
`build/calculator-random-validation/`, `build/reminders-priority-validation/`
and `build/terminal-word-selection-validation/`. The inventory still covers
43 entries and thirteen missing utility proposals with their dependencies.

## Sorting, log-level, integer-width and block-selection follow-up (2026-10-06)

Calculator now offers unsigned 8/16/32/64-bit words, bounded arithmetic and
logical shifts, explicit narrowing/zero extension, and history recall of the
original value and word width. Word-width choices are a Vinix engineering
extension to its integer mode. Reminders adds stable Added order/Priority/Due/
Title sorting of view indices, preserving saved order, editor/delete identities
and export order. Console intersects literal queries with explicit leading
levels and keeps ordinary message words unmarked. Terminal adds an explicit
Text/Block toggle, rectangular physical-row selection, UTF-8 copying and equal
space padding for short or blank rows, with the existing 64 KiB refusal bound.

Immutable focused stages run 116 behavior groups (28,770 assertions) and 31
manualfree retention groups (46,836 assertions) across these four apps. All
pass with zero retained bytes. Generated C contains executable heap-check
failure guards; Console's five classification helpers contain no allocation
calls, Reminders sorts fixed indices using borrowed task strings, Calculator
keeps width/history values inline, and Terminal frees temporary rectangular
copies after the clipboard client owns its snapshot. New lifetimes received
independent source and generated-C reviews before their commits.

A separate desktop/translation/native-close regression stage runs 106 behavior
groups (2,786,502 assertions) and nine retention groups (29,735 assertions).
Both pass; the final Console small-window refinement then passes its own 13
behavior and four retention groups. The broader fixture retains two pre-existing
os.execute deprecation warnings and one unused-parameter notice; the four
focused app suites report no warnings or errors. These are separate runs,
not one combined suite or duplicate-free aggregate.

The assertion-enabled native host fixture at 175c3ae4 passes both the focused
organize workflows and the complete existing IPC suite, including prior
Calculator/Rand, Reminders priorities, Capture flags and Terminal word/row
selection. Its real generated C retains 25 failure exits across the eleven
new workflow/helper functions.
Readout checks use stable labels instead of screen coordinates; a shared
Terminal helper waits for a settled cursor-bearing shell prompt before typing.
The host fixture freezes the earlier 43-entry catalog plus the four utility
changes; production at 09e70d94 includes the independently committed
44-entry catalog. Every owned source/catalog/compiler hash is recorded.

Production is cross-built from git-archive 09e70d94 with pinned UI2 sources and
recorded compiler/static-musl dependencies. The stripped AArch64 executable
is 25,706,456 bytes, SHA-256
c452ec1f47fdbcc3d67214e4b09c4db993a7180f143eddc0d90e43ff963b802c.
It has no ELF interpreter or dynamic segment. Files, Activity Monitor and
Settings aliases are published with identical bytes; their hashes and static
ELF properties received independent verification.

The non-production ARM IPC fixture differs from the 188-file production app
closure only in main.v. Its stripped static binary is 25,431,728 bytes,
SHA-256 da5cff3af22498bdb5648715d67b8eb2b943e3e35c440c41e4a6b89214fc9bde.
Independent generated-C review verifies the 25 workflow/helper exits, the
focused --require-vinix guard and the existing Basic display oracle (27 total).
Source, compiler and static-musl hashes remain unchanged after linking.

A disposable QEMU guest passes the native organize IPC workflows with
--require-vinix before starting production. Thirteen GUI workflow screenshots
show Calculator wrap/widen/history recall, Reminders Added/Priority/Due/Title
orders and draft preservation, Console All/Error/Unmarked and combined literal
filtering, and Terminal's padded four-column, three-row selection. Root reviews
all thirteen screenshots; an independent pixel review measures Terminal's
32-by-48 highlight, including the fully selected blank row. Native IPC checks
exact clipboard bytes; the GUI screenshot verifies selection and Copy feedback.
The compositor and all four native app processes run with correct parentage.

Final saved files match exactly: the 85-byte task record keeps insertion order
and its original High priority, the 139-byte CSV follows Title order, and the
23-byte Console export contains only `[ERROR] second failure` plus its newline.
The serial parser accepts two known kernel exec/ELF diagnostics before each
payload and compares exact contents after serial newline normalization, without
dropping payload lines. Wrapper and guest runner exit zero. All six runtime driver files, binaries and 1,482 launch,
firmware, compiler and sysroot dependencies retain their sealed hashes.
Guest logs, output files, action records, screenshot hashes and independent
reviews are in build/utility-organize-validation/driver and shots; the guest
summary is guest-summary.json. Prelaunch linker-path and root marker-spelling
check failures are preserved; correcting those checks requires no guest rerun.

All six catalogs gain 23 keys and four updated integer-width messages. Pinned
Japanese subsets and the atlas add nine code points; five font coverage tests
pass. All 20,464 existing glyph masks/metrics across sixteen faces remain
unchanged. Immutable snapshots, source/compiler hashes, assertion guards,
review records and logs are retained under build/utility-organize-validation,
build/calculator-width-validation, build/reminders-sort-validation and
build/terminal-block-validation. Redundant completed stages were archived as
hashed tar.gz files, and older generated C files were compressed when the
machine ran out of disk space; their evidence remains available.


## Bit editing, import and vector export follow-up (2026-10-06)

Calculator adds a labelled bit editor for every unsigned word width, with
eight-bit compact pages, pending/repeated operand preservation, history width
restoration and bit-page clamping. Reminders adds independent session directions
for all four sort keys, preserving stable ties, undated-last placement, editor
identity and ordered exports. Notes imports one bounded UTF-8 text file as a
new note while publishing the current draft in the same transaction; invalid files and
conflicts preserve the draft/history/store. Grapher exports standalone SVG
vector paths and text with XML escaping, range clipping and sampled domain gaps.
Its CSV, PNG and graph-document formats retain their existing behavior.

Immutable focused stages pass 126 behavior groups (4,690,895 assertions) and
44 manualfree retention groups (42,598 assertions). Calculator passes 50/17,
Reminders 25/6, Grapher 29/11 and Notes 22/10 behavior/retention groups. The
retention fixtures retain executable C failure guards and report zero retained
bytes; positive allocation witnesses confirm tracking is active. Actual native
generated C retains the behavior checks. New lifetimes received independent
review before the app commits. All four focused suites report zero errors,
warnings and notices.

The six catalogs each gain the same 34 keys and update the sorting hint. Five
font tests pass; sixteen atlas faces gain four code points and remove none.
All existing ASCII, Latin, Cyrillic, kana and symbol glyphs remain unchanged.
Only two existing shared CJK glyphs switch from the Japanese source to the
documented Chinese fallback because the new Chinese labels use them. Both
Japanese subsets add three characters while preserving all previous outlines,
metrics, hinting, names and license metadata. The generator and font sources
retain their documented pins.

The assertion-enabled host fixture passes the new utility refinement workflows,
the previous utility precision workflows and the complete existing native IPC
suite. It checks exact 64-bit readouts and clipboard bytes, all four Reminders
directions with ties and undated tasks, UTF-8 SVG escaping and exclusive export,
and Notes atomic import/conflict/cancel/history behavior against literal saved
record bytes. The host refuses the guest-only mode with the expected exit 97.

Production uses git-archive `8cbb11b5`, the actual compatible UI2 revision
`047bdced4209c49a71ad36604ee9348198278111`, a frozen compiler and private
optimized static-musl dependencies. The 25,874,024-byte static AArch64 desktop
has SHA-256 `c0a693c51f8c35ddc27cd78610e1bcf577e45ddf7aff3e08eb46048db7fe7944`.
Its standard build copy and Files/Activity Monitor/Settings published copies
have identical bytes. Independent checks rehash all original source, compiler,
UI2, library and tool inputs; no original input changed. The build reports zero
errors/warnings and 35 unused-function notices.

The static, assertion-enabled AArch64 IPC executable is 26,139,800 bytes,
SHA-256 `a55ccf13502d92dba07c00da03d4f93736fb8bbce95da7045c00f308ec3eb9a5`.
It differs from the 196-file production application closure only in `main.v`,
which contains committed fixture `f5102416`. Actual C retains 420 fixture
assertion sites plus the explicit false-condition exit 97. Shared readout,
clipboard, bounds and text helpers retain their conditional failure exits;
coordinators explicitly reach the four guarded client workflows. Both ELF
executables have no interpreter or dynamic segment.

Visual review found that Notes reused a paste-specific error for invalid file
content. Commit `8cbb11b5` makes that message action-neutral in all six languages.
Every catalog retains its keys and code-point set; product V sources and font
assets are unchanged. Matching production and native IPC snapshots were rebuilt
and independently reviewed. Only generated translation data differs from the
previous production application closure, and the critical feature C bodies are
byte-identical.

The isolated QEMU guest runs the assertion-enabled refinement fixture with
`--require-vinix` before the GUI replay. All four client workflows pass, and
Calculator, Reminders, Grapher and Notes are distinct children of the desktop
compositor. Fourteen workflow screenshots plus the initial desktop frame pass
independent visual review, including the corrected Notes error. Seven persisted
outputs match exact expected bytes: the original task record, ordered reminder
CSV, graph document, SVG, Notes record, normalized note export and unchanged
source-file bytes. The 15,979-byte SVG parses as 960×640 with 256 curve segments
and no raster images. All nine driver sources, 1,493 runtime dependencies and
eight handoff artifacts retain their sealed hashes after the run. The owned VM
is removed; cleanup targets only its unique runtime.

The first serial checker accepted single carriage returns but the UART/host
PTY path produced doubled carriage returns for console output. Its raw log,
failed verification and screenshots remain unchanged. Strict reconstruction
of that log confirms the same seven expected outputs. Within result blocks,
the corrected checker accepts LF/CRLF/CRCRLF transport, preserves every payload
line and rejects other carriage returns or unknown diagnostics. Its parser
checks pass 63 valid and reject 126 malformed cases; optimized Python execution
is refused. The final guest run passes this corrected checker directly.

Initial host manifests named the older `d13259f` UI2 checkout, while the default
module path actually selected the compatible sibling checkout. A private
production build exposed the mismatch. All four focused suites and all native
host modes were repeated with archived `047bdced`, a frozen-first module path
and empty private default modules; actual C confirms the frozen dependency and
excludes ambient UI2 paths. The Darwin test overlay derives only its headless
bounds condition so the excluded AppKit backend is unnecessary; the production
Linux bridge is unchanged. Original attribution failures and the first isolated
Darwin bounds failure remain archived. UI2 font assets match both revisions,
so the decoded-font comparisons and five font tests remain valid.

Evidence is retained under `build/utility-precision-validation`: corrected
focused suites in `calculator-047`, `reminders-corrected`,
`grapher-ui2-corrected` and `notes-corrected`; font proofs in `fonts`; host IPC
in `ipc/corrected-047`; final ARM builds, guest outputs, screenshots and review
receipts in `notes-wording`. Previous snapshots and failure evidence remain
alongside them.

The inventory still covers 46 catalog entries and thirteen missing utility
proposals with their dependencies. Remaining work includes rich-text/folder
interchange, background task alerts and implicit/multiple/3D equations.
