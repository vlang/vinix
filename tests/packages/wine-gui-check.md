# Signed x86 Wine graphical calculator, 2026-11-12

Source baseline: `02dfc3a7f`, plus this checkpoint's V calculator bindings,
guest/controller, frame codec, independent retainer and evidence controls.
This continues the [private XImage fallback](wine-ximage-check.md).

`run-graphics-x86-03` passes a real signed USER32 calculator on native x86_64
Vinix, under uid/gid 1000. The application has exactly `display` and `process`
permissions. There is no network permission or W+X exception. Its installed
runtime is byte-for-byte the independently admitted console runtime.

The guest creates a real ordinary account and a private authenticated Xvfb
display through the existing X11 authority boundary. Missing authority and a
mismatched display both refuse through the real package launcher. Xvfb runs
as the ordinary account, with TCP and MIT-SHM disabled. The fixture explicitly
stages the native shell Xvfb needs to launch `xkbcomp`, its keyboard data and
miscellaneous server fonts. Those selected inputs and copied bytes are bound
before and after execution.

The real PE creates standard Windows EDIT/BUTTON controls. Its Win64 callback
uses exact 64-bit WPARAM/LPARAM/LRESULT and userdata types. Generated C passes
MinGW's `-Werror=incompatible-pointer-types`. Host arithmetic and fixed-buffer
ownership checks still pass normal, production and ASan/UBSan, including
10,000 zero-retained tracked V cycles and the production arithmetic mutation.
The final `pe-02` receipt admits complete original compiler/MinGW inventories,
source, generated C, executable and literal commands.

The ordinary observer finds the mapped calculator using Wine's UTF-8 X11
title, with legacy title fallback. Only stale-window `BadWindow` races are
nonfatal in this observer; other X11 errors fail. The final absence query
must succeed. No Wine, kernel or package policy error is suppressed.

Actual `XGetImage` pixels produce bounded RGB run-length records with SHA-256
and canonical base64. The two 320x405 PNGs are decoded captures, not recreated
screenshots. XTest pointer motion/press/release enters `13+29=42`; the display
and stdout result change. A standard window-close event produces CLOSED and
natural exit status 0. The mapped calculator disappears. The fixture observes
the ordinary client/server credentials and busy generation lease during the
run, then process retirement, free lease, removed authority and removed socket.
The harness stops QEMU after PASS; guest shutdown and arbitrary detached-server
lease intervals are not qualified.

The independent production retainer admits uninterrupted outcome, exact
ordered markers, both captured frames, bounded PNG headers/dimensions and exact
decoded pixel equality. It rechecks source discovery/build lists, literal V/C
commands, selected inputs, generated artifacts, admitted PE and exact installed
runtime file set/bytes. It independently invokes the console retainer and
compares both controller baseline receipts to that fresh admission.

Publisher admission verifies the actual Ed25519 index signature with a valid
publisher point and matches both installed manifests and publisher identities
to that signed index. This is historical signature/manifest binding. The real
recorded package launch enforces expiry; retention does not confer current
catalog trust or use a synthetic clock in the trust API.

The GUI control collection admits original and copied baselines and passes
all **eleven targeted refusals**. Targeted
controls cover failed/diagnostic outcomes, missing authentication marker,
duplicate result, changed frame hash, changed PNG pixels, missing generated
guest, omitted shell input, resealed PE/runtime bytes and changed publisher
signature. Each refusal must occur at its expected gate with no requested
qualification output. Control copies explicitly borrow unchanged boot evidence
from the complete original run and keep generated payloads private.

Frame codec normal, production and ASan/UBSan checks pass a long-run roundtrip
and eleven malformed record/run/hash refusals. The visual extraction tool can
also decode failed-run frames, but its receipt explicitly grants no launch
qualification. The source snapshot tool now accepts an explicit `--guest-only`
mode for this one-guest harness, preserving the existing two-program default.
The passing GUI run preserves 168 admitted parsed sources and modes; both
native console runs preserve 491. The source snapshot correctly refuses when
the current guest source no longer matches a failed historical run.

Raw evidence remains at `/Users/alex/.cache/vinix-wine-gui-20261112`.
The passing run is `run-graphics-x86-03`; independent qualification and controls
are under `controls-gui-x86-01`. Earlier shell/readiness, missing graphics,
SysV abort, title-lookup, numeric-hostname and stale-window attempts remain
failed evidence. The numeric-hostname mode is explicitly rejected by retention.
The unchanged complete [pinned dependency bundle](wine-forksafe-retention-check.md)
remains required in addition to this workspace and original namespaces.

The GUI control receipt SHA-256 is
`09d3f8d5a87b1b23ba08908fadd0883d8a98126fe0550c225681b58ab82e6dbd`.
Its original baseline qualification receipt SHA-256 is
`fe6f942f370a03fb9694c42d7505ce5cd7e7b64e9f25562abc68deee71903c3c`.
The passing run's `before.png` SHA-256 is
`165363469ecf5786c9954a7478bbb69b04dfe0334d41498c98bc7b99c63bd116`;
`after.png` is
`dccff8c5d61cdb78629faa8489652cb3a245f6eab552217da4a57b438a03a275`.

The ARM graphical attempt remains refused: Wine cannot map its shared
user-data section and Explorer exits before the calculator window is created.
The same mapping error appears in its passing console log. A subsequent
[shared-page diagnostic](wine-shared-pages-check.md) measures the translator's
4 KiB shared-mapping limitations on the 16 KiB ARM host. ARM graphical
startup, desktop embedding, broader applications/exception coverage, complete
corresponding source and redistribution/catalog acceptance remain open.
Section 14 remains unchecked.

During qualification, evidence jobs briefly paused when available storage
dropped below 4 GiB, then resumed. The earlier exception archive and its typed
inventory still match their published SHA-256 values. Its complete redundant
extraction was rechecked successfully, including root mode 755, before removal.
The original exception workspace and complete archive remain retained. This
workspace preserves the recheck and retirement logs.
