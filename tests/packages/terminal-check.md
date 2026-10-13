# Interactive package terminal qualification

Software offers **Launch in Terminal** for installed applications. The
[SDK command](../../tools/packages/SDK.md#interactive-terminal-execution)
`run-terminal` requires terminal input/output, preserves the normal trust,
policy, payload verification and generation lease, and adds terminal operations
only to this explicit launch. Package metadata and signatures remain unchanged.
The application runs through the configured ordinary account, using literal
arguments and the existing Terminal renderer inside Software.

The shared V [PTY constructor](../../desktop/ptycore/pty.c.v) claims a new
controlling terminal, sets geometry before exec, attaches standard streams and
closes higher descriptors. Linux/Vinix uses `close_range`; host fixtures snapshot
their open `/dev/fd` entries before fork. The production package terminal starts
the trusted service directly, without an intermediary shell. Output is bounded
by the Terminal renderer and its existing scrollback limits.

The maintained checks cover:

- `pkgcore` launch/session tests: terminal-only `tty`/`TERM=linux`, unchanged
  filesystem grants, ordinary-account handoff and literal document arguments.
- CLI regression: redirected terminal launch and alternate installation roots
  are refused, alongside all existing package lifecycle checks.
- [Host PTY check](terminal-check.v): all standard streams are terminals;
  literal arguments/input survive punctuation; initial and changed geometry are
  visible to the child; an inherited descriptor at 200 is closed; the child
  exits and is reaped normally. Invalid argument vectors are refused.
- Software worker fixture: the new action, keyboard routing and exit/return
  gating. Its terminal stub isolates worker behavior; actual Terminal code is
  exercised separately by the desktop launcher fixture.
- Desktop launcher/heap fixture: 50 measured open/render/return/close cycles
  with real Terminal screen/history/arguments and 20 PTY wrapper launches after
  warmup retain zero tracked bytes. Existing package/Software redraw checks run
  alongside them. Host wrapper children may refuse the guest-only `/root`
  working directory; actual application execution is qualified in the guest.
  Another 20 measured real-child exit/poll/close cycles verify output-buffer
  retirement. PTY host checks also pass clang ASan/UBSan with leak detection off.

The real `packages-sqlite` guest scenario uses the same PTY constructor and
production service, account handoff, sandbox and signed SQLite runtime. It
requires an interactive prompt, typed SQL reading the account's database,
resizing, repeated uninstall/reinstall while the session stays alive, collection
retaining that leased generation, `.quit` with successful child exit, and
collection releasing the old generation afterwards. The redirected launch must
fail. Existing WAL, outside-path refusal, library update, rollback and offline
reinstall checks still run. `PACKAGE TERMINAL` and every SQLite marker are
required on both architectures, followed by clean guest poweroff.

```sh
v -no-skip-unused -o /tmp/terminal-check tests/packages/terminal-check.v
/tmp/terminal-check
v -no-skip-unused -o /tmp/package-check tests/packages/distribution-check.v
/tmp/package-check --direct-tests --cross --desktop
```

Use the [SQLite controller commands](sqlite-profile-check.md) with the retained
SQLite inputs and fresh state directories to run the extended guest scenario.
The inputs are the previously qualified unmodified SQLite 3.53.4 source/build
tuple; this increment changes neither SQLite nor the kernel. QEMU TCG and a
600-second functional deadline apply.

The 2026-10-13 [toolchain receipt](results/2026-10-13/terminal-toolchain.json)
records the compiler tuple and separate passing phases: 20 core/CLI runners,
final PTY/sanitizer checks, Software/cross/desktop checks, and the affected final
Terminal heap/poll fixture. The retained [core/CLI log](results/2026-10-13/terminal-core-cli.txt)
is the passing prefix of the initial run, which stopped at the then-failing PTY
fixture; later phases ran separately after fixes. Guest receipts verify all 36
fixture/artifact hashes, every required marker and clean guest poweroff:

- [AArch64 receipt](results/2026-10-13/terminal-aarch64.json) and
  [serial log](results/2026-10-13/terminal-aarch64.serial.txt): 20.8 seconds.
- [x86_64 receipt](results/2026-10-13/terminal-x86_64.json) and
  [serial log](results/2026-10-13/terminal-x86_64.serial.txt): 36.6 seconds.

These checks cover the CLI/PTY contract
and host UI lifetimes, not an end-to-end ordinary-user graphical login/display
broker, performance thresholds, every terminal application or hangup-resistant
background process cleanup. Normal Software close/return waits for application
exit; forced retirement closes the PTY and preserves the lease holder's lifetime
instead of killing it independently of its sandbox child.
