# Generated-C ownership guards

The native commands in `resource-accounting`, `pagecache`, `procfs-mount`,
`procfs-allocs`, `ipv6-multicast`, `socket-io`, `posix-timer` and `process-churn`
read production kernel `blob.c` files directly. They retain each original
function selector, allocation-name word boundaries, stack-slot counts, loop
ordering, procfs template identity, lock/return accounting,
ancestry-before-retarget ordering and persistent receiver checks. The timer
selector accepts multiline arguments and counts raw braces; the other selectors
use the first unindented closing brace. Socket checks also preserve shared flags,
interface-box release and the single shallow transfer of each queued FD list.

```sh
tests/resource-accounting/check-generated kernel/obj/blob.c
tests/pagecache/check-generated kernel/obj/blob.c
tests/procfs-mount/check-generated kernel/obj/blob.c
tests/procfs-allocs/check-generated kernel/obj/blob.c
tests/ipv6-multicast/check-generated kernel/obj/blob.c
tests/socket-io/check-generated kernel/obj/blob.c
tests/posix-timer/check-generated kernel/obj/blob.c
tests/process-churn/check-generated kernel/obj/blob.c --operations
```

`guardcore` reads strict UTF-8 with universal newline conversion. It uses the
existing native host-test Unicode word table and the original whitespace set;
matching allocation calls does not depend on a regex runtime. Malformed or
truncated C returns an error. Diagnostics and success lines retain the original
policy messages and partial stdout before a later failure; Python tracebacks are
replaced with concise errors. Commands accept `--help` and `--` with status 2 for
invalid usage. The timer command now uses this same argument convention instead
of its former positional-only parser. `process-churn` retains its optional
`--operations` checks, including abbreviated options and interspersed arguments.

Run `v -nocache -cc cc test tests/generated-source-guards/guardcore`.
Set `VINIX_GUARD_TOOLS` to a directory holding `accounting`, `pagecache` and
`procfs` compiled commands to exercise their argument and stream contracts.
Set `VINIX_SCRATCH_TOOLS` to a directory with compiled `procfs-scratch`, `ipv6`,
`socket`, `timer` and `churn` commands from the five new entrypoints for their CLI
checks. For example, compile `tests/socket-io/check-generated.v` with
`v -nocache -cc cc -o "$VINIX_SCRATCH_TOOLS/socket"`; the folder must already
exist. The fixtures cover all checked functions and mutation failures, Unicode
boundaries/whitespace, multiline signatures, nested and truncated braces,
stack placement, descriptor transfer backreferences, formatter/select/fork
ownership, UTF-8 errors, CRLF/CR normalization and optional operations output.
These source checks do not build or boot a new kernel and do not establish
new memory-retention measurements.
