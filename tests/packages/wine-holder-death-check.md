# Signed Wine collection after holder death

`wine-native-check --owned-manager --holder-death-probe` builds both the guest
and package frontend with `wine_kernel_lease` and the holder-death fixture.
It uses the existing owned-runtime receipt, local signing key, sandbox,
ordinary UID1000 account, real Win64 collection program and package service.
Owned qualification remains x86_64 only.

The fixture authenticates the caller/holder/SDK manager/server chain. It kills
and reaps the ordinary caller, checks a competing launch's prefix refusal, then
kills and reaps the adopted holder with exact signal status 9. The SDK manager
must be adopted by PID1 while the real Wine server and Windows child stay live
and the generation lease remains busy.

Real remove/rollback transitions make that generation obsolete. Three actual
collection commands must preserve its directory and executable hash while the
holder and caller remain absent and Wine stays alive. The fixture then releases
the Windows child through its normal file handshake. It collects only identified
adopted runtime PIDs: the Win64 child must exit 0, the manager must exit 37, and
generation-matched UID1000 auxiliary processes have their raw statuses recorded.
No fixture signal is sent to those surviving runtime processes. All matching
runtime command lines must disappear and an independent exclusive flock must
succeed before a final real collection removes the obsolete generation.
The active rollback generation must remain available.

The native controller keeps the raw outcome in `guest-outcome.json`. It writes
`result.json` only after native success, captured/generated input verification
and its compiled-source check. Unsupported kernels refuse before Wine launch
at the workload-lease capability gate, retain a failed raw outcome and verified
inputs, and produce no final passing result.

## Focused evidence check

Build `wine-holder-evidence.v` with the repository on V's module path, using
manual memory management:

```text
CHECK controls
CHECK /absolute/native-run positive
CHECK /absolute/unsupported-kernel-run baseline
```

The checker independently rehashes every recorded input and generated artifact,
compares before/after inventories, checks staged package identity and exact
compiler flags, verifies the selected QEMU and 3 GiB memory command, and requires
an uninterrupted outcome within the unchanged 600-second outer bound. Positive
milestones must be exact, unique lines in order. Baseline refusal must name the
capability gate before Wine output and leave no passing result. Production
controls cover missing/duplicate/quoted/reordered milestones, forbidden output,
wrong refusal gates, and missing/duplicate/merged compiler flags.

This is a focused native outcome and recorded-input check. The existing ordinary
Win64 runtime retainer and full original producer/compiler/header provenance
remain separate requirements; this checker does not admit their closure or
replace their refusal controls.

## Qualification checkpoint, 2026-11-15

External state is `/Users/alex/.cache/vwwineholder-20261115-01`, based on
`54f4f8134`. `native-05` passes the signed holder-death run; its two adopted
auxiliary processes both report raw status 0, manager status is 37, the lease
is free, and the obsolete generation is collected. `baseline-02` fails at the
required-capability gate with no final result. Both focused evidence checks and
the production rejection controls pass.
The existing ordinary owned-Wine mode also passes in `owned-regression`, with
its final verified result. The holder-death and ordinary runs take 107.6 and
106.163 seconds respectively, within their unchanged outer bounds.

The first signed attempt, `native-04`, remains failed: it retained the generation
after holder death but its final scan found auxiliary Wine processes that the
fixture had not reaped. The final fixture waits for and collects those admitted
runtime processes explicitly. Earlier build/setup failures and their source
snapshots remain preserved. Prior verdicts are unchanged.

The exact kernel comes from `vwkernellease-20261115-01/candidate-x86-01` and the
owned runtime from `vwcollect-20261113-01/prepared-03`. Those original bundles
remain independently required. Default activation, owned ARM/GUI, full build
admission and broader roadmap 14 acceptance remain open.
