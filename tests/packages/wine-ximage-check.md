# Wine private XImage fallback, 2026-11-12

Source baseline: `a8eabd864`, plus this checkpoint's graphics patch,
producer/admission wiring and refusal controls.

A read-only LLDB replay of retained `run-x86-08/boot/test.iso` stops twice at
the pinned kernel's fatal-signal path. The first SIGABRT is Wine startup's
refused network socket. The second is syscall 29 (`shmget` on x86_64), after
the calculator finishes `WM_WINDOWPOSCHANGING` in `ShowWindow`. Its pending
pledge violation has no admitting promise. Production x86 kernel reports go
to the framebuffer; the ordinary observer's status 134 exposed the failure
that was initially mistaken for a stall. The debugger records exact kernel
and ISO hashes, literal commands, selected tool/source hashes before/after,
registers and backtraces. This replay is diagnostic, not launch qualification.

[Wine 9.17's graphics source](https://github.com/wine-mirror/wine/blob/wine-9.17/dlls/winex11.drv/bitblt.c#L1519)
tries a private SysV allocation before its X server attachment. Disabling
MIT-SHM at the server does not prevent that allocation attempt. Failure
already selects Wine's ordinary `XCreateImage` path.

The private runtime now selects that existing fallback. The original
`winex11.so` SHA-256 must be
`f187ce85dbec1a29def88ec5c8725568eb74d75c8512ef90b8b6d90cf104ab97`.
At file/virtual offset `0x7e3a`, the six-byte indirect call to `shmget` becomes
`mov eax,-1; nop`. The surrounding unique instruction sequence is checked in
addition to the complete input hash. The original branch still destroys the
temporary XImage and allocates its normal image buffer. No SysV segment is
created or attached. No kernel, pledge promise, package permission, executable
mapping policy, function size or unwind metadata changes. This local binary
adaptation does not establish corresponding-source or redistribution acceptance.

Normal, production and ASan/UBSan patch checks pass immutable input, unchanged
length, exact six-byte-only output and ten corruption/reapplication refusals.
The production layout checker admits original/copied prepared runtimes and
rejects twelve changed/linked executable controls, now including `winex11.so`.
The producer and independent native retainer embed the patch source, require
the exact ordinary original driver and compare the complete expected patched
driver. A resealed original `shmget` call still refuses.

Fresh `prepared-graphics-{x86,arm}-01` and `native-graphics-{x86,arm}-01`
pass signed console execution and existing Windows API, W^X, vectored
exception, ordinary private prefix/socket, outside-write refusal, natural
exit and lease checks. Every control shard admits original/copied baselines.
The complete collections pass **61 x86 and 70 fork-safe ARM refusals**, with
exact unique assignment across four shards per architecture. Collection
checker baseline/retry and nine refusal controls pass.

Raw evidence remains at `/Users/alex/.cache/vinix-wine-gui-20261112`.
`controls-graphics-x86-coverage.json` SHA-256:
`1cfdc8a3a28798623002c787340273c740fa28780a01671053cd9388eb17d8ee`.
`controls-graphics-arm-coverage.json` SHA-256:
`e49fbfdc9f3f884e9f392fc95a8481ea1f66fa4bcf69340e1c6dd2b63050d6bd`.
Both native parsed-source captures preserve 491 admitted files and modes.
The original namespaces and complete pinned dependency bundle remain required.

The subsequent x86 graphical attempt paints two distinct captured frames,
accepts real pointer clicks producing `13+29=42`, and emits natural CLOSED.
Its observer then fails on an X11 stale-window race, so that run is not a
passing GUI qualification. The ARM attempt fails earlier: Wine cannot map
its shared user-data section and Explorer does not start. That mapping error
also occurs in the passing ARM console log. Broader GUI and desktop/runtime
acceptance remain open; failed attempts are preserved unchanged.
