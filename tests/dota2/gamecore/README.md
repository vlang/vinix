# Dota guest controller

`gamecore` maintains the guest-launch, serial verdict, screenshot, stop/reap,
read-observer and report policies formerly in `tests/dota2/run.py`. The public
Python entry points retain their signatures, parser, imports and caller hooks;
`_game_vm_native.py` binds actual Python library objects to synchronous queries.
Preparation policies already ported in `prepcore` remain there and receive no
additional translation credit.

The importing process owns the PTY child, descriptor, server, worker, file and
context managers. V retains their table identifiers while it orders calls.
Managers and entered values remain distinct. Explicit exit consumes each owner
before cleanup, with emergency recovery after the controller has been reaped.
Error objects and saved traceback properties stay actual caller objects; callbacks
run under the original active cause, including suppression and cleanup failures.
The original final wait after SIGKILL remains nonblocking. Emergency recovery
additionally reaps children and closes descriptors on legacy exceptional stop
paths that skipped retirement; it preserves the original error.

Qualification compares frozen complete workflows, public helpers, cleanup and
context controls on ARM, x86 and ASan/UBSan, and checks real PTY/server/thread/FD
retirement. Prepared ARM guest comparisons retain an existing
`VINIX-DOTA2-PROBE-FAIL` before game launch, with matching disk reads and final
screenshots. This does not establish game execution or rendering, and does not
claim a fresh kernel build. Machine-local immutable receipts are under
`~/.cache/vinix-python-to-v/dota-game-guest-20261009/`.
