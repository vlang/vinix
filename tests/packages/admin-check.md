# Ordinary-account package administration

Software now routes catalog refresh and reviewed administrative changes through
the fixed `packages-change` administrator action when its real effective UID is
ordinary. Its password prompt freezes the existing literal worker arguments,
masks single-line UTF-8 input (256-byte limit), rejects hidden parent actions,
and wipes the credential on submission/cancellation/retirement. An owned copy of
the mask keeps previous UI trees valid after the credential buffer retires.
Cancelling a following repository refresh reports that trust was already saved.

`vinix-package admin [--progress] [--offline] COMMAND ...` sends a canonical
format-1, 4,096-byte request with a fresh 128-bit nonce. Only catalog refresh and
reviewed apply/repository/deployment/policy/offline-export operations are admitted.
The service repeats the exact fingerprint and current trust/policy/state checks.
The current guest/controller also require the subsequent
[organization-policy workflow](policy-ui-check.md). Its public-read,
administrator/standard-role, changed-file refusal and policy-only persistence
checks have separate receipts; existing receipts keep their original scope.
The current controller also requires the public
[complete review-metadata workflow](review-metadata-check.md), covering package,
repository/history and both offline-export envelopes under administrator and
standard accounts without mutation or a password.
The controller additionally requires the
[catalog metadata workflow](view-metadata-check.md), checking complete views,
installed launch declarations and malformed-field refusal under both roles.
Older receipts retain their original scope.
The current controller also requires the
[bounded dependency resolver workflow](resolver-check.md): a 4,096-package chain,
a dense 512-package cyclic graph and an explicit refusal at the global search
limit. These graph checks call the public resolver with synthetic data metadata;
the subsequent signed administrator workflow checks service transactions.
Launches, arbitrary executables, alternate roots, publisher tooling and raw
unreviewed transactions are refused before authentication.

Before sending a password, the client checks the authentication service's kernel
peer UID is root. That service checks the actual caller's administrator account
and own password. Its root action connects only to a listener belonging to that
ordinary UID in the account's existing private runtime. The client accepts only a
root worker. Root parents/private directories, socket permissions, links, request
bounds, canonical shape and completion nonce/digest/exit-code are checked.
Authorization forks the transaction into its own session and clears the inherited
alarm; progress streams separately from the short authentication action.

The worker uses the normal package journal/lock and reports a bound completion
receipt followed by EOF. Lost/mismatched/trailing completion is failure; a missing
receipt tells the operator to check state before retrying. The client closes/unlinks its socket
on success or refusal. Disconnecting the client does not kill an approved root
transaction; SIGPIPE is ignored and its state remains coherent. Approval audit
attributes the request to the real account; the stream reports transaction result.

The qualification covers 36 package assertion runners, SDK allocation checks,
CLI/PTY/Software fixtures, and separate authentication action/root-peer tests.
The full driver completes those host checks; its initial cross-stage failed on an
unused waitpid declaration affecting the pinned compiler's generated OS wrapper.
Removing that declaration restores both service stages, checked separately. The
final desktop run checks both target architectures and the actual launcher
assertions using the retained qualified headless UI overlay/calculator examples.
The launcher fixture explicitly owns/frees its Software object after V promotes
the former local value. Existing compiler/generated-C notices are retained.

Protocol assertions pass ASan/UBSan with leak detection disabled and undefined
behavior fatal. The root-peer host test proves an ordinary fake authentication
listener receives zero bytes and the request secret is wiped. Software's 1,000
prompt/edit/render/wipe cycles retain zero tracked bytes; the SDK/window broker
allocation checks also pass. These tests exercise the actual UI/controller code.

Both QEMU TCG guests freshly build package service, authentication daemon, account
manager, session runner and guest init, retaining the target kernel. Eight input/
serial artifact hashes are recorded per architecture and each VM shuts down
cleanly. The guest uses real ordinary administrator/standard accounts and a signed
offline data package. It checks ordinary read-only review, denied non-admin/bad
password, a planted wrong-UID listener, reviewed install with progress and root
state ownership, stale fingerprint refusal, launch/root/raw-operation refusal,
reviewed remove/rollback/trust revocation, immediate authorized-client disconnect,
coherent verified state, audit attribution, absent passwords in logs/output and
socket cleanup. Required markers:

- `PACKAGE ADMIN ordinary-admin password-required peer-bound reviewed-install progress stale-refusal no-launch PASS`
- `PACKAGE ADMIN reviewed-remove rollback trust-revocation root-state audit no-password-log clean-runtime PASS`

Reproduce host checks with the reviewed V compiler and headless UI module:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused \
  -o /tmp/distribution-check tests/packages/distribution-check.v
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 CPATH=/path/to/vinix/desktop \
  VINIX_PACKAGE_TEST_WORK=/path/to/private/work \
  VINIX_PACKAGE_TEST_UI2=/path/to/headless/modules \
  /tmp/distribution-check --direct-tests --cross
```

Build [the guest controller](admin-check.v) with the repository and
`tests/hardware-platform` on the module path, then use a new state directory:

```sh
VINIX_HWTEST_TCG=1 V=/path/to/v \
  VINIX_AMD64_LIMINE_DIR=/path/to/retained/limine \
  /tmp/admin-check --arch=x86_64 --kernel=/path/to/x86_64/kernel \
  --scenario=packages-admin --state-dir=/tmp/new-admin-state
```

Results: [AArch64 receipt](results/2026-10-13/administrator-aarch64.json),
[serial](results/2026-10-13/administrator-aarch64.serial.txt),
[QMP](results/2026-10-13/administrator-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-13/administrator-x86_64.json),
[serial](results/2026-10-13/administrator-x86_64.serial.txt),
[QMP](results/2026-10-13/administrator-x86_64.qmp.txt),
[host summary](results/2026-10-13/administrator-host.txt) and
[toolchain/source ledger](results/2026-10-13/administrator-toolchain.json).

The guest qualifies authenticated administration and signed package state; it
does not boot a graphical ordinary-user desktop or qualify application-launch
group isolation, physical presentation, foreign graphical/audio brokers, public
publisher enrollment or the remaining catalog migration. Those roadmap acceptance
items remain open.
