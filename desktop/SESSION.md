# Desktop shell and session services

Open **Desktop & Session** with **Super+N**. Its five tabs configure workspaces,
show notification and alarm history, select clipboard history, control services,
and explain keyboard and pointer gestures. Settings provides the device and
session controls. These surfaces use the same session broker as applications.

Workspaces support 1–16 named spaces, floating, columns, rows, grid and main/stack
layouts, and groups that migrate together. Super+1…4 selects the first four;
the pager and overview reach every configured workspace. Layouts operate per
display and leave crowded windows usable when minimum tile sizes cannot fit.
Up to eight framebuffer outputs form a horizontal, bottom-aligned desktop.
Maximize and snapping use the window's display. Output changes are checked every
two seconds; windows fall back onto a connected display. The optional return
policy retains a disconnected display's identity for reconnection.

Placement snapshots include application identities, instance numbers, frames,
restore frames, workspace, group, display, snap, minimize and maximize state.
They are written when changed, at most once every two seconds, and on orderly
exit. Login and compositor reload restore applications and placement. Missing,
crashed or unresponsive applications retain a recovery window with retry and
close controls; the compositor's application IPC already has bounded waits.
Application document contents remain the application's responsibility.

The separate broker owns notifications, quiet/focus policy and alarms. Notices
include urgency, optional progress and an action. Notification progress feeds
running taskbar buttons. Clock countdowns register durable alarms; closing Clock
does not cancel them. The center lists outstanding alarms and can cancel them.
The broker recovers deadlines from wall time after restarting and uses monotonic
deadlines while running. Notification actions support `launch:<catalog-id>`,
`open:<absolute-path>` and `uri:<URI>` and execute when the user selects Open.

Services run in private process groups with dependency ordering, bounded restart
backoff and limits, reverse dependency shutdown, grace deadlines and forced
termination. Each group has a guardian connected to the broker by a lease;
losing the broker terminates its groups. Services must run in the foreground
and keep their children in the assigned group. Logs are private files under
`.vinix-service-logs`, checked every five seconds and truncated after 1 MiB.
Enable/disable choices persist. Only root may load definitions marked system.
The default root service synchronizes time using SNTP; nonroot sessions report
that setting system time requires root. Replies validate the request nonce,
server mode, leap/stratum, era, root uncertainty and round-trip bounds. Installed
IANA zoneinfo enables named zones and daylight-saving changes; a numeric UTC
offset is also available.

Shared file, save-file and folder dialogs are rendered by the compositor. Text
Editor and Preview use them; hosted wrappers expose the same picker on Ctrl+O.
Save dialogs ask before replacing an existing file. A dialog returns a path to
its authenticated owner, once. Files has Open With; MIME and URI defaults persist.
User MIME choices apply to Files, launcher results and session open requests.
Dragging a file to a window sends its open action; dropping on the desktop opens
the application chooser. Hosted wrappers deliver file/URI opens to the hosted
application's input interface.

The clipboard supports UTF-8 text, HTML, URI lists and PNG, with 16 in-memory
history entries and a 64 KiB payload limit. Plain-text clients receive an HTML
text fallback. Preview accepts PNG. The X11 bridge negotiates selection targets
and serves rich selections to hosted applications. Password/sensitive offers
are excluded from history. Clipboard privacy settings disable app access or
history; Capture obeys the screen-capture setting. Application exchanges use
random, single-use five-second tokens bound to UID, source PID, target PID and
data type. New copies and dead owners revoke grants. External window/session
actions require recent input in the focused application; help and explicit
user-confirmed dialog requests remain available.

Settings covers sound, Bluetooth, printers, users, network, privacy, storage,
updates, accessibility, time, power, shortcuts, gestures and services. Sound uses
the real OSS mixer. Bluetooth/CUPS/account/network actions use installed tools
with argument arrays, process supervision, deadlines and logs. Storage opens
the existing inspection utilities; updates invoke the installed version checker.
Existing startup applications, recent items, appearance and power settings stay
integrated. Missing tools, drivers, microphone/speech support and in-place system
updates are reported as unavailable. These pages do not imply that a missing
hardware driver is implemented.

Shortcut capture customizes shell, overview, help, show-desktop, close and
minimize actions. Configurable corners activate after a 600 ms dwell. Optional
middle-button gestures switch spaces horizontally or open overview vertically.

## Application API

The desktop executable exposes the broker client without opening a framebuffer:

```text
vinix-desktop --session-control notify job "Download" "Receiving data" 0 45 "launch:vinix-files"
vinix-desktop --session-control alarm timer "Tea is ready" 300 0
vinix-desktop --session-control alarm.cancel timer
vinix-desktop --session-control action help
vinix-desktop --session-control action open /home/user/Documents/readme.txt
vinix-desktop --session-dialog 0 /home/user/Documents text/plain
```

Notification urgency is 0/1/2; progress is -1 or 0…100. Alarm delay and repeat
are seconds; zero repeat means once. Dialog kinds are 0=open, 1=folder, 2=save.
Dialog CLI prints the selected path. Alarm, notification and direct policy changes
acknowledge durable snapshots. `action` acknowledges queueing for the compositor
and supports `launch`, `uri`, `open.with`,
workspace count/switch/rename/layout, clipboard offer/request and settings actions.
Settings mutations require the actual Settings application's authenticated PID.
Administrative history, policy, service controls, grants and shutdown require
the compositor's private inherited connection. `attach` only confirms that
connection; it cannot claim authority through the public socket, even with the
same PID. Running the client from an unrelated terminal does not grant a user
gesture. See [session selector filters](../docs/security.md#session-selector-filters).

The compositor creates a socket pair before launching `vinix-session`, keeps one
endpoint private, and passes the other to the broker at startup. Both endpoints
are then close-on-exec, so applications and services do not inherit the capability.
The broker requires this connection at startup; `--session-owner=PID` is no
longer accepted. Closing or losing the connection saves session state and shuts
down supervised services. A restarted compositor launches a fresh broker and
connection, restoring durable alarms and service configuration from snapshots.

The private 0700 runtime directory is `/run/user/<uid>/vinix-session.<uid>` for
ordinary accounts and `/run/vinix-session.0` for root; its Unix socket is 0600.
The ordinary default validates the trusted `/run/user/<uid>` parent chain.
Kernel peer credentials supply identity. `VINIX_SESSION_RUNTIME` preserves the
explicit base-directory override. Frames have a four-byte little-endian length followed
by a bounded UTF-8 record; text arguments are hex-encoded tab fields. General
records are limited to 256 KiB. Clipboard bytes use a separate bounded encoding.

Private atomic snapshots in the selected user home are `.vinix-window-session`,
`.vinix-notifications`, `.vinix-shell-policy`, `.vinix-associations` and
`.vinix-services`. Versioned records validate numbers, identities and field bounds,
reject unknown versions, and reject cyclic service dependencies. Service records
start with `vinix-services<TAB>1`; each service row contains hex name, hex absolute
executable, dependency bitmask, restart policy (0/1/2), restart limit, initial
backoff milliseconds, stop milliseconds, enabled/system flags and up to 16 hex
arguments. Definitions are read on broker startup. Enable changes persist through
the Services tab; changing definitions requires restarting the broker.

## Validation

`desktop/tools/session_check.v` is the native V build and test driver. It stages
sources independently so unfinished edits from concurrent sessions cannot enter
the artifact. Build it with the repository's V compiler and the `hosttest` module
from `tests/linuxkpi`; set `V` to the compiler executable. The driver uses installed
ui2, falling back to `third_party/ui2`.

```text
session-check core          # session state, records, services, alarms, exchange, SNTP
session-check build         # host desktop and isolated broker executable
session-check integration   # real credentials, persistence, service groups and displays
session-check               # existing workspace/layout/action/Settings/Clock regressions
session-check x11           # both architecture selection bridges
session-check cross         # ARM64 and x86-64 static Linux executables
session-check publish       # atomic app-sync binaries and version markers
```

Integration tests kill and restart the broker, verify alarms outlive their
originating process, deny unauthorized Settings changes and replayed exchange
tokens, cycle a dependent service group and check broker-crash cleanup. Viewport
and placement tests exercise display coordinates and missing-display fallback.
Physical hotplug, device tools and hosted application workflows additionally
require qualification on a guest with the corresponding devices and applications.
