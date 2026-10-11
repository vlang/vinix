# Native N64, PS1 and PS2 test controllers

Run `tests/n64/run`, `tests/ps1/run` or `tests/ps2/run` for the ordinary guest
checks. `--no-build`, `--game`, `--bios` (PS1/PS2), `--prebuilt-init` (N64/PS2),
`--timeout` and `--log` retain their previous roles and defaults. Run the
corresponding `desktop` command with `--desktop` and `--timeout` for pointer
and screenshot checks. Native source and commands are under
`tests/emulator-desktop/emulatorhost` and the six `*-main.v` entrypoints.

The controllers replace seven Python files (50,249 original bytes / 1,097
lines), including their now-unused preparation/QMP adapter. Original bytes
and hashes are frozen outside the checkout in `controller-originals` under
`~/.cache/vinix-python-zero-process-20261011/`. Nothing is excluded or moved
to a maintained archive to reduce the language count.

The native command owner scopes SIGINT/SIGPIPE, compiler groups and scratch
directories. Guest PTYs retain raw transcript bytes and require every feature
and final verdict exactly once. Desktop stdout/stderr share one disk log;
its child owns a separate process group and stdin pipe. The owner closes
descriptors once, joins its direct child and retires descendants on normal
exit, failures and interruption. Existing ABI boot callers retain their
original interface and behavior.

Qualification uses ARM, Rosetta x86 and ARM ASan/UBSan host builds. The host
checker covers CUE/M3U closure/cycles/deduplication, unsafe references, invalid
UTF-8, stat/symlink staging, complete ROM variants, guest verdict gates,
complete RGB crops, P6 boundaries, arbitrary QMP integers, asynchronous events,
malformed replies and EOF. Actual Unix exchanges check input ordering and
measured sleeps. SIGINT interrupts an unanswered command. Resource checks
cover 128 failed socket connections, 64 logged children, all 27 combinations
of open/CLOEXEC/closed standard descriptors and private descendant retirement.
Controlled native processes and full-size screenshots run all three complete
desktop workflows without reducing waits or thresholds. A separate SDK test
checks exact nanosecond metadata on dangling symlinks.

All three ordinary ARM guest regressions passed with the frozen kernel and
current native emulator frontends. N64 passes all ten feature checks, PS1
all five and PS2 all six, plus each final verdict. Their guest workloads were
unchanged. Kernel SHA-256:
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`.
The initially selected older N64 staging frontend fails its clickable-input
guard; that failure is retained separately. The current private frontend
inputs come from the previously qualified native emulator builds.

Additional controls are failures, not passes. Both independently recovered
historical C fixtures fail the unchanged rejected-content explanation check
against the current frontends. Their parser assigns the status buffer from
every label; the newer controller labels overwrite it (N64 prints `C`). The
current V fixtures identify the status label explicitly. This stage establishes
no new equality claim between those historical C fixtures and the current V
workloads. The actual N64 desktop boot reaches the compositor and emulator,
but fails the retained fixed-coordinate start-game check with the current
compositor/frontend. Its logs and PPM captures are retained. Actual desktop
gameplay qualification remains incomplete; controlled orchestration checks
do not replace it.

No Python was run and no kernel was rebuilt. Host sanitizer checks do not
instrument guest kernels or upstream emulator cores. LeakSanitizer is
disabled on macOS. Cold front checks run from `/tmp`; CLI and all qualification
logs use the `controller-` prefix in the cache above.
