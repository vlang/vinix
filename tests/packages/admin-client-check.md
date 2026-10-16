# Administrator client ownership and refusal diagnostics

The package CLI now calls `pkgadmin.run` for its existing administrator
transport. The module owns both authentication request frames, password input,
nonce scratch and the temporary listener. It compares approval fields as
borrowed bytes and keeps the listener borrow synchronous. The command allowlist,
root-peer checks, password requirement, request bytes and completion rules stay
the same.

An additional refusal bug appeared in full guest calls: the client constructed
an error from an allocated diagnostic and then freed that diagnostic before
returning. The caller could crash while reading the error. Approval checking now
transfers that string to the returned error, independently of the reply that
supplied its bytes. A direct ASan/UBSan fixture retires the reply before checking
each error message.

Password refusal cleanup uses `memset_s` on macOS and `explicit_bzero` on Linux,
including the single-byte input scratch. Successful input transfers to an owned
authentication frame; its exchange wipes fields and its close wipes and frees
them. Nonce generation fills an explicitly owned array. Terminal state uses
stack borrows; prompt, echo restoration, input bounds and EOF behavior retain
their existing implementation.

## Measurement

The baseline is the administrator client in `25a97b08a:tools/packages/main.v`,
extracted by the retained V helper into a private fixture module. Only module
qualifiers, private function names, the authentication socket and password input
descriptor are parameterized. The request decoder, receipts and account tools
are the same for both measurements. Baseline calls repeat five times; final
windows repeat 1,000 times. Encoder type metadata is initialized before tracking.

On macOS, eight password success/refusal cases each retained 360 bytes over five
calls; unavailable authentication retained 625 bytes. Final windows retain zero.
Both target architectures reproduce 300 bytes per five password calls and the
following complete ordinary-client outcomes:

| Outcome | Baseline retained bytes, five calls | Final |
| --- | ---: | --- |
| Success, status 37 | 1545 | 0 |
| Description denied or incomplete | 625 | 0 |
| Account denied | 625 | 0 |
| Throttled or approval denied | 1365 | 0 |
| Approval refusal diagnostic, missing fields or nonzero worker status | SIGSEGV while reading the freed diagnostic | Safe owned error, 0 |
| Other outcomes | See retained serial logs | 0 |

Baseline diagnostic crashes are expected reproductions, each with one request
and recorded SIGSEGV. Remaining baseline outcomes check their exact messages,
return statuses, descriptor counts and empty private runtime. Baseline success
does not mean the unsafe diagnostic paths passed.

The final native fixture has **29 zero-retention windows**:

- Eight password cases: newline/EOF success, the 256-byte boundary, empty input,
  control/DEL refusal and oversized input.
- Unavailable authentication.
- Twelve output cases: diagnostics and progress, oversized diagnostic omission,
  oversized protocol refusal, wrong receipt, missing/truncated completion,
  trailing data/newlines and malformed status.
- Borrowed field/invitation checks with exact lengths and byte mismatches.
- Seven approval cases, including diagnostics checked after reply retirement.

Each target also exercises fourteen outcomes, each with 1,000 complete calls
from UID 1000 against a root fixture service, covering success codes 0/37, description/account/approval
refusals, throttling, malformed approval, interrupted approval, invitation
mismatch, missing receipt and unsafe runtime. Literal reviewed input and password
bytes must arrive intact. Each case requires unchanged descriptor counts and no
runtime socket left behind. Both root and UID 1000 run the local fixtures.

Socket-heavy windows pause for seven seconds between 250-call batches and
between cases, below the unchanged kernel's deferred endpoint budget. This is
fixture pacing, not production retry behavior. These measurements cover live V
user allocations, not allocator residency or kernel memory.

## Qualification

All **34 focused native compile/run checks passed**, covering
account/launch/administrator regressions,
tracked ownership, ASan/UBSan, the signed CLI lifecycle and distribution-driver
build. Sanitizers disable leak detection; tracking measures allocation
retirement separately. Generated-C review checks frame and listener wrappers,
diagnostic ownership and non-elidable credential erasure.

The target controller runs the original and final fixture on AArch64 and x86-64,
then the real authenticated administrator scenario runs with freshly built
package/account tools. All use unchanged isolated socket-qualification kernels;
successful receipts pin the kernel, init, fixtures, tools and serial log and
require guest-initiated QMP shutdown.

| Architecture | Original reproduction | Final ownership | Real authenticated administration |
| --- | --- | --- | --- |
| AArch64 | PASS, three expected diagnostic crashes, 18.7 s | PASS, 72 zero-retention windows, 598.8 s | PASS, 35.8 s |
| x86-64 | PASS, three expected diagnostic crashes, 17.0 s | PASS, 72 zero-retention windows, 604.7 s | PASS, 41.5 s |

The fixture does not qualify pseudo-terminal echo transitions, complete CLI
command dispatch allocation, privileged transaction allocation or a graphical
Software session. Publisher enrollment, catalog migration, graphical
login/display integration and broader foreign-runtime qualification remain
roadmap 14 release gates.

Repeat the local fixture:

```sh
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/admin-client \
  tools/packages/pkgadmin/client_ownership_test.v
/tmp/admin-client
```

The target controller is `tests/packages/admin-client-runtime-check.v` with
`--arch aarch64|x86_64 --kernel PATH --state-dir NEW_SHORT_DIRECTORY`.
`--baseline` requires reconstructing the original module with the retained V
extraction helper. The distribution driver includes the final tracked fixture.

- [Native checks](results/2026-10-16/admin-client-host.txt), [memory](results/2026-10-16/admin-client-memory.txt), [sanitizers](results/2026-10-16/admin-client-asan.txt), [CLI lifecycle](results/2026-10-16/admin-client-cli.txt)
- [Source/toolchain/artifact pins](results/2026-10-16/admin-client-toolchain.json), [generated-C review](results/2026-10-16/admin-client-generated-c.txt), [baseline extraction](results/2026-10-16/admin-client-extraction.v)
- [AArch64 baseline](results/2026-10-16/admin-client-aarch64.baseline.serial.txt), [final](results/2026-10-16/admin-client-aarch64.serial.txt), [real administrator](results/2026-10-16/admin-client-aarch64.admin.serial.txt)
- [x86-64 baseline](results/2026-10-16/admin-client-x86_64.baseline.serial.txt), [final](results/2026-10-16/admin-client-x86_64.serial.txt), [real administrator](results/2026-10-16/admin-client-x86_64.admin.serial.txt)
