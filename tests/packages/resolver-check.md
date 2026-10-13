# Bounded dependency resolution

The consumer and publisher now share an iterative dependency search. A FIFO
constraint worklist, candidate chains by identity, and saved decision cursors
replace recursive calls and copied branch graphs. Backtracking removes only the
assignments and requirements introduced after a decision. Cycles, shared
dependencies, constraints discovered after a selection and isolated runtime
entrypoint fallback retain their behavior. Publisher validation fixes each exact
advertised root, so a working older version cannot hide a broken release.

The resolver enforces 4,096 roots, 32,768 catalog variants, a 4,096-package closure,
128 dependencies per package and a shared 100,000-step search budget. Constraint
processing and candidate checks consume steps, including rejected candidates.
Limit errors propagate directly. The retained baseline reproducer shows that
recursive backtracking previously swallowed the budget error and returned a
missing trusted candidate diagnosis instead.

Equal versions select the host architecture before `all`, independently of input
order, on both supported hosts. Non-upgrade installs still prefer an exact
authenticated installed variant. Repository identity ownership is preserved.
Version comparison uses stack numeric components and retains canonical numeric
boundaries and previous invalid-input behavior.

Host assertions cover the maximum chain, a 512-node graph with 128 dependencies
per node, closure/input/dependency limits, discarded branch requirements, fixed
publisher roots, runtime fallback, architecture ties and installed preference.
An independent exhaustive oracle enumerates absent/old/new choices for four
identities and checks reachability and constraints on 256 generated graphs.
The tracked-heap fixture owns inputs outside the measured interval and frees
returned arrays, error messages and error objects. It measures search work and
diagnostic buffers, rather than full service/configuration validation.

Run the core assertions and allocation fixture with the reviewed compiler:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused -gc none -manualfree \
  -o /tmp/resolver-test tools/packages/pkgcore/resolve_search_test.v
/tmp/resolver-test
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused -gc none -manualfree \
  -d track_heap -o /tmp/resolver-memory tools/packages/pkgcore/resolve_search_test.v
/tmp/resolver-memory
```

The package administrator guest scenario requires the large-chain, dense-cycle
and explicit search-limit marker on both architectures. These are synthetic
public-resolver graph checks followed by the existing signed offline package,
ordinary-account authentication, progress, stale refusal, remove/rollback and
trust/policy workflows. They qualify resolution and service behavior; they do
not qualify a real application catalog or graphical login.

All 27 package-core runners, signed CLI contracts and resolver ASan/UBSan passed.
The 1,000-cycle tracked-heap fixture retained **zero bytes** across successful 256-package chains and missing/policy refusals.

Both QEMU TCG guests passed with clean shutdown and eight verified artifact hashes each: AArch64 **34.437 seconds**, x86_64 **47.918 seconds**. These are functional deadlines, not performance qualification.

- [AArch64 receipt](results/2026-10-13/resolver-aarch64.json), [serial](results/2026-10-13/resolver-aarch64.serial.txt), [QMP](results/2026-10-13/resolver-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/resolver-x86_64.json), [serial](results/2026-10-13/resolver-x86_64.serial.txt), [QMP](results/2026-10-13/resolver-x86_64.qmp.txt).
- [Host checks](results/2026-10-13/resolver-host.txt), [baseline and initial attempts](results/2026-10-13/resolver-attempts.txt), [source/toolchain/artifact ledger](results/2026-10-13/resolver-toolchain.json).
