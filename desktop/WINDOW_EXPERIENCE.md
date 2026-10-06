# Desktop window experience

This audit compares Vinix's native desktop window manager with everyday
window-management features in macOS and Windows. It covers moving, resizing,
arranging, focusing and hiding windows, and moving between workspaces. It does
not cover application feature parity, which is tracked in [UTILITIES.md](UTILITIES.md).

The starting state was checked in the implementation, including [wm.v](wm.v),
[window.v](window.v), [window_shortcuts.v](window_shortcuts.v),
[titlebar_click.v](titlebar_click.v), [workspace.v](workspace.v),
[switcher.v](switcher.v), [taskbar_preview.v](taskbar_preview.v) and
[scale_wm.v](scale_wm.v). Apple and Microsoft support documentation was checked
on 6 October 2026. Priorities below are Vinix implementation decisions, not
claims that macOS and Windows behave identically.

## What already worked

| Feature | Implementation evidence and behavior |
| --- | --- |
| Move windows without jumping | `on_pointer_down` and `on_pointer_move` in `wm.v` retain the title-bar grab offset and keep enough of the frame on screen to retrieve it. |
| Restore a maximized or tiled window by dragging | `on_pointer_move` restores the original frame and retains the grab position proportionally along its title bar. |
| Minimize, maximize, restore and close | `wm.v` implements all four controls; `titlebar_click.v` adds double-click maximize/restore. `Cmd/Super+W` closes the focused window through the usual close handling. |
| Drag to arrange | Releasing at the top edge maximizes; left and right edges fill the corresponding half of the usable desktop. The taskbar remains visible. |
| Keyboard halves and quarters | `tile_focused` in `window_shortcuts.v` handles `Super+Left/Right`; following a half with Up or Down creates a quarter. The floating frame is retained for restore. |
| Resize from every corner | `window_element`, `window_resize_action` and `resize_window_to_pointer` in `wm.v` provide four corner grips, minimum sizes and fixed opposite corners. The README previously described only the lower-right grip. |
| Four independent workspaces | `workspace.v` isolates composition, focus, taskbar entries and window switching. `Super+1..4` switches; `Super+Shift+1..4` moves the focused window. Apps continue running. |
| Visual window switching | `switcher.v` implements a quick `Cmd/Super+Tab` switch and a panel on a longer hold, reverse traversal, cancellation and restoration of minimized windows. It lists windows on the current workspace. |
| Show Desktop with precise restore | `taskbar_preview.v` minimizes visible windows in the current workspace and records their IDs; a second invocation restores that set. The taskbar corner and `Super+D` invoke it. |
| Taskbar previews and Peek | `taskbar_preview.v` provides retained thumbnails, grouped window selection, preview closing and temporary window/desktop Peek. Pins, ordering and Jump Lists are already present in the taskbar. |
| Preserve arrangements across scaling | `scale_wm.v` reapplies tile geometry for the new logical desktop extent and clamps floating/restore frames. |

These features are the baseline. They should not be counted as newly added
macOS or Windows parity work.

## Improvements in this update

| Missing feature at the start | New Vinix behavior | Comparison |
| --- | --- | --- |
| Title-bar shake to focus on one window | While dragging a title bar, several deliberate horizontal reversals minimize the other visible windows on the current workspace. A later shake restores only those windows. Windows that were already minimized and windows on other workspaces keep their state. | Windows provides title-bar shake to minimize other windows. [Microsoft's focus settings](https://support.microsoft.com/en-us/accessibility/windows/make-it-easier-to-focus-on-tasks). |
| Keyboard access to hide others | `Cmd/Super+Alt+H` invokes the same reversible action as shaking. `Super+Shift+M` restores the windows hidden by this action. The parser also accepts `Super+Home` from clients that emit modified Home; native keyboard drivers currently report Home without its modifiers. | macOS has `Option+Command+H` to hide other apps. Vinix applies the action to individual windows on one workspace and makes it reversible. [Apple's keyboard guide](https://support.apple.com/en-mide/102650). |
| Mouse access to quarter tiles | Drag to a desktop corner to fill that quarter; bottom corners are reachable at the work-area boundary above the taskbar. Drag to a side away from its corners to fill that half; drag to the top away from its corners to maximize. | Windows supports corner snapping as well as side snapping. [Microsoft's Snap guide](https://support.microsoft.com/en-us/windows/experience/snap-your-windows). |
| Feedback before a snap | A translucent destination preview appears during a title-bar drag, showing the frame that will be applied on release. Moving away removes it. The preview and final placement use the same destination policy. | Windows previews the pending snap before release. [Microsoft's Snap guide](https://support.microsoft.com/en-us/windows/experience/snap-your-windows). |
| Resize one dimension without moving the other | Floating windows can be resized from all four edges as well as all four corners. Left/top resizing anchors the opposite edge; side resizing preserves height and top/bottom resizing preserves width. | This makes routine window sizing practical without requiring a diagonal corner drag. |
| Keyboard minimize for the active window | `Cmd/Super+M` minimizes the focused window. `Super+Down` minimizes a floating window; existing restore and quarter-tile transitions remain available for arranged windows. A minimized window can be reopened with the taskbar or window switcher. | `Command+M` minimizes the front Mac window; Windows' arrow shortcuts support a restore/minimize sequence. [Apple's keyboard guide](https://support.apple.com/en-mide/102650), [Microsoft's keyboard guide](https://support.microsoft.com/en-US/Windows/Hardware/Input-Devices/windows-keyboard-tips-and-tricks). |
| Persistent window overview | The taskbar overview button or `Cmd/Super+Ctrl+Up` opens a thumbnail grid for the active workspace, including minimized windows. Click a card or use arrows and Enter to restore/focus it; Escape or a backdrop click dismisses. Workspace buttons switch the grid, and Previous/Next pages keep every window reachable on small displays. Cards reuse retained thumbnails, with an app icon or generic window icon when no picture is available. `Cmd/Super+Tab` keeps its existing quick switcher. | Both macOS Mission Control and Windows Task View offer an overview for finding windows. Vinix's initial overview provides selection and workspace switching. [Apple Mission Control](https://support.apple.com/en-gb/guide/mac-help/mh35798/mac), [Windows Task View](https://support.microsoft.com/en-gb/windows/how-to-multitask-in-windows-b4fa0333-98f8-ef43-e25c-06d4fb1d6960). |
| Discoverable arrangement chooser | `Cmd/Super+Z` or a right click on a window's maximize button opens an anchored chooser for maximize, restore, side halves and four quarters. Click a layout or use arrows and Enter; Escape or a click outside closes it. Small displays use a compact menu. | macOS and Windows expose arrangements from window controls; Windows also supports a layout shortcut. [Mac tiling icons and commands](https://support.apple.com/my-mm/guide/mac-help/mchl9674d0b0/mac), [Windows Snap layouts](https://support.microsoft.com/en-us/windows/experience/snap-your-windows). |
| Snap Assist for the vacant half | A user half-snap from dragging, the chooser or Super+Left/Right offers visible current-workspace windows for the opposite half. Click or use arrows and Enter to tile one; Escape/click-away skips. Minimized windows are excluded, and an already occupied opposite half produces no offer. Paging keeps candidates reachable on small displays. Super+Up/Down still continues from a half into a quarter. | [Windows Snap Assist](https://support.microsoft.com/en-us/windows/experience/snap-your-windows). |
| Windows switch and close shortcuts | Alt+Tab and Alt+Shift+Tab use the existing visual switcher, with the last Alt release committing selection. Alt+F4 calls the normal close handler, preserving unsaved-document handling. SPI, virtio and PS/2 drivers supply the necessary chords and release event. Fragmented input is retained without passing partial shortcuts to apps. | [Windows keyboard shortcuts](https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec). |
| Window action menu and keyboard move/resize | Alt+Space or a right click on the title bar opens Move, Resize, Minimize, Maximize/Restore, Arrange, desktop migration and Close. Move/Resize uses 10-pixel arrow steps (1 with Shift), Enter applies, and Escape/click-away restores the full original frame and arrangement. Small screens page menu actions. | [Windows keyboard shortcuts](https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec). |

On Mac keyboards, Command is the desktop's Super modifier. Shake and hide
others operate within the active workspace. Restoring the hidden set should
not revive windows that the user had already minimized, or switch workspaces.
Closing or moving a window while others are hidden must not make restoration
act on a different window.

## Remaining gaps, in priority order

These features remain separate work. Each row states a concrete useful next
step and the current limitation, rather than claiming full desktop parity.

| Priority | Feature | Current limitation and proposed next step | Reference |
| --- | --- | --- | --- |
| P2 | Shared divider for tiled windows | Tiled windows have fixed half/quarter dimensions and do not resize together. Introduce an explicit adjacent-window pairing and a divider that respects both windows' minimum sizes; update both frames together. | [Windows divider resizing](https://support.microsoft.com/en-us/windows/experience/snap-your-windows). |
| P2 | Arrangement groups | Taskbar grouping is by application, not by a set of tiled windows. Track a tile group and let one taskbar/overview action raise the whole group; remove closed or independently moved members safely. | [Windows Snap groups](https://support.microsoft.com/en-us/windows/experience/snap-your-windows). |
| P2 | Richer workspaces | Four numbered workspaces and keyboard migration already work. Add pointer migration in the overview, user-visible names and adjacent-workspace shortcuts first; then support bounded creation/removal and carry live windows to a surviving workspace on removal. | [Windows multiple desktops](https://support.microsoft.com/en-gb/windows/how-to-multitask-in-windows-b4fa0333-98f8-ef43-e25c-06d4fb1d6960), [Apple's Spaces overview](https://support.apple.com/guide/mac-studio/manage-windows-on-your-mac-apd2345fc25d/mac). |
| P2 | True native fullscreen | Maximize currently fills the usable desktop and keeps chrome/taskbar. Add a distinct fullscreen state with reversible frame storage, explicit exit, correct input routing and a way to reach desktop controls. This is separate from display-owning external applications. | [Apple fullscreen and Split View](https://support.apple.com/guide/mac-studio/manage-windows-on-your-mac-apd2345fc25d/mac). |
| P2 | Window gesture preferences | Drag snapping and gesture thresholds are currently compositor policy. Add persisted controls for shake, snap activation and double-click behavior, with useful defaults and localized Settings labels. | [Windows multitasking settings](https://support.microsoft.com/en-us/accessibility/windows/make-it-easier-to-focus-on-tasks), [Mac tiling settings](https://support.apple.com/en-afri/guide/mac-help/mchl118087b0/mac). |
| P3 | Additional tile regions and coordinated layouts | The arrangement enum supports side halves and quarters, without top/bottom halves, thirds or coordinated multiwindow layouts. Extend shared geometry and the existing chooser after establishing minimum-size policy for each new region. | [Mac tiling commands](https://support.apple.com/my-mm/guide/mac-help/mchl9674d0b0/mac), [Windows Snap layouts](https://support.microsoft.com/en-us/windows/experience/snap-your-windows). |
| P3 | App-focused overview and task groups | The desktop switches individual windows; it does not provide an app-only overview or Stage Manager-style project groups. Build these on overview/group infrastructure if they prove useful in daily use. | [Apple App Exposé](https://support.apple.com/en-gb/guide/mac-help/mh35798/mac), [Apple Stage Manager](https://support.apple.com/en-sa/guide/mac-help/mchl534ba392/mac). |
| P3 | Multiple-display window policy | The native desktop composes one canvas and uses one screen extent. Per-display work areas, window migration and arrangement recovery after reconnecting displays need display enumeration and input/composition support first. | [Apple's display-specific Mission Control behavior](https://support.apple.com/en-gb/guide/mac-help/mh35798/mac). |
| P3 | Gesture and hot-corner navigation | Keyboard and pointer actions exist, but there is no desktop gesture or configurable hot-corner layer for overview/workspaces. Add this after the corresponding desktop actions exist and input devices expose the required gestures. | [Apple Mission Control gestures](https://support.apple.com/en-gb/guide/mac-help/mh35798/mac). |

## Verification

The window manager runs without a garbage collector. Gesture recognition must
use bounded state and keep allocations out of repeated pointer-motion paths.
Shake restoration is tracked by a flag on each window and one bounded session
record per workspace, so it needs no per-gesture window-ID list. Temporary UI
retains explicit ownership of any allocated resources. Lifetime review also
checked the generated C for direct `ui2.Element` field transfers of the pooled
placement and layout trees, avoiding V's deep clones of borrowed element arrays.

The regression cases for these changes cover:

- Shake recognizes deliberate reversals but ignores ordinary travel, tiny
  jitter, stationary packets and gestures too far apart in time.
- Shake restores precisely its saved set, including after a member is closed,
  moved to another workspace or explicitly activated.
- One pointer gesture triggers at most one hide/restore action.
- Every corner and edge selects the expected resize cursor and anchors the
  opposite side while enforcing minimum size and visible title-bar bounds.
- Quarter, half and maximize previews match the final release frame; a plain
  title-bar click does not arrange a window; dragging an arranged window
  still restores its floating size.
- Global shortcuts consume only their recognized chords, keep ordinary app
  keys intact, and target the visible workspace.
- Existing title-bar double-click, scaling, Show Desktop, previews and
  workspace tests continue passing.
- Overview cards include minimized windows, borrow retained thumbnail buffers,
  and exclude other workspaces; stale IDs cannot activate a different window.
- Overview keyboard and pointer input stay modal, partial toggle sequences
  stay out of application input, and pagination reaches every open window.
- Opening a modal cancels an application's held pointer buttons once and
  consumes their later physical releases, including simultaneous buttons;
  canceled desktop shortcut drags restore their original order.
- Modal controls keep the desktop cursor visible over game surfaces that
  ordinarily hide it, and snap previews do not contaminate cached thumbnails.
- Cards without a cached picture retain an app or generic window icon.
- Snap Assist excludes minimized/background-workspace windows, skips occupied
  halves, validates stale IDs, pages candidates and preserves quarter shortcuts.
- Keyboard Move/Resize applies precise increments and constraints; cancellation
  restores frame, saved restore frame, maximize and snap metadata without
  changing focus. Close continues through the application's existing veto.
- Alt and Super switching use the matching release event. Global shortcuts can
  replace an open window control, and fragmented/malformed input is accounted
  for byte by byte without duplicating a lone Escape.
- SPI keyboard fixtures cover both Alt keys, reverse switching, repeat,
  reset and ordinary Meta input while preserving the decoder C ABI.

All 15 window-experience suites passed: isolation, placement, edge resizing,
overview, layout chooser, Snap Assist, window actions, Windows shortcuts,
title-bar clicks, workspaces, taskbar features, switcher, Quick Launch,
utilities and Color Meter. The additional localization suite passed for all
six supported languages and their glyph coverage. Tests run through
[test-window-experience.sh](tools/test-window-experience.sh) with V's new
compiler, `ui2_headless`, `-gc none` and `-manualfree`. Optimized static desktop
builds and isolated optimized kernel builds succeeded for both ARM64 and AMD64.
The SPI production fixtures passed 21 keyboard and 19 touchpad groups under
ASan/UBSan, preserving the C ABI and requiring no allocator imports.

The initial QEMU idle/application smoke and 25-second pointer scenario checked
overview, layout selection, shake hide/restore, placement previews, quarters
and drag-to-restore. The captures are
[window overview](../docs/screenshots/vinix-window-overview-qemu.png) and
[arrangement chooser](../docs/screenshots/vinix-window-layouts-qemu.png).

The follow-up 65-second QEMU scenario uses a scratch init with desktop stdin
connected to `/dev/console`. QMP keys travel through the updated VirtIO keyboard
driver into the desktop. All 18 visual checks passed, with 22 captures: a half
snap opens Assist; choosing a candidate fills the opposite half; Escape and
Alt+Space control the menu; keyboard Move/Resize applies and cancels correctly;
Alt+Tab and Alt+Shift+Tab display the switcher and focus the expected window on
release; Alt+F4 closes only the focused window. The guest exited without a
kernel panic. Reviewed captures show
[Snap Assist](../docs/screenshots/vinix-window-snap-assist-qemu.png) and the
[window action menu](../docs/screenshots/vinix-window-actions-qemu.png).
