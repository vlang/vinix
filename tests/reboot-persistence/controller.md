The reboot-persistence controller delegates environment, disk preparation,
command construction, process-group retirement, transcript capture and result
checks to `rebootcore`. The original Python parser, public helper signatures,
PTY fork/exec and ordered `stop_child` then descriptor close remain in Python.
Small tuple/unpack, mapping-display, shared-cell generator and formatting syntax adapters
remain counted Python, with the shared Package Session ABI borrowing actual
caller objects. Named main locals remain owned across all phases in their
original fast-local/cell order; saved errors pin those actual objects into the
adapter traceback before native IDs retire.

Public global lookup uses the running wrapper's builtins table and interned
finite source names. Actual callbacks, ordering, results, aliases, exception
identity/context, manager versus entered-object ownership and cleanup remain
part of the migration contract. Private bridge traceback frame shape and the
interpreter's remaining recursion budget inside arbitrary callbacks are not
claimed identical; arbitrary replacement of private translated helpers is
outside the contract.

The x86 disk recipe, 64 MiB size, ext2 feature flags, one attached disk and
absence of `-no-reboot` are unchanged. Existing fixtures and deadlines stay
independent. Host policy comparisons, actual tar/ext2 preparation and PTY
fixture processes establish no new Vinix kernel, QEMU guest-reset or physical
storage result. Host tools use bundled GC; no kernel allocator claim is made.
