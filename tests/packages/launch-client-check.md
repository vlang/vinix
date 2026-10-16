# Isolated-launch client ownership

The ordinary package-launch caller previously retained its authentication
request tables and fields, text copies used for approval checks, a listener
wrapper promoted by V, and a temporary runtime-parent array. These accumulated
on successful handoff and on service/approval refusals.

The caller now owns each outgoing authentication frame and closes it on every
return, erasing and releasing its fields and table. Approval checks borrow
reply bytes directly, including an exact nonce-plus-newline check. Nonce
storage is registered for cleanup before requesting entropy. The synchronous
listener accept uses an explicit stack borrow, and shared runtime-parent
validation iterates a fixed array. The generated C confirms the listener stays
on the stack and that parent validation allocates no array.

The public entry point still uses the fixed root-verified account service.
Only a private helper takes a service path for isolated testing. Argument
validation, ordinary-caller requirement, root-peer authentication, action and
wire formats, literal arguments, three-stream transfer, statuses and failure
diagnostics remain unchanged.

## Measurements

The frozen compiler and the same fixture compare sources from `4f038484b`
with the final implementation. The baseline adds only the private path-taking
test entry point; its production body is otherwise unchanged. Baseline package
socket sources are staged separately to keep the runtime-parent measurement
independent of current sources. Both versions initialize JSON's shared per-type
encoder metadata before forking measured clients. The first unprimed run
retained 481 bytes of that persistent metadata; it does not grow per launch.

Each matched target window repeats five complete calls with owned results and
errors retired, and caller argv outside tracking. Both architectures agree:

| Caller outcome | Previous retained bytes | Final retained bytes |
| --- | ---: | ---: |
| Successful status 0 or 37; bad completion receipt (each) | 2800 | 0 |
| Description denied or malformed (each) | 625 | 0 |
| Account denied | 635 | 0 |
| Password required | 645 | 0 |
| Approval denied, malformed or interrupted (each) | 2620 | 0 |
| Noncanonical approval status | 2635 | 0 |
| Mismatched invitation | 2800 | 0 |
| Unsafe private runtime directory | 1040 | 0 |

An ordinary native caller's unavailable-service window also drops from 625
bytes over five calls to zero. The final fixture repeats all 13 target outcomes
1,000 times and preserves descriptor counts and an empty runtime directory
after each cohort. Native tests repeat local refusal and borrowed reply checks
1,000 times; seven invitation shapes cover missing/extra bytes, NUL, wrong
nonce and CRLF. Root and UID 1000 companion runs cover the identity gate and
unavailable-service cleanup.

The test service is a root process using the real authentication framing and
private socket/descriptor protocols. It verifies the action, empty password,
nonce, literal argv and three CLOEXEC streams, and returns selected completion
receipts. It does not start an application inside the tracked window. Separate
real package scenarios exercise the shipped daemon, session helper and CLI.

These are user allocation measurements, not kernel memory or allocator
residency. Endpoint-heavy cases use batches of 250 calls with seven-second
reclamation waits, following the measured [socket budget](launch-socket-check.md).
There is no production allocation retry.

## Qualification, 2026-10-16

All 28 focused native compile/run checks passed, covering existing protocol/account/
launch/administrator fixtures, tracked ownership, matched unavailable-service
probes, ASan/UBSan local-refusal/reply checks and signed CLI lifecycle/driver
builds. ASan/UBSan disables leak detection; explicit tracking checks allocation
retirement separately. Full root-service/ordinary-client stress and real package
scenarios run on both architectures using the unchanged isolated tracking
kernels from socket qualification. Artifact receipts and guest-initiated QMP
shutdown records are retained alongside source and toolchain pins. Account and
package programs are freshly built; the sandbox binaries are retained
production artifacts, pinned in the isolated-launch receipts.

| Guest check | AArch64 | x86-64 |
| --- | --- | --- |
| Thirteen whole-caller outcomes ×1,000, root/UID 1000 companions | Passed, 373.5 s | Passed, 376.9 s |
| Signed install, isolated account handoff and uninstall | Passed, 10.1 s | Passed, 9.9 s |
| Real isolated CLI, terminal, window and document workflows | Passed, 50.9 s | Passed, 56.7 s |

Durations include TCG and reclamation waits and do not qualify performance.

This closes measured isolated-launch caller storage. Administrator-client
workflow ownership, production publisher/catalog enrollment, advertised foreign
runtime qualification and graphical session/display integration remain broader
roadmap 14 gates.

Repeat the native fixture from the repository root:

```sh
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/launch-client \
  tools/packages/pkglaunch/client_ownership_test.v
/tmp/launch-client
```

The target controller is `tests/packages/launch-client-runtime-check.v`, with
`--arch aarch64|x86_64 --kernel PATH --state-dir NEW_SHORT_DIRECTORY`. Its
guest flag enables the root test service in a disposable image; native tests
skip this branch. The distribution driver includes the tracked native fixture.

- [Native checks](results/2026-10-16/launch-client-host.json), [summary](results/2026-10-16/launch-client-host.txt), [tracked windows](results/2026-10-16/launch-client-memory.txt), [sanitizers](results/2026-10-16/launch-client-asan.txt), [CLI lifecycle](results/2026-10-16/launch-client-cli.txt)
- [Matched measurements](results/2026-10-16/launch-client-comparison.txt), [generated-C review](results/2026-10-16/launch-client-generated-c.txt), [source/toolchain/artifact pins](results/2026-10-16/launch-client-toolchain.json)
- [AArch64 receipt](results/2026-10-16/launch-client-aarch64.json), [serial](results/2026-10-16/launch-client-aarch64.serial.txt), [real package serial](results/2026-10-16/launch-client-aarch64.packages.serial.txt)
- [x86-64 receipt](results/2026-10-16/launch-client-x86_64.json), [serial](results/2026-10-16/launch-client-x86_64.serial.txt), [real package serial](results/2026-10-16/launch-client-x86_64.packages.serial.txt)
- [AArch64 real-isolation receipt](results/2026-10-16/launch-client-aarch64.isolated.json), [serial](results/2026-10-16/launch-client-aarch64.isolated.serial.txt), [x86-64 real-isolation receipt](results/2026-10-16/launch-client-x86_64.isolated.json), [serial](results/2026-10-16/launch-client-x86_64.isolated.serial.txt)
