The unchanged C syntax caller in `caller.v` is used by the four native audit
generation cases in `tests/native-linuxkpi-tools/kpihost/audit_fixture.v`.
Run `tests/linuxkpi/audit_generation_test` to exercise them. V owns setup,
the audit API, compiler observation, assertions and scratch retirement.

The cases verify separate private headers on successive invocations, actual
bounds compilation failure before driver compilation, and malformed required
or optional adapter metadata. They use the verified pinned Linux import and
archive with the real C compiler. This removes the old verification mock that
could not cross the native bounds process boundary. Each compiler observer
checks generated adapters, bounds, dependencies and provenance before the
driver compiler executes. Every scratch directory is retired on return.

ARM, x86 and ASan/UBSan qualification is recorded in the native tooling batch.
These checks establish audit orchestration and header generation; they do not
establish full i915 readiness or a running LinuxKPI guest.
