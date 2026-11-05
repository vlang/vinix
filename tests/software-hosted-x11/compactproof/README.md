# Existing compact compositor admission

This module prepares one future native Launch options scenario using the
already built current compact compositor. It preserves the original five-source
target recipe, the outer four-file compact binding, the original complete
metadata checker, and the separate eleven-source hosted bridge proof. It changes
neither an original bundle nor a historical checker. Guest acceptance is pending.

The fixed compact bundle is
`/Users/alex/Library/Caches/vinix-codex/section14/compact-launch-entry-20261026/targets01/bundle`.
Its manifest SHA-256 is
`965a08c5e673059fcc4f78f2bf45f0c504767ea651dcf01f7d8f0d2b1e1bf337`.
The AArch64 and x86_64 compositors have hashes
`2a20ac2d5fa011a161727e197f502a9c1ec3f5c90a630f9ad018db00b703f22b`
and `acb73c83cc144bf531a2f5413ea30c18927e5d6cbb82dd02671737e88c87b91d`.
Captured and both staged sources match the current compact app, launch,
launch-navigation, package-navigation and hosted launch files. This is scoped
source equality; it does not claim a build of the current whole repository.

The caller uses these APIs:

1. `check_audits(callback) !Audits` passes the unchanged original checker the
   complete original `targets01` and `target-bootstrap01` roots and pinned
   original manifests. The callback runs those exact commands under the existing
   admitted controller/supervisor and returns `CheckRun` with the actual waited
   exit, recorded argv, merged log, and an actual `{"exit_code":0}` receipt.
   The module requires the exact original PASS marker and rechecks all inputs.
2. `import_build(arch, destination, audits)` independently copies the current
   compositor and captured source into a fresh external directory. Failed
   output stays available. The receipt binds this module and the original
   bundle without relabelling its historical production scope.
3. `assembled(desktop, stage, arch, compiler, audits)` validates the imported
   current compositor and separately calls the unchanged `launchproof.assembled`
   on the original hosted import and unchanged historical assembled stage.
   Every returned path must enter the caller's complete before/after input maps.
4. `bridge(arch, audits)` optionally returns the exact bridge from the original
   eleven-source hosted bundle after validating that entire original proof.

After each successful pre/post phase, `audits.write_record(new_path)` exports
strict canonical source/checker/manifest and argv/log/actual-exit paths and
hashes. The native producer must bind both distinct record hashes in its
qualification and full input maps. `recorded_assembled(desktop, stage, arch,
compiler, before_record, before_sha256, after_record, after_sha256)` permits
static retainer replay. Both expected hashes must come from the admitted
producer qualification/input maps. It verifies those hashes and both complete-audit proofs
without launching a checker or imposing a historical monotonic-clock age.
Before and after audit outputs must use distinct paths. This API records prior
producer execution and makes no claim of new complete audit execution. A
resealed caller-supplied record alone is insufficient provenance.

The `Audits` fields are private, an empty token refuses admission, and a token
expires after 30 minutes. Reuse it for static proof calls within one admitted
phase. Obtain a fresh token and record its paths after producers/guest exit;
static `assembled` calls do not themselves rerun expensive original checks.
Audit callback argv/log/exit paths must remain outside every original frozen
root. The callback's production source and actual execution receipts belong to
the caller's qualification; receipt-parser controls alone establish no audit
execution. Resource admission, command deadlines, live log/space observations
and process cleanup remain with the existing controller/supervisor.

The unchanged original `../launchproof/admit.v` is SHA-256
`e8ba120b8b4ac08207bd53be979c5d6ea8085eb11df4689025b107ab0f1aeb94`.
It and its existing tests are copied byte-for-byte from the frozen fixture
worktree `build/package-hosted-launch-options-guest-worktree/tests/software-hosted-x11`.
The unchanged `../optionsfixture/fixture.v` is retained alongside them.
Compile this module with those exact dependencies and the existing `proof`
module; an altered original proof refuses admission.

`controls.v` exercises small external fixtures, including complete hidden-file
inventories, malformed/resealed manifests, aliases, scan limits, audit receipt
and token refusals, and ELF architecture/type/interpreter/segment refusals.
The standalone `check/main.v` accepts `--controls NEW_EXTERNAL_OUTPUT`; its parent
must exist and be canonical. The existing fixed host builder may copy that exact
entry file to its fixed `compactproof-check.v` name. For V's test runner, set
`COMPACTPROOF_TEST_ROOT` to the same kind of fresh output path instead.
All controls use explicit refusals and remain active in production builds.
The recorded-proof parser controls also require the original pinned checker,
checker source and complete manifests to remain available; they read those
small inputs without executing the checker or scanning a retained bundle.
They do not run the original complete audits, import the real compositor, or
boot a guest. Normal and production host results and preserved initial failure
are recorded in [QUALIFICATION.md](QUALIFICATION.md). A later separate
[complete inventory qualification](../compactdiagnosis/QUALIFICATION.md), committed
as `e21fc13ec`, retained actual historical refusals and qualified fresh complete
current inventories with the unchanged original auditor. The historical API
above retains its strict original-manifest checks. An explicit profile to consume
the fresh inventories, real compositor imports, retention integration and native
guest acceptance remain pending.
