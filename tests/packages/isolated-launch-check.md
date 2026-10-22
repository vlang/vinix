# Package launches from ordinary sessions

Normal login sessions retain account memberships, including an administrator's
admin group. The sandbox cannot clear supplementary groups after privileges have
been dropped. The existing root-desktop `launch_user` handoff already stripped
them; ordinary Software/Start/Open With/terminal callers now use a separate fixed
`packages-launch` account action automatically when memberships remain.

The action uses the new explicit `auth = account` rule: a known ordinary kernel
peer needs no password for this bounded public operation. Greeter/system/unknown
accounts are refused. The helper takes no caller-selected executable, account or
command-line parameters. It accepts only a random 128-bit invitation, connects
to that caller's private runtime with a kernel peer check, and validates the
canonical package launch request independently. Only installed-package launch
modes are accepted; alternate roots, administration, publisher tooling, nested
actions and sandbox/identity flags cannot cross this boundary.

The full request travels separately from the authentication action's small input
field. Its 512 KiB encoded bound preserves the existing 64 KiB literal argument/
document contract, including escaping. Initial packet acquisition has a total
10-second deadline and standard-stream acquisition a 5-second deadline. Missing,
extra or truncated ancillary rights fail; delivered descriptors are closed on
refusal. Explicit 32-bit storage matches the SCM_RIGHTS descriptor ABI on both
targets and the macOS host.

The caller passes exactly its existing stdin/stdout/stderr. The helper duplicates
those descriptors and closes other inherited descriptors before the session
executes. The trusted account database supplies the identity/home; `launch_user`
cannot redirect an ordinary caller. The isolated session checks IDs, zero groups,
capability removal and no_new_privs before re-executing the protected installed
package service. That ordinary service repeats policy, provenance, payload and
generation-lease admission. The completion supervisor also drops root/groups
before waiting. It loads only protected public passwd/group metadata, so no
shadow records enter processes that shed root. A nonce/request-digest/code receipt
and EOF distinguish completion from lost output; application stdout/stderr remain
separate from that receipt.

An empty completion stream reports that the isolated application supervisor
closed before reporting completion. A nonempty malformed receipt still reports
its protocol validation error. `pkglaunch/streams_test.v` checks both cases with
real half-closed sockets; neither can be accepted as a successful application exit.
The tracked ownership suite repeats accepted and refused completion paths 1,000
times each with no retained V allocations or descriptors, including the explicit
synchronous request borrow used by completion validation.

The host protocol fixtures cover every launch mode, literal empty/quoted/UTF-8
arguments, count/byte bounds, a command over the authentication input limit,
escaped 64 KiB input, invalid/noncanonical requests and bound completion codes.
Socket fixtures check separate input/output/error streams, CLOEXEC, missing and
extra rights, and zero extra descriptor retention after refusal. Authentication
fixtures check administrator/standard peers without a password, rejected system/
unknown accounts and extra identity parameters, and unchanged administrator
action restrictions. All shipped actions must parse with their exact fixed shape.

The initial host run completed seven assertion runners, then failed to create
temporary deployment signing files. Its followup resumes the remaining unchanged
assertions in a private fixture namespace, replacing only `os.temp_dir()` expressions;
production sources remain unchanged. The generated V driver and fixture witnesses
are retained. Earlier guest attempts exposed an explicit-width descriptor issue,
a pinned-compiler fixed-array mutation issue, an overlong QMP path and a missing
external bootloader cache. Final inputs use indexed descriptor retirement, a short
state path and a private checksum-pinned bootloader cache. The attempted root
transition is tested as a separate expected sandbox refusal. Further disk-space
failures and an interrupted FFmpeg pin check are retained; that unchanged FFmpeg
runner passes after recovery. Only disposable media from this task's completed
package guests was retired; executable inputs and logs remain available.
Final CLI assertions also catch and verify restored early terminal/alternate-root
diagnostics before delegation. The GCC poll binding uses an explicit pointer cast;
final descriptor sanitizers and both target stages cover that binding.

Both QEMU TCG guests use the production sandbox and retained target kernel;
authentication daemon, account manager and guest init are freshly built for this
change and retained for the final followup. The final public-metadata session
runner and current package service are rebuilt for each guest. Each receipt records nine input/serial
artifact hashes.
The guest signs and installs native CLI/window fixtures, then starts their package
clients as actual administrator and standard accounts with supplementary groups.
It checks caller identity despite a conflicting root-desktop setting, group
removal, inability to regain root, literal arguments, stdin/stdout/stderr, exact
exit status, private-data ownership, native frame/close events, PTY identity/
geometry/input, publisher revocation and payload tamper refusal, audit attribution
and socket cleanup. A root listener planted in the caller's runtime is refused
before launch. Required markers:

- `PACKAGE ISOLATED account-admin-standard own-identity groups-zero literal-argv stdin-stdout-stderr exit-code private-data PASS`
- `PACKAGE ISOLATED native-window terminal-tty geometry input trust-and-payload-refusal audit clean-runtime PASS`

The current fixture/controller also require the document-grant marker described
in [the subsequent regular-file qualification](document-grants-check.md).
The receipts below retain the original isolation/stream qualification; that
followup records its own guest inputs and results.
The current controller also requires the subsequent
[personal-data purge workflow](purge-data-check.md), with separate receipts.
It also requires the subsequent [personal-data inventory](personal-data-check.md)
marker and account-isolation checks; its receipts retain their original scope.

Run the package host driver with the reviewed V compiler and headless UI module:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused \
  -o /tmp/distribution-check tests/packages/distribution-check.v
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 CPATH=/path/to/vinix/desktop \
  VINIX_PACKAGE_TEST_WORK=/path/to/private/work \
  VINIX_PACKAGE_TEST_UI2=/path/to/headless/modules \
  /tmp/distribution-check --direct-tests --cross
```

Build [the V guest controller](isolated-launch-check.v) with the repository and
`tests/hardware-platform` on the module path. Supply a production sandbox for the
target, a retained target kernel, and a new state directory:

```sh
VINIX_HWTEST_TCG=1 V=/path/to/v \
  VINIX_ISOLATED_SANDBOX=/path/to/target/vinix-sandbox \
  VINIX_AMD64_LIMINE_DIR=/path/to/retained/limine \
  /tmp/isolated-launch-check --arch=x86_64 --kernel=/path/to/target/kernel \
  --scenario=packages-isolated-launch --state-dir=/tmp/new-isolated-state
```

Retained results: [AArch64 receipt](results/2026-10-13/isolated-launch-aarch64.json),
[serial](results/2026-10-13/isolated-launch-aarch64.serial.txt),
[QMP](results/2026-10-13/isolated-launch-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-13/isolated-launch-x86_64.json),
[serial](results/2026-10-13/isolated-launch-x86_64.serial.txt),
[QMP](results/2026-10-13/isolated-launch-x86_64.qmp.txt),
[host summary](results/2026-10-13/isolated-launch-host.txt), and
[toolchain/source ledger](results/2026-10-13/isolated-launch-toolchain.json).

This qualifies ordinary-account package launch isolation and stream transport.
A complete graphical login/Software/Start presentation on the guest, terminal
job control/signal forwarding, foreign display/audio brokers, public publisher
enrollment and full advertised catalog migration remain separate release gates.
