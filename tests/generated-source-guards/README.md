# Generated-C ownership guards

The native commands in `resource-accounting`, `pagecache` and `procfs-mount`
read production kernel `blob.c` files directly. They retain the original
single-line function selectors, allocation-name word boundaries, stack-slot
counts, loop ordering, procfs template identity, lock/return accounting,
ancestry-before-retarget ordering and persistent receiver checks.

```sh
tests/resource-accounting/check-generated kernel/obj/blob.c
tests/pagecache/check-generated kernel/obj/blob.c
tests/procfs-mount/check-generated kernel/obj/blob.c
```

`guardcore` reads strict UTF-8 with universal newline conversion. It uses the
existing native host-test Unicode word table and the original whitespace set;
matching allocation calls does not depend on a regex runtime. Malformed or
truncated C returns an error. Diagnostics and success lines retain the original
policy messages; Python tracebacks are replaced with concise errors.

Run `v -nocache -cc cc test tests/generated-source-guards/guardcore`.
Set `VINIX_GUARD_TOOLS` to a directory holding `accounting`, `pagecache` and
`procfs` compiled commands to exercise their argument and stream contracts.
These source checks do not build or boot a new kernel and do not establish
new memory-retention measurements.
