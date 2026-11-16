# Timestamp-object validation and lookup order

Native timestamp-object BIND now treats `object_handle` as output-only, checks
offset/range overflow before BO lookup and rejects empty ranges after lookup,
following packaged [Asahi special-object binding](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs).
Previously a nonzero output field was refused, empty ranges hid missing BOs,
and overflow could be hidden by a missing BO.

UNBIND now resolves zero, missing and foreign-file object names to ENOENT before
manager lookup. A found entry stays installed if the native global manager is
unavailable: ENODEV releases the file lock without dropping its mapping owner.
With a manager, removal happens under the file lock, followed by the existing
unmap and BO release after unlocking. BIND acquisition/adoption and failure
release sites remain unchanged; a nonzero initial output field never replaces
an existing mapping. The fake backend is unchanged.

Validation passed:

- 183,400 new ASan/UBSan ioctl cases cover output fields, overflow/alignment,
  empty-range/missing-BO precedence, private/bounds refusal, injected map OOM,
  missing/zero/foreign UNBIND names, manager-unavailable retry, malformed headers,
  ID wrap and live-sibling preservation. Failures preserve outputs and references;
  unbind/close release every fixture BO. The exact prior ioctl method builds
  and fails the missing-zero-name assertion.
- Earlier GET_PARAMS, BIND/UNBIND/GEM/lifecycle/private-BO/identity/priority
  cases, 167,395 wait/syncobj checks and async, wire, fence, VM geometry and
  production PTE regressions pass. PTE tests explicitly use `--sanitize`;
  focused sanitizer linkage receipts are retained.
- 35 V source/contract/allocation-tool test files and selected primary-source
  gates pass. The strict native ARM C checker now covers 108 helpers, including
  the full special-object ioctl, and its selftest passes. Root C review confirms
  unchanged acquisition/release and array push/delete site counts, stack lookup
  records and unlock-before-unmap/release. The global getter and timestamp
  map/unmap C bodies are unchanged; the getter adds no nested lock. No new
  allocation/free or retained-borrow lifetime is introduced.
- Isolated ARM and clean x86 builds use
  `4a9da7085776c0444fef9708ffa04d714733b01f` plus one overlay,
  `kernel/gpu/agx/file/file.v`. Both ELF/C pairs and exact inputs are retained.
  Native AGX is ARM-only; x86 uses `LD_X86_64=ld.lld`.

The unchanged allocation allowance audits **still fail** for baseline and feature,
with identical per-file/kind counts: 383 ARM/289 x86 sites and 828/813 sources.
These compiler counts do not measure native heap rates. No allowance was changed.

Fresh remote heads are Omarchy `37285b5cc4c9679a03df502e1765f0ac566f5fde`
and packages `268cc49d44697cf0e7bb627727e3b73df93f4aa2`. Pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The full audit remains
`not_equivalent` (exit 1), while selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-timestamp-bind-20261116/`.
Canonical `bundle/` and full archive restoration pass the unchanged complete
typed inventory checker. Four packaged source files are retained: file, GPU,
GEM and MMU implementations. The initial unit log before narrowing a reference
selector is diagnostic; final gates/tests use the implemented mapper selector.
`completion.txt` binds nine source paths and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `316ebb596f17baddb830b8f12940b576e90375e8651b11d1b38160ed3e894491` |
| `bundle.tar.gz` | `169f29fa0d212b31b9ce8cfaa025f53e1b1e72b0fa170ee8c75ae905df7cbd2e` |
| `bundle/vinix-aarch64` | `20a3247830ee95b0d2f6dd8cf335c4f1195aa2b6439d85ae2739eaf9c5868919` |
| `bundle/vinix-x86_64` | `347529a03931596eb19729929f6b87f8e1fd2eac3833c1cd29e45aca77eb8286` |

GPU mapping services are injected in host tests. Native physical mapping,
firmware cache handling, metadata admission and in-flight timestamp retention
keep their existing policy and remain unqualified here. Modern ABI/Mesa,
scheduling, memory-accounting, timeline/container and reclamation gaps remain
open. No GPU execution, native hardware test, Vinix/QEMU boot, reboot, SSH or
deployment occurred.
