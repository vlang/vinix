# Software failure details

Software's status area previously displayed only the last three output lines.
Earlier causes and long paths could be clipped, and a catalog reload replaced
the operation output. The new **Failure details** control opens an owned snapshot
of the latest failed service operation from the catalog and administrative forms.

The snapshot records a human operation label, exit status and at most 8 KiB of
retained raw service output. It survives successful reloads and automatic status
refreshes. A later failure replaces it; clearing or closing the window releases
its storage. Progress protocol frames stay outside the human diagnostic output.
Output rollovers, oversized discarded lines and response-size failures are
disclosed. A successful exit with an oversized response is identified as a
response-limit failure, rather than presented as a nonzero service exit.

Preparation preserves complete UTF-8, normalizes CRLF and tabs, and renders
control/invalid bytes as visible hexadecimal escapes. Cached pages wrap at UTF-8
boundaries into fourteen 48-byte lines. Page text and labels are prepared once;
redraw borrows them. Back/Escape preserves the underlying screen and review.
Hidden package actions and text/paste input cannot execute while the viewer is
open. Small windows retain a Back control. The button is available after a worker
finishes, alongside the existing status text.

This is transient service-output presentation. It writes no log file, captures
no password-input buffer, and adds no package mutation, retry or authorization
action. Terminal and native-window streams retain their existing handling.

The maintained Software fixture launches a real child that emits a verification
event, an early failure cause, a long Unicode path, context and retry guidance,
then exits 27. It checks full retained content across pages, progress filtering,
navigation bounds, hidden-action refusal, compact dismissal, catalog reload,
administrative-form access, replacement and clearing. Separate cases cover
bounded tail capture at a UTF-8 boundary, control/invalid bytes, absent output,
discarded oversized lines and response-size failures.

The 1,000-cycle allocation fixture covers capture, page preparation, rendering,
navigation, Back, replacement and clearing. The complete existing Software
functional suite and all eight memory modes run as regressions. Sanitizer runs
use clang ASan/UBSan with leak detection disabled. Both desktop configurations
are typechecked for AArch64 and x86_64 with the current implementation and retained
generated assets; these are not guest graphical executions.

```sh
V=/path/to/pinned/v V_MACOS_V3_NO_FALLBACK=1 \
VINIX_PACKAGE_TEST_UI2=/path/to/headless/modules \
  /path/to/distribution-check --software-only --direct-tests
```

The qualification driver stages the failure viewer/fixture and supplies the
desktop include directory for the heap tracker. Initial attempts exposed a
local variable-name collision, the missing heap include and a private harness's
binary/directory name collision. Their diagnostics are retained. The functional
suite passed before the include correction; final memory and maintained-driver
runs exercise the completed setup.

Public publisher enrollment, catalog migration and ordinary-user graphical
login/runtime acceptance remain separate roadmap gates.

The complete Software functional suite, all eight memory modes and the maintained Software-only driver passed. The new failure-view cycles retained **zero tracked bytes** over 1,000 iterations. The full functional suite and new allocation mode passed ASan/UBSan with leak detection disabled. Both desktop target configurations typechecked successfully.

- [Host, maintained-driver and typecheck results](results/2026-10-14/software-failure-host.txt).
- [Sanitizers](results/2026-10-14/software-failure-asan.txt), [initial attempts](results/2026-10-14/software-failure-attempts.txt).
- [Source/compiler/artifact ledger](results/2026-10-14/software-failure-toolchain.json).
