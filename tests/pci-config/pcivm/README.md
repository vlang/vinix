# ARM PCI host observation

`core.v` owns executable lookup, owned-Popen termination and the ARM guest's
serial marker, timeout and final-drain policy. The Python CLI still prepares
and freezes the boot inputs and owns its original outer `try/finally` cleanup.
The controller borrows actual Python objects through the package-store binding;
paths, process objects, clock values, exceptions and callback results are not
converted to serialized substitutes. Digest uses the already qualified WAKE_OP
host implementation.

The counted Python bindings only create the lazy containment generator, provide
storage for the original monitor locals and raise an already constructed actual
exception. The monitor publishes each local before retiring its previous value.
Its storage remains in the original main frame through error handling, process
retirement and final report writes. Expression operands and ignored callback
returns are retired at their original boundaries; completed and interrupted
queries leave the caller's Popen cleanup authoritative.

Qualification compares the frozen original Python monitor and helpers with the
production V query, including full marker combinations, rich callbacks, exact
error identity/context, failure precedence, actual child termination, interruption
and flat descriptor counts. Prepared guest checks exercise host supervision; they
do not establish a fresh kernel build, physical PCI operation or native SMP.
