# ARM PCI host observation

`core.v` owns executable lookup, owned-Popen termination and the ARM guest's
serial marker, timeout and final-drain policy. `preparation.v` checks and freezes
the boot inputs, constructs fixture compilation and linking commands, creates
the archive and sparse disk, populates the boot files and publishes the launch
command and input hashes. The Python CLI retains argument validation, its
original preparation-log `run` closure and outer `try/finally` cleanup.
The controller borrows actual Python objects through the package-store binding;
paths, process objects, clock values, exceptions and callback results are not
converted to serialized substitutes. Digest uses the already qualified WAKE_OP
host implementation.

The counted Python bindings only create the lazy containment generator, provide
storage for the original monitor locals, format a prefix with an actual value
and raise an already constructed actual exception. Preparation uses a dictionary
in the original main frame for its named locals. Both native stages publish each
local before retiring its previous value.
The original `copies` closure cell also retains its dictionary through fast-local
retirement; a narrow nonlocal assignment binding preserves that cell's lifetime.
Its storage remains in the original main frame through error handling, process
retirement and final report writes. Expression operands and ignored callback
returns are retired at their original boundaries; completed and interrupted
queries leave the caller's Popen cleanup authoritative.

Qualification compares the frozen original Python preparation, monitor and
helpers with the production V query, including whole preparation failures,
temporary-manager retirement, full marker combinations, rich callbacks, exact
error identity/context, failure precedence, actual child termination, interruption
and flat descriptor counts. Prepared guest checks exercise host supervision; they
do not establish a fresh kernel build, physical PCI operation or native SMP.
