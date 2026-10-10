# Display-hotplug host controller

`hotplughost/core.v` owns the build recipe, production-source hashes, allocation
import check sequencing, guest entry/link policy, manifest, compiler selection,
flags, fixture execution and report sequencing. The public `build()` and `main()`
signatures remain available to Python callers. The parser, real temporary
owner, original assertions, flag comprehension and map-to-string expressions,
environment expansion and output codec remain Python syntax bindings.

The controller borrows actual caller objects through the committed Package
Session ABI. It captures actual callable targets before their operands, preserves
named local order in an ordered dictionary, and pins assigned locals into the
actual saved failure frame. Temporary manifest and command operands retire in
reverse order on success and error. Native integer truncation, JSON conversion
of policy objects and substitute filesystem APIs are avoided.

The first call builds a private host query and SDK library. The temporary owners
retire at interpreter exit. `VINIX_HOTPLUG_QUERY` and
`VINIX_PACKAGE_STORE_LIBRARY` can select already-built artifacts. Private helper
frames do not promise the original traceback layout or arbitrary callback
recursion budgets near CPython's limit. Original recursive algorithms are not
ported here.

Accounting excludes the unchanged guest entry/header literals, independent
fixtures and retained Python syntax. The original runner is 7,460 bytes;
its replacement plus binding is 4,527 bytes, a net reduction of
2,933 Python bytes. Conservative algorithm credit is 4,721 bytes
across 76 original lines; transferred fixture literals receive zero credit.

Qualification compares original/native real files, ordered callback recipes,
compiler options, partial failure output, supplied object lifetimes and actual
standard descriptors. The unchanged independent display-hotplug fixture passed
through both runners on ARM, x86 and ASan/UBSan. Generated C/header/object
bytes and manifest fields matched; linked Mach-O UUIDs and executable digests
varied. This controller port establishes
no new kernel, QEMU or physical display result.

The shared process transport reserves originally closed standard slots with
CLOEXEC descriptors during private pipe creation and restores those slots before
normal policy callbacks. A reentrant lock protects overlapping spawn windows.
Global POSIX descriptors can still change for a callback inside or overlapping
another allocation window, including a nested constructor proxy; callbacks are
not serialized. This transport receives zero algorithm credit.
