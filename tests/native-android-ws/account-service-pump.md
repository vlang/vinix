# Account service pump failure diagnostics

Commit `9e6a3cb3383323e103913ebdf7ba810550cfe8dd` adds terminal failure
diagnostics to `build-support/android/nativews/account_service.v`, source SHA-256
`0fd27e8edece566671eb824b537858938478300ca16c3572a9aa64bf102cebea`.
The previous pump returned false without reporting a pending Java exception;
Activity launch cleanup could clear it before service teardown.

Each failed pump now writes one bounded numeric record:
`ANDROID-AUTH-PUMP-FAIL stage=N status=N pending=N`. Stages are 1 transport
read, 2 Activity launch, 3 command copy and 4 command dispatch. The record
contains no account, session, request identifier or option content. Successful,
idle and cancellation paths remain silent, and the eight-command pump limit
is unchanged.

When an exception is pending, the helper retains its original local Throwable
reference, calls the existing `ws_failure` with the static marker
`ANDROID-SERVICE-FAIL account pump`, then restores that same Throwable and drops
the local reference. This accounts for `ExceptionDescribe` clearing pending
state. The trace goes to the existing private service log before launch or
shutdown cleanup. If capturing the reference unexpectedly returns null, the
helper preserves pending state and skips the trace.

## Focused host verification

`check-account-service-pump.v` extracts the production helper, pump and
`ws_failure`, instrumenting JNI and transport boundaries. It checks all four
terminal stages with and without pending exceptions, same-Throwable identity
and reference lifetime, diagnostics before launch cleanup, failed-dispatch
command release, silent success/cancellation and the eight-command budget.
Seven compiled mutations are rejected: silent read failure, late launch
reporting, missing command release, lost exception restoration, wrong pending
flag, wrong dispatch stage and missing exception trace.

The final complete probe bundle is
`/Users/alex/.local/state/vinix/android/account-pump-check-build-2026-10-28-r1/probe-r2`.
Its `sha256.json`, SHA-256
`e88be24e0f0a7523af986b9045a0bb39b9e0cf09a9f2f51914040611313d585e`,
inventories retained source inputs, generated model, binary and build/run/mutation
receipts. `evidence.json` records the pre-commit checkout
revision `d6b82d4e2b10c88ea3c8626bf913b02a8cbaa293`; the extracted production
source hash above matches the committed implementation. The checker source
hash is `e5a1e8df76039d7dcf9afed6490c2d671055bcc999e3f0b178a606ba1cbac7bb`.

Under the same external build root, `checker-build-r3.guard.json` and
`checker-run-r2.guard.json` both record exit zero and complete cleanup:

| Command | Guard duration | Sampled process-tree RSS | `/usr/bin/time` maximum RSS |
| --- | ---: | ---: | ---: |
| Checker build | 1.349 s | 326,696,960 bytes | 362,971,136 bytes |
| Probe build and suite | 1.828 s | 182,009,856 bytes | 181,567,488 bytes |

Both used the pinned compiler
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, a 600 MiB RSS ceiling,
300-second deadline, 1 GiB disk reserve and 512 MiB growth ceiling; both time
logs record zero swaps. Earlier failed checker attempts remain retained in
that root. These checks establish host branch and ownership behavior.

## Native producer

The complete current AArch64 JNI provider built and linked with `-Werror` in
`/Users/alex/.local/state/vinix/android/current-native-build-2026-10-28-account-pump-r1`
from commit `9e6a3cb3383323e103913ebdf7ba810550cfe8dd`. Recorded SHA-256 pins:

| Artifact | SHA-256 |
| --- | --- |
| Bundle inventory manifest | `a6a7f207b07083726b9708eea2c67290bcf8baced755651c50bdc205cd7097cd` |
| Native DSO | `cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791` |
| `build.json` | `2802af6636568126359765ac00d09b0771f0b4d22a09c45db55dfe21ba557924` |

The sibling `native-account-pump-build-2026-10-28-r1.json` and `.log` record
exit zero, complete cleanup, 29.291 seconds, 637,255,680 bytes sampled process-tree
RSS, 634,880,000 bytes maximum RSS from `/usr/bin/time`, and zero swaps. The
producer used a 1 GiB RSS ceiling, 300-second deadline, 1 GiB reserve and 2 GiB
growth allowance. Runtime validation of these diagnostics remains pending;
this report establishes no successful Google authentication or Maps rendering.
