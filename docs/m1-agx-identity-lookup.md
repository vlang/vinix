# VM and queue identity lookup errors

Missing VM and queue identities now return `ENOENT` in four native paths,
matching the corresponding lookups in packaged
[Asahi file.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs).
Previously they returned `EINVAL` for otherwise well-formed requests.

| Operation | Missing identity |
| --- | --- |
| VM destruction | VM ID in the current open file |
| Queue creation | Requested VM ID in the current open file |
| Queue destruction | Queue ID in the current open file |
| G13 submission | Queue ID in the current open file |

Submit uses a separate presence flag so a found queue with invalid internal
VM state still returns `EINVAL`. Existing request validation and busy-VM pins
retain `EINVAL` and `EBUSY`. Failed lookup leaves live neighbors untouched,
does not construct resources or publish work, and releases the file lock.
The new submit failure path returns its owned command staging storage.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 9,400 lifecycle ioctl
  checks cover missing, removed and foreign-file names, zero/large IDs,
  malformed requests, busy VM pins, unchanged queue output IDs, constructor
  counters and resource identities. Successful destroy followed by repeated
  destroy checks single teardown; fixture-only logical metadata retirement
  follows removal of every consumer. Borrowed neighbor VM/queue values outlive
  close. Existing close/mapping/private-object/priority/PRIME checks pass.
- 1,400 new real submit-ioctl checks cover absent queues, found queues with
  invalid VM state, staging allocation precedence, complete request cleanup,
  unchanged result bytes and zero published work. Earlier async cases pass.
- All 167,395 earlier wait/syncobj checks and the wire/node/fence sanitizer
  regressions pass. The VM-destroy-before-queue-create lock race now expects
  `ENOENT`, preserving its constructor/refcount checks.
- Two negative runs use exact prior GpuFile source with current fixtures.
  Lifecycle lookup fails with `-22` where `-2` is required; submission fails
  the missing-queue assertion. Raw source, precise single-source adapters,
  executable tests and rejections are retained.
- 26 V test files, selected reference/source gates, the unchanged strict
  checks for 94 live ARM C helpers and negative storage selftests pass.
  A new guard checks all four local/reference lookups and rejects errno
  collapse, lost presence tracking and removed internal-state validation.
- Isolated ARM and clean x86 builds from
  `561e90b4f907dd6dae881edd19837f88e123de5d` plus one overlay,
  `kernel/gpu/agx/file/file.v`. Both ELF/C pairs and exact inputs were retained
  before architecture switch. x86 excludes AGX. Selected audited/support
  sources match the isolated inputs.

Bounded ARM C review confirms a stack boolean and the existing deferred unlock
and storage free on missing-submit-queue failure. Allocation/container-mutation
token counts in all four functions match prior C. The production change adds
no allocation or lifetime. The unchanged global allocation allowance audit
**still fails** on baseline and changed source: identical per-file/per-kind
counts, 383 ARM/289 x86 sites and 827/813 sources. No allowance changed.

Fresh Omarchy `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and packages
`d727707b620c4e6c1c8de0f45c4a843475fa020e` match checked remote heads. Pins
remain Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected source gates pass;
the full audit remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-identity-lookup-20261116/`.
Canonical `bundle/` and a fully restored archive pass the unchanged complete
typed inventory checker. Sources/references, kernels/C, executable tests,
negative runs, raw logs and bounded C review are retained. `completion.txt`
binds eleven source paths and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `5a4002aecf304efa7a0e89a44dbe590f900c1b0ea12c991ca475c7f310da2bef` |
| `bundle.tar.gz` | `6d8a4823fce8ded255f035c6f69059d1542ee7a195603266b708c5d37c14c97c` |
| `bundle/vinix-aarch64` | `29fff77d9645e5e2664e991e348b44f5cf0d5e7df75710d7c7c3a6dd24530672` |
| `bundle/vinix-x86_64` | `98758a5d6484add3193d4f9f63f3e8b70da7b279f0d01b520cec060520c80066` |

This qualifies absent-identity results for otherwise well-formed requests.
Native command allocation/staging still precedes submit queue lookup; the
reference looks up the queue earlier. Complete precedence, GEM-bind missing-VM
semantics, modern ABI/Mesa migration, cumulative timelines, fence containers,
reclamation and hardware qualification remain open. Host fixtures do not
measure native heap usage or multi-CPU races. No Vinix/QEMU boot, GPU execution,
hardware test, reboot, SSH or deployment occurred.
