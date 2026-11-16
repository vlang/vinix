# Global parameter queries after device loss

Native GET_PARAMS now returns ENODEV when the manager is in error or stopped
state, before formatting or copying the response. This follows the packaged
[Asahi global-query crash check](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs).
Previously a retained manager could continue returning device information
after failure or shutdown, including successful zero-length queries.

Header validation remains first, followed by manager lookup and a state snapshot
under the manager lock. This shares shutdown's stopped-state serialization;
the helper releases the lock before formatting or checked usercopy. Idle,
starting and running retain existing behavior. A later failure can race with a
successful query, as with the reference's relaxed atomic `is_crashed()` snapshot.
The helper adds no direct allocation, reference transfer or retained borrow.
The fake backend, response formatters and shared copy helper remain unchanged.

Validation passed:

- 32,800 new ASan/UBSan ioctl cases cover all five manager states, zero/short/
  oversized sizes, valid/invalid pointers, unchanged headers/buffers and EINVAL
  header precedence. Deterministic callbacks change state immediately before
  lock acquisition or complete shutdown holding that lock. Every return releases
  it, and response formatting asserts the lock is free.
- The exact prior GET_PARAMS method passes the older copy cases but fails the
  new device-loss case: success instead of ENODEV. Source, adapter, executable
  and rejection are retained.
- Earlier 33,600 parameter-copy cases, BIND/UNBIND/GEM/lifecycle/identity/private
  BO/priority regressions, 167,395 wait/syncobj checks and async, wire, fence,
  VM geometry and production PTE tests pass. The PTE runner uses `--sanitize`;
  focused sanitizer linkage receipts are retained.
- 34 V source/contract/allocation-tool test files, selected primary-source gates
  and the native ARM C storage checker for 107 helpers plus its selftest pass.
  C review confirms rejection before formatting/copying, stack values and a
  released state lock; formatter/copy/fake/shutdown function bodies match the
  prior bundle. No new allocation/free lifetime requires independent review.
- Isolated ARM and clean x86 builds use
  `f336d1977b01117f91e66f8fe3239dfccb4c77b5` plus two overlays:
  `kernel/gpu/agx/file/file.v` and `kernel/gpu/agx/gpu/gpu.v`.
  Both ELF/C pairs and exact inputs are retained. Native AGX is ARM-only;
  x86 uses the repository-supported `LD_X86_64=ld.lld` override.

The unchanged allocation allowance audits **still fail** for baseline and feature,
with identical per-file/kind counts: 383 ARM/289 x86 sites and 828/813 sources.
These compiler counts do not measure native heap rates. No allowance was changed.

Remote heads remain Omarchy `c2e2dd9ad90b5f12a241b2a369e0c58e2412ff05`
and packages `268cc49d44697cf0e7bb627727e3b73df93f4aa2`. Pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The full audit remains
`not_equivalent` (exit 1), while selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-param-device-20261116/`.
Canonical `bundle/` and full archive restoration pass the unchanged complete
typed inventory checker. `completion.txt` binds eleven source paths and two
reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `e6728a291be4432c3639e36fd837666c3cc6e42993eddba094e54bd454529141` |
| `bundle.tar.gz` | `c35fe0cbf1bfe17c17c7525432d3663329b1904b2a619a163e05a8c037c63065` |
| `bundle/vinix-aarch64` | `5190c37826528a1c1ada6088d1dcab14a28df8c36cbd20941339d4388c2bd109` |
| `bundle/vinix-x86_64` | `3242bda93787221daf28b1b61a8649dbfc755bd898bd7caf61a0dfc8377535ae` |

Formatting/usercopy and lock scheduling are injected host services. These checks
do not qualify actual firmware failures, all existing manager state writers,
native multi-CPU visibility or hardware behavior. Modern parameter layout/content,
per-file size bookkeeping and the broader ABI/Mesa, scheduling, memory-accounting,
timeline/container and reclamation gaps remain open. No GPU execution, native
hardware test, Vinix/QEMU boot, reboot, SSH or deployment occurred.
