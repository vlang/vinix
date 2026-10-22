# Queue-buffer followup validation

Qualified isolated revision: `bd9aa1bc1d04eac1ce31e02ce8914969294566ff`. Exact paths, observed exit statuses and SHA-256 pins are recorded in `qf-validation-summary.json`; native cohort selection and earlier failures are recorded in `qualification-summary.json`.

Both architectures passed all four strict native procfs cohorts with flat slab classes and big pages, zero errors/taint, and held-link/cwd protections. Both Linux reference fixtures passed. All four tracking/production kernel builds and generated-C reviews passed. Source ownership review and an independent reviewer found no new lifetime blocker; the existing timed grace period and permanent mount protections remain limits.

The allocation inventory exits 1 for both baseline and candidate because of the same inherited excess groups. The comparison exits 0 with no new groups. The Q1 missing-annotation inventory failure is preserved separately; final Q2 changes that annotation without changing the built binaries.

ARM and x86 performance audits each passed 36 operations repeated 200 times and four short-program cohorts repeated 300 times, with zero retained bytes per operation/run and no slab deltas. Cache checks passed their declared bounds. Idle/apps and separate fresh actual-drag scenarios completed five-second measurements. Independent full-image review confirmed window movement on both architectures. Input and raw-result audits passed, and strict negative controls were rejected. These are bounded functional/retention checks with cached desktop images, not release-performance or long-soak qualification.

The initial x86 run failed when the cached image lacked curl. Its logs, status 1, receipts, manifest and tooling remain preserved. The full final replay uses the same Q2 kernel and workload with a pinned genuine curl/dependency closure. The initial auditor JSON-filter correction and other host/diagnostic failures remain preserved. No failed run is selected as the final qualification.
