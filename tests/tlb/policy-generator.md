# Native TLB host-policy generator

`policy.v` extracts the maintained production functions and writes the exact
independent host adapters and assertions in `policytemplates/`. Those templates
were existing V fixture text inside the old Python script; moving them receives
no algorithm translation credit. The extractor deliberately retains the old
brace-counting behavior. Source files use strict UTF-8 and universal newlines.

The existing `policy.py` entry keeps its disposable directory owner and actual
compiler subprocess, including cleanup on exceptions and interrupts. It runs
the V generator using the repository compiler selector, or an explicitly
qualified `VINIX_TLB_POLICY_GENERATOR`. The generated host fixture retains every
original assertion and uses the production source under this checkout. It
covers PCID ownership, conservative switching, MTRR boundaries, direct-map
splitting, allocation rollback and table/reservation retirement. Host coverage
adds no new physical TLB, kernel build or QEMU evidence.
