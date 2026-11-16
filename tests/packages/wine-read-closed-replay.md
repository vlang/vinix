# Captured host replay with ordinary data-read capabilities

This additive macOS qualifier admits an original format-5 host build with its
exact pinned checker before replaying its captured Mach-O archive:

```
wine-read-closed-replay ORIGINAL_HOST_BUILDER FORMAT5_HOST_BUILD FRESH_OUTPUT
wine-read-closed-controls REPLAY ORIGINAL_HOST_BUILDER FORMAT5_HOST_BUILD FRESH_CONTROLS
```

Build both V tools with the selected compiler, `-backend c -prod -gc none
-manualfree -cflags -fno-lto`, and the repository module path
(`-path '@vlib|/absolute/source/root|@vmodules'`). The replay tool links macOS
`libsandbox`. Its main source and `winereadclosure/policy.v` have embedded source
guards. Preserve the compiled source namespace and complete imported sources
with the executable; use a frozen source snapshot for retained results.

A child applies a kernel sandbox policy before executing LLD in a closed
environment. The policy denies `file-read-data`, then allows exact literals for
each extracted archive member, each pinned ordinary linker image and one derived
control response. The receipt binds every such file's hash. No captured-directory
prefix grants regular-file reads. The projection rejects unsafe, repeated,
relative and unbounded paths rather than interpolating arbitrary policy syntax.

Directory data reads and metadata lookups stay allowed, including searches and
enumeration. Data reads under `/usr/lib` and `/System/Library`, plus the exact
devices `/dev/null`, `/dev/random` and `/dev/urandom`, are explicit exceptions.
OS loader/shared-cache bytes are unqualified. Writes and network access remain
allowed. Helper startup happens before the restriction, and this does not admit
bootstrap or pre-existing process state. The scope is this kernel policy's
ordinary non-system file-data boundary during LLD replay; it is not complete
search, filesystem, ABI or hermetic toolchain admission.

The captured replay must reproduce the original executable, with reported file
loads confined to captured members and observed ordinary image hashes/UUIDs
matching the original host graph. A captured-object read must succeed under the
same policy. An identical object outside the capability set must be unreadable
through its direct path, a private symlink and the Data-volume alias. An installed
SDK stub must also be unreadable. These read refusals require EPERM/EACCES and a
distinct exit status; unrelated failures cannot pass.

A second response substitutes only that external object operand. Its
unrestricted link must reproduce identical bytes. Under restriction the same
response must fail with exactly one `cannot open`/`Operation not permitted`
diagnostic naming that object, exit 1 and no executable. The policy admits the
derived response itself so that this control tests object access. Both successful
outputs retain the original `program` output basename during linking.

The tool records raw commands, environments, exits and actual LLD execution
records/policies. Before publishing `receipt.json` it checks retained capability
bytes, both successful outputs, hidden object/alias and policy, repeats full
original host admission, and rechecks original proof/archive/checker/self hashes
and both embedded source guards. Receipts record local observations, not an
authenticated trust anchor. Preserve the full new directory and original host
bundle with typed inventories outside Git. Current mandatory host receipts keep
their format-5 SDK-denied contract; integrating this broader data-read restriction
remains a separate gate. No guest or default behavior changes.

The production control runner checks nineteen unsafe/list-policy refusals,
deterministic literal projection and system-prefix boundaries, then rejects a
wrong checker, incomplete original bundle and old-format proof without replay
receipts. The replay itself requires all six runtime controls for every host role.
