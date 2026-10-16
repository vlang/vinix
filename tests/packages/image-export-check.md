# Export reviewed image application deployments

`stage.v --check --export-deployment NEW_FILE` saves the exact canonical format-2
deployment lock produced by the selected signed application requirements. It
requires a file/inline requirement selection and an output outside the image.
The returned JSON includes the saved canonical destination and SHA-256 of the
newline-terminated file, independently of the source requirements digest.

This makes the preflight result usable directly by Software's Deployment form
and the normal deployment CLI. They authenticate the exact pinned manifests with
current enrolled keys and policy and review the complete set, including removals.
Export grants no automatic deployment authority or publisher enrollment.

The [export API](../../tools/packages/pkgcore/image_deployment.v) compares parent
directory identities against the captured image namespace before resolving
aliases. Direct image descendants and aliases/parent traversal into the image
refuse. A path whose filesystem meaning is outside the image remains usable.
Output parents must already exist and pass the normal controlled-parent checks.

The common exclusive metadata writer writes and flushes a private temporary,
publishes a new name at mode 0644 and flushes the same parent descriptor. Existing
files, links, FIFOs, directories and hard links remain intact. Handled failures
before publication retire temporaries; failures afterward explicitly report a
saved file. Retry never replaces a previous/concurrent output.

V builders call `ImageConfiguration.export_applications` or
`export_application_file`. Reports own their returned text; callers free it and
close both image plans. Default report/check methods keep empty output-receipt
fields and create no deployment file. See [SDK contract](../../tools/packages/SDK.md#export-an-image-application-deployment).

## Checks and reproduction

The extended [application fixture](../../tools/packages/pkgcore/image_applications_test.v)
checks:

- Both architectures, exact newline-inclusive output hashes, complete canonical
  format-2 files and inline/file requirements parity. Source and saved digests
  remain independent. Receipts survive closed plans and deleted source files.
- Actual ordinary offline deployment review/apply and integrity verification
  consume the exported file, preserving exact versions, architectures, publishers
  and manifest digests. The staged image and consumer state remain separate.
- Existing file/link/dangling-link/FIFO/directory/hardlink outputs retain their
  identity, mode and contents. Invalid paths, missing/shared-write parents,
  invalid roots and incompatible sets refuse without publishing an output.
- Direct image output, aliases into the image and alias/parent traversal refuse.
  A path using the image's parent to resolve outside succeeds and reports its
  actual canonical destination.
- Injected created/written/flushed/published checkpoints, ENOSPC writes,
  directory flush failures and a concurrent destination writer. Private temporary
  files retire on handled failures; saved-file diagnostics, preservation and
  retry behavior match the actual publication boundary.
- The real CLI on both host configurations: file/inline exports and option
  placement, compiler bypass, repeated-output refusal, missing check/requirements
  context and image-output refusal. Successful export changes no image files.

The existing [atomic new-file fixture](../../tools/packages/pkgcore/atomic_new_test.v)
also checks mode/parent/final substitutions and four concurrent publishers with
one complete winner. Existing signed bundle, target requirements, schema,
deployment, policy, resolver and desktop-cache checks remain included.

The [host driver](image-export-check.v) runs **32 build/run checks**: real stager,
twelve package suites, desktop cache suite, the app/export fixture under
ASan/UBSan, real package CLI and signed CLI maintenance. Sanitizer leak detection
is disabled. There is no whole-plan heap-retention claim.

The [guest controller](image-export-runtime-check.v) builds the actual stager and
nine assertion programs. Both targets must complete all twenty report markers,
all nine processes and guest-initiated shutdown. Each receipt pins thirteen
artifacts: kernel, PID 1, ten binaries and raw serial output. Structural native/
foreign payload fixtures are installed and verified but never executed.

```sh
v -o /tmp/image-export-check tests/packages/image-export-check.v
V=/path/to/reviewed/v /tmp/image-export-check /build/new-image-export-host

v -path '@vlib|@vmodules|.|tests/hardware-platform' \
  -o /tmp/image-export-runtime-check tests/packages/image-export-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/image-export-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-image-export-arm
```

Repeat for `x86_64` with its matching kernel and a fresh state directory. List
mode creates no guest; missing inputs and existing state paths refuse. Cross
compiler/QEMU prerequisites follow the [hardware controller](../hardware-platform/README.md).

## Qualification, 2026-10-16

All **32 host checks passed**, including ASan/UBSan and the concurrent new-file
publisher assertions. Four controller list/input/existing-directory guards
passed. Both fresh guests completed all nine assertion programs and every
required marker, then initiated QMP shutdown: **AArch64 56.0 seconds**,
**x86-64 52.5 seconds**, within the 180-second deadline. Kernel hashes match
the installed-system Software receipts.

- [Host receipt](results/2026-10-16/image-export-host.json),
  [32 checks](results/2026-10-16/image-export-host.txt),
  [export/CLI assertions](results/2026-10-16/image-export-core.txt),
  [atomic publication](results/2026-10-16/image-export-atomic.txt),
  [sanitizer](results/2026-10-16/image-export-asan.txt),
  [cache](results/2026-10-16/image-export-cache.txt) and
  [signed CLI regression](results/2026-10-16/image-export-cli.txt).
- [AArch64 receipt](results/2026-10-16/image-export-aarch64.json),
  [serial](results/2026-10-16/image-export-aarch64.serial.txt) and
  [QMP](results/2026-10-16/image-export-aarch64.qmp.txt).
- [x86-64 receipt](results/2026-10-16/image-export-x86_64.json),
  [serial](results/2026-10-16/image-export-x86_64.serial.txt) and
  [QMP](results/2026-10-16/image-export-x86_64.qmp.txt).
- [Source/toolchain/artifact ledger](results/2026-10-16/image-export-toolchain.json)
  and [V evidence verifier](results/2026-10-16/image-export-retain.v).

The verifier checks all thirteen target artifacts, all twenty report markers,
nine successful processes, guest shutdown, unchanged kernels and host app/export/
atomic/cache markers. The ledger pins the compiler, sources, generated guest C,
host/target binaries, logs and helpers. Product/test sources were unchanged
throughout the final host and guest runs; documentation was finalized afterward.

This increment qualifies explicit release deployment artifacts and existing
reviewed offline maintenance. Full desktop image builds, production publisher
enrollment/catalog migration, graphical login/presentation and broader runtime/
device/crash qualification remain separate roadmap 14 work. Kernel code is
unchanged.
