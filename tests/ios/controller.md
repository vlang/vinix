# iOS VM host controller in V

`run.py` keeps its public entry points and original argument parser. The native
`ioscontroller` module owns the image-header arithmetic, option validation,
build and staging policy, runner marker updates, and final runner invocation.
The shared Package Session ABI borrows the actual Python objects: Path,
compiler, parser, environment and runner callbacks keep their identity,
exceptions, aliases, rich comparisons and evaluation order.

The original hardlink/copy fallback and actual temporary-directory, gzip and
Popen context-manager syntax remain counted Python. Those managers can return a
distinct entered object, suppress failures, or retain an actual saved traceback.
One ordered scope owns the original named values. Publication occurs before
prior expression handles retire; native failure pins and genuine Python handler
frames retain that same scope. Normal cleanup retires original names in their
original order. A suppressed saved failure keeps its scope until its traceback
is cleared.

Original fixtures, shell compiler recipes, independent C/Mach-O programs, feature
marker data and recursive shared codecs are unchanged or receive zero algorithm
translation credit. Fixed recipe and fixture-name data relocated into V are
reported separately from translated Python algorithms. The compiler and real
archive commands still run through their actual Python callables.

Qualification compares frozen original and native host controllers, including
real files, Mach-O headers and partial failures, USTAR/gzip archives, controlled
compiler and VM-runner callbacks, rich and weak ownership cases, retained errors,
closed standard descriptors, EOF and SIGINT cleanup, and cold installers. These
host controls establish no new iOS guest execution, rendering, audio, kernel or
physical hardware result. Arbitrary replacement of translated private helpers,
private bridge frame layout, and exact remaining recursion budget inside
supplied callbacks are outside the compatibility boundary.

A direct invocation uses `python3 tests/ios/run.py` with the original options.
The shared installer finds V through `build-support/find-v.sh`; prepared artifact
overrides are `VINIX_IOS_CONTROLLER_QUERY` and `VINIX_PACKAGE_STORE_LIBRARY`.
Native V host code deliberately uses the bundled GC. Kernel allocator policy
and guest sanitizer settings are unaffected.
