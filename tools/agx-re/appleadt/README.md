The native V Apple DeviceTree core parses recursive node/property records,
unsigned scalar and region fields, PMGR and PMP records, and the instruction
predicates used by T6050 power recovery. It replaces 23 maintained Python
function implementations (347 original lines, 15,469 original bytes).

`parse_spans` returns only validated integer offsets. `parse` gives native
consumers independent property buffers. The synchronous `adt:` import boundary
borrows inputs until return; JSON and optional decompressed binary results use
the existing explicit release ABI. LZFSE scratch allocations are freed on
rejection, capacity growth and successful copies. Uncompressed Python inputs
retain their original identity through a result flag. Python dataclasses,
callback-based tree iteration and higher recovery families remain counted
compatibility consumers pending their own ports.

Qualification uses the unchanged T6050/T8103 Python fixtures and frozen original
implementations outside the repository. ARM64 and actual x86-64 each pass 23
native tests, 54,690 independent API comparisons and the same 54,690 comparisons
through the production import adapter. Each architecture also passes 8,000
repeated calls across 32 foreign workers: outstanding libc output allocations
return to zero, post-collection retained bytes stay bounded and copied values
survive caller-input mutation. Address/bool/float comparisons, arbitrary manual
record integers, unaligned instruction searches, parse error ordering, DER
truncations and real LZFSE growth/rejection paths are included.

ASan/UBSan cover the native comparison executable and 10,000 direct production
ABI iterations with four foreign threads, including independent releases of
binary and JSON outputs. All 43 existing T6050/T8103 fixture tests remain in the
suite. The real T6050 manifest also matches the frozen original implementation
on both architectures. This host-tool stage changes no kernel or firmware
behavior; these checks make no new physical GPU or kernel-guest claims.
