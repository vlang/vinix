# PowerPC native application launch

The shortcuts were receiving clicks, but the boot archive contained only
`/bin/init` and the PPC32 kernel had no child processes or IPC pipes. The desktop
launcher requires `/usr/bin/vinix-*`, fork/exec, two protocol pipes and wait/reaping.
Its failures were printed behind the compositor, making a click look ineffective.

Commit `54683f38a` adds the bounded process implementation, private address spaces,
descriptor sharing, pipes, exec, wait, per-process FPU state and raw PTYs. It also
keeps the compositor's framebuffer claimed when a child execs or exits. Native
apps need an 8 MiB stack: the earlier 2 MiB stack faulted while creating their
UI. Child faults now terminate that child rather than halt the whole kernel.

Commit `b0deb8850` installs the multicall desktop's app aliases and native shell
in the boot archive, connects Calculator to an enforced PPC sandbox, selects
`/bin/sh` for Terminal and shows launch failures in a window.

## Verification

The final QEMU mac99/7450 test uses 512 MiB and real USB mouse/keyboard events:

- Files opens and lists the persisted user's home directories.
- Settings opens its Appearance controls.
- Text Editor receives `ppc editor` in its document.
- Calculator receives `2+2` and shows `4` and `2 + 2 = 4` in history.
- Terminal execs `/bin/sh`, receives `uname` and prints `Vinix 0.1-ppc-dev powerpc`.
- Calculator opens and closes eight more times, exceeding the process slot
  count over time and verifying that closed windows and children are reclaimed.
- No child faults, launch failures, framebuffer reopen or console takeover occur.

The app checker verifies process execution, changed content regions, removed
windows and framebuffer ownership; the screenshots were also inspected for the
actual text and calculation result. It does not infer successful computation
from a launch log alone.

The native musl regression independently passes eight fork/exec cycles, transfers
larger than the pipe buffer, shared offsets, descriptor duplication/CLOEXEC,
failed exec, wait status, FPU preservation, exact free-page reclamation, a deliberate
child protection fault, eight PTY lifecycles with CRLF output and the irreversible
sandbox's denied file/process operations. The 128 MiB driver regression passes
nested USB hubs, pointer/keyboard input, framebuffer restoration, DHCP/ARP/ICMP
with independent packet validation and independently checked USB PCM output.
Two-boot storage ABI tests pass with clean ext2 checks.

The fresh account/display test initially failed because the newly working Files
autostart window overlapped System, confusing the existing window locator. The
captured System drag was correct. The fixture now closes Files before that drag;
the historical display checker and its original evidence requirements are unchanged.
The corrected two-boot run passes account hash/permissions, all 56 display
captures, the held drag, Start menu clicks and both filesystem checks.

## Retained evidence

Complete bundles are retained outside Git at
`/Users/pancake/.local/share/vinix-powerpc/audits/apps-20261109`:

- `desktop-build`: compatible V/ui2 sources, desktop source archive and overlay,
  generated code, ELF, logs and checksums.
- `image`, `apps`, `apps-disk.raw`: tested image with exact sources, complete
  application captures, checker and disposable persisted-account disk.
- `runtime`, `drivers`, `storage`: complete independent regression bundles.
- `persistence-initial`: the original overlapping-window fixture failure.
- `persistence-final`: fresh account creation, restart, unchanged 56-frame
  display check, saved hash/permissions and clean filesystem checks.
- `installed-image`: the installed image rebuilt from `b0deb8850`, with exact
  sources and checksums. The user's existing disk was preserved.

The initial runtime/driver/storage and desktop builds used base `c73e93b7f` plus
the exact source snapshots/overlays retained in each bundle. The final app image
uses kernel commit `54683f38a` plus the packaging changes later committed as
`b0deb8850`. Capture manifests retain their original temporary paths. The external
inventory binds every file in the retained copies.
Staging symlinks were materialized in the retained desktop copy; the source
archives, revision records, overlays and generated code remain the build evidence.

Inventory receipt: `apps-20261109.inventory.json` beside the bundle.
SHA-256: `83dba67c96d5cce1f89333b415b6fac3f6b1c257a6c283d945eb5a398ed9f391`.

## Scope

These are native PPC processes running the actual desktop applications. This
qualifies launching, basic interaction and closing those five apps, not every
operation inside them. In particular, Editor's guarded save path still needs
additional filesystem ABI support. Third-party runtimes such as Firefox, Wine
and Steam are not ported. Terminal has the native builtin shell, not Zsh or a
complete POSIX environment. There are eight process slots, four raw PTYs, no
job control, general signal handlers, threads or TCP/Unix sockets. Physical iMac
G4 hardware remains untested. See [port status](powerpc.md) for the current limits.
