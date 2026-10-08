# Native private Vulkan staging fixtures

`vulkan-stage-test.py` retains the independent fixture's 18 unittest IDs and
public helper signatures. V owns fixture setup, Debian/tar member construction,
all fake compiler and driver effects, cache mutations and the original
assertions. The importing Python layer binds unittest, tarfile, mock contexts
and the already native production stager. It invokes the actual original
unittest assertions, preserving their messages and deadlines.

The bridge uses an isolated copy of the production transport and the shared
`build-support/native_host.py` compiler owner. Synchronous nested effects keep
the testcase, captured digest function and patched namespace alive. Archive,
patch and assertion managers are registered only after successful entry;
explicit exit clears ownership before calling user cleanup, while an ExitStack
retires outstanding managers after the controller has been reaped. Successful
exit return values are ignored. Error exit preserves exception context and
suppression.

Qualification compares the complete frozen original fixture with this port on
ARM64, actual x86 host ABI and ARM ASan/UBSan. Each comparison records every
produced byte, file mode and symlink target, ordered compiler/build effects,
public unittest assertion calls and final fixture attributes. Both candidates
exercise the same production stager and matching host transcript primitive;
gzip timestamps are pinned identically for reproducible archive comparison.
The original 18-case fixture body remains frozen outside the maintained tree.

These are offline fixtures. Fake Mesa/Venus builds establish staging policy;
they do not establish GPU, guest or physical hardware operation. Imported
archive and HTTP implementations remain library bindings, and no C fixture
migration credit is taken. Cold compilation retains the existing cachekey
unused-import diagnostic and its usual compile overhead.
