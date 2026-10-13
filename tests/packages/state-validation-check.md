# Persistent package state qualification

Stored package generations previously checked package/dependency versions but
did not enforce the resolver's runtime-kind and executable-runner requirements.
Generation names used unchecked numeric conversion. Collection could remove
obsolete generations before noticing damaged rollback metadata, and its cache
retention pass decoded that metadata without full validation.

The shared stored-generation reader now requires every state envelope field,
strict JSON types and unambiguous supported keys at every nested record. It
rejects missing or duplicate requested roots, unreachable installed packages,
incompatible dependencies/architectures/provenance, invalid runtime kind/runner
and self/future rollback links. Dependency cycles and explicit data/runtime roots
remain supported. The active pointer and numeric directory names use checked
canonical positive u64 parsing, with no leading-zero aliases or overflow.
State JSON and generation directories must be ordinary filesystem entries.

State-changing transactions admit the next generation identity before removing
abandoned stages. Collection admits both retained metadata records and every
eligible obsolete-generation lease before removal. Leased generations survive;
bad names, symbolic generation directories, missing/symbolic/nonregular leases
and corrupt retained metadata leave the generation/cache contents intact.
Nonblocking lease opens refuse FIFOs without waiting. This admission guarantee
does not make later filesystem removals atomic; ordinary I/O failures can still
leave partial cleanup. Independently decoded state owns its nested allocations;
error cleanup and collection retirement do not free borrowed plan manifests.

The new host assertion runner covers both metadata architectures, u64 boundaries,
required fields, escaped duplicate keys, unknown nested fields, strict types,
root/runtime/history/closure failures, cycles, valid empty generations, pointer
aliases, symlink generations and identity mismatch. Collection assertions retain
the complete cache and obsolete generation through malformed rollback state,
bad names and leases, then verify successful cleanup, active/previous object
retention, abandoned-part removal and held/released application leases.
Generation exhaustion and bad names preserve abandoned-stage sentinels.

The Linux guest injects a data package in place of a runtime in an offline
deployment client's previous state. Rollback and collection both refuse it;
an obsolete generation and unused cache sentinel survive. Restoring the original
metadata permits cleanup, payload verification and rollback. Status, verification,
Software view and collection refuse escaped duplicate state fields. A real
leading-zero activation alias is refused, then the original pointer is restored
and verified. The required marker is
`PACKAGE STATE runtime-closure duplicate-fields canonical-generations collection-preflight restore PASS`.
The rest of the signed Linux install/update/offline/deployment/sandbox workflow
also runs, using fresh service/init/account/session programs and retained kernels
and native sandbox binaries.

Reproduce the host suite and both target service builds with the pinned V compiler:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused \
  -o /tmp/distribution-check tests/packages/distribution-check.v
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 \
  VINIX_PACKAGE_TEST_UI2=/path/to/desktop-assets/modules \
  /tmp/distribution-check --direct-tests --cross
```

Use [the Linux guest controller](linux-runtime-check.v) with matching kernel,
native sandbox and musl copyright inputs, `VINIX_HWTEST_TCG=1`, and a fresh state
directory for each target. The final new state assertion runner also runs under
clang ASan/UBSan with leak detection disabled and undefined behavior fatal.
This checks exercised safety, rather than general decoder leak freedom.

The final 2026-10-13 host run passes 29 assertion runners, SDK context heap,
CLI/PTY/Software fixtures and both target service builds. The extended state
runner passes ASan/UBSan, including a trusted successful launch and explicit
runtime/data roots. Final QEMU TCG runs complete in 92.4 seconds on AArch64 and
141.1 seconds on x86_64, within the 180-second deadline, with clean guest shutdown.

[Host results](results/2026-10-13/state-validation-host.txt) and
[compiler/source/artifact ledger](results/2026-10-13/state-validation-toolchain.json)
retain the passing markers and witnesses. Final guest receipts, serial and QMP:

- [AArch64 receipt](results/2026-10-13/state-validation-aarch64.json),
  [serial](results/2026-10-13/state-validation-aarch64.serial.txt) and
  [QMP](results/2026-10-13/state-validation-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/state-validation-x86_64.json),
  [serial](results/2026-10-13/state-validation-x86_64.serial.txt) and
  [QMP](results/2026-10-13/state-validation-x86_64.qmp.txt).

The ledger pins eleven artifacts per guest and the generated C containing the
final regular-file/nonblocking lease guard. An earlier ARM run passed the state
corruption workflow before that guard was added. A subsequent ARM guest passed
functionally but could not write its receipt after its temporary kernel file
disappeared. The controller now captures staged input hashes before boot; the
receipt-safe ARM rerun supplies the complete-change evidence, and its hashes are
checked against retained inputs. Full logs and artifacts remain under
`build/package-state-validation-work`, including existing generated-C warnings.
This step adds no desktop typecheck/heap, physical-media, power-cut, public
publisher enrollment, graphical broker or broader foreign-runtime qualification.
The wider roadmap acceptance gate remains open.
