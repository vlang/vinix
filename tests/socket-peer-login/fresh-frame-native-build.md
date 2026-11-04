# Fresh x86 frame native build

The fresh frame build on 2026-11-04 exited zero (`26ef01`) and emitted the
exact native PASS plus the unchanged original controller's x86 PASS markers.
This records kernel compilation and generated-output qualification only;
original full seal/check/root-independent check and guest/performance validation
remain pending at this report's cutoff.

Source preparation/control tools are recorded in component commit
`88e0ffc8aebe982676a73747a22bfe9d33fec8ad` and main integration `1ce0e8656`.
The kernel uses source base `9acefa77` at detached checkout `b262bf48`, with
the four pinned frame files and pristine peer socket sources. There is no ARM
baseline or peer ABI qualification claim.

The qualified native source/binary are
`203100b0be37aae9ba593412da22e30fb7507e5bb6acf7dff7765d974264673c` /
`b9d9e1beb4db7a3f5d7c7d44dc35badef81885ee9cc23b6fda456c990f7fa3f5`.
Its 1,100-second entry-through-final-PASS and five-second final-tail guards
passed. Actual native receipts contain 276 samples, maximum start gap 1,012 ms
and maximum complete window 515 ms. Recorded sample maxima were 89,368 KiB
allocated/103,663 KiB apparent; minimum free space was 9,240,836 KiB.

The unchanged inner make recorded 223,475 ms, exit zero, empty reason and
`leader reaped; group absent`. Its literal 20 arguments matched the reviewed
x86 command. Native direct-controller ECHILD/ESRCH cleanup is separate from
the original controller's ownership of make's group.

The actual generated C passed all 18 mutation refusals; ELF machine and exact
defined symbol checks passed. Original before/after source/tool maps matched
(`67af25011f2f0ab9853add9b4c296396ba0115009382a661f9ea698e482b3738`).
All 79 external fixed-input pins matched before/after
(`1dec10e0746049ac2003c1b01145a8cc0dc987748dac7130f9cb5cf727fe7462`).

The frozen raw root is
`/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026`.

- `build-01/qualification.json`: `3bd6314d714ff13189abac8bedc846961f90bba45c8dab872cbedde8af57c1e0`.
- `build-01/x86_64/bin/vinix`: `41e99c7205fe23dce3c68453c8dc0b64ee101271f793a983d4667db8a69a2556`.
- `build-01/x86_64/obj/blob.c`: `1c7dc1b491c9e8f7debcb8bf68978614d5ca54f923c0c77ca19788fc556c920e`.
- `native-observer-01/run-01/observations.jsonl`: `6e14ed451a342e63b3c55db779c1538fbfc482b6d992800843020dfcfe07ab76`.

All postbuild metadata stays in the adjacent `-seal-01` root. Its
`frame-build-01.handoff.json` has SHA256
`0ebfa7730a08f30575d626aade6ab60ecc1d171601874afbcc5e53ad7eee4c8a`;
`frame-build-01.outer-status.json` has SHA256
`09f216da56abf42582fef5bb3bcbf21f352b3128512848155eabfeaa6409a83e`.
Raw evidence and generated outputs remain outside Git. The raw root is frozen
for separately reserved original audits; no historical frame/atomic evidence
was repaired or replaced.
