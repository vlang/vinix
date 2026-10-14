# Package signing qualification

The package publisher and consumer use the
[pinned MIT-licensed V signing module](../../tools/packages/signing/README.md).
It retains the standard-library arithmetic/encoding from commit
`826e96f56ca12fcb8fd02dfd6edf1551008e62a8` and replaces the private variadic
initialization check with sequential value checks. The old check copied a mutable
receiver pointer as a point value; [the baseline traces](results/2026-10-13/documents-sanitizer.txt)
record a stack-buffer-overflow before policy parsing. No global compiler checkout
or standard library is modified by the package implementation.

A subsequent [field-temporary qualification](signing-repeat-check.md) removes
redundant carry-result assignments in multiplication/squaring. It preserves the
carry operation and returned limbs, measures the allocation reduction, and runs
the reference vectors and repeated publication on both target architectures.
The original results below describe the earlier signing tuple.

The later [table ownership checks](signing-tables-check.md) add explicit table
and digit cleanup, live-allocation budgets and renewed reference/sanitizer/target
qualification. Small scalar/digest/encoding ownership remains separate work.

The signing runner checks published empty, one-byte and two-byte message vectors
from [RFC 8032 section 7.1](https://www.rfc-editor.org/rfc/rfc8032#section-7.1).
Derived public keys and deterministic signatures must equal the reference bytes;
verification must accept those bytes and reject changed signatures/messages,
wrong lengths and a signature with the group order added to S. The guest fixture
checks the same three reference keys/signatures and tamper refusal on both CPUs.
Reference seeds are public test data and are never enrolled as publishers.
The guest reference probe runs in a child that is reaped before the long-lived
init process begins package maintenance; its gc-none allocations retire with
that child. The native host reference runner used about 35 MiB peak RSS.
The [initial run evidence](results/2026-10-13/signing-initial-runs.txt) retains
both reference passes, the later AArch64 allocation failure and x86-64 timeout
when the probe ran inside PID 1, plus the native memory measurement. Moving the
probe into a child bounds its allocation lifetime; subsequent full workflow
results are retained separately below.
The [child-probe retry](results/2026-10-13/signing-probe-timeout.txt) also reached
the original 180-second deadline after the document-validation marker.
Qualification uses a 600-second deadline under the
same QEMU TCG configuration: AArch64 replays the exact built init/root artifacts,
and x86-64 builds the updated child-probe fixture. These runs establish functional
completion, not a performance threshold.
Both completed all required markers and powered off cleanly: AArch64 in 179.6
seconds and x86-64 in 155.1 seconds.

Run `tests/packages/distribution-check.v --direct-tests --cross --desktop` with
the usual staged UI assets and compiler environment. It includes the signing
runner and the existing package/core/protocol/launcher checks. Compile
`tools/packages/signing/signing_test.v`, `tools/packages/pkgcore/policy_test.v`
and `tools/packages/pkgcore/deployment_test.v` with clang,
`-cflags '-fsanitize=address,undefined -fno-omit-frame-pointer'` and
`-ldflags '-fsanitize=address,undefined'`, then run with
`ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1`.
These sanitizer checks qualify exercised memory safety; leak detection is disabled.
The V source regeneration tool's `--check` mode verifies every pinned production
file and rejects extra implementation files or source symlinks.
`tests/packages/signing-source-check.v V_GIT_CHECKOUT WORK_DIRECTORY` exercises
matching files, a changed source, an extra implementation and file/root symlinks
in a disposable copy. Set `V` to the selected compiler when running it.

The 2026-10-13 [host receipt](results/2026-10-13/signing-toolchain.json) records
18 assertion runners, CLI and Software UI/heap checks, both package target builds,
both desktop typechecks, source checks and the three passing sanitizer runners.
An additional `--software-only --cross` run verifies that both binary staging
targets retain the exact MIT notice at
`/usr/share/licenses/vinix-packages/ed25519-MIT.txt`.
The guest receipts retain the new `PACKAGE SIGNING` marker with all existing
package/runtime markers:

- [AArch64 receipt](results/2026-10-13/signing-aarch64.json) and [serial](results/2026-10-13/signing-aarch64.serial.txt).
- [x86_64 receipt](results/2026-10-13/signing-x86_64.json) and [serial](results/2026-10-13/signing-x86_64.serial.txt).

This is evidence for the pinned signing/package tuple. It does not qualify every
compiler, every signing input or all dependent library paths. Catalog migration,
ordinary-user graphical sessions and broader compatibility runtimes remain
separate acceptance work.
