# Native OpenGothic host and guest controller

`run.py` keeps the public Python signatures, globals and argument parser.
The host core owns layer copying, staging, QMP key policy and preparation.
The guest core owns boot configuration, absolute deadlines, menu/world state,
split serial FPS sampling, screenshot policy, performance records and shutdown.
The importer retains actual library objects, context managers, entered values,
paths and exceptions while V borrows them through synchronous callbacks.

Monitor cleanup resolves `stream.close` then `sock.close` at retirement. A
failure in the first close prevents the second call, matching the original.
Context owners clear before exit; fallback cleanup runs after controller reap.
The guarded post-fork initialization additionally retires a child and its PTY
if deadline capture fails. The original leaked both on that error path.
An overridden public `stop` that raises before closing still leaves its master
open, matching the original; that branch has no full-retirement claim.

Qualification uses the complete frozen original, both macOS host architectures
and ARM address/undefined sanitizers, actual PTY and QMP owners, repeat FD checks,
process-group interrupts, forced controller exits and cold compilation.
Prepared four-CPU ARM software guests exercise the menu, world, gameplay key and
screenshot using identical kernel, desktop and engine inputs. This is no fresh
kernel build, physical-device or Venus performance claim.
