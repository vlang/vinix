# M1 AGX pre-hardware parity recheck, 2026-11-17

Result: **not_equivalent; 100% parity cannot be signed off**. This is already
demonstrable from host source comparisons. No hardware test or reboot is needed
to expose the incompatible interfaces below. This change updates the audit
record and gap inventory; it changes no kernel or userspace implementation.

The previous session ended at
`c0ef56e6e4d8112b1755969ccac8433cb7bfdc5f`. Its complete logical-queue evidence
bundle passes its original typed-inventory checker again, and its inventory and
archive match the checksums in [the previous report](m1-agx-workqueue-records.md).

## Reference freshness and source scope

Fresh independent checkouts follow remote HEAD, including Omarchy's current
default branch `quattro`, rather than assuming `master` is the default.

| Input | Revision |
| --- | --- |
| Vinix committed source | `c0ef56e6e4d8112b1755969ccac8433cb7bfdc5f` |
| Omarchy remote HEAD | `c3c8acf1ef376d19c400464eab9bc382a8667c6f` |
| Omarchy packages remote HEAD | `538b4824bafe9959c1b7894961ade1dc7d027ec4` |
| Packaged Linux-Aurora | `bed544bdf93a496ebf70ba180923bab12b6e01cf` |
| Packaged Mesa | `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` |
| m1n1 contract reference | `b4654b32941d51afdb77579d63e7cb1aa6c03ecc` |

The current [kernel package](https://github.com/omacom/omarchy-pkgs/blob/538b4824bafe9959c1b7894961ade1dc7d027ec4/pkgbuilds/linux-aurora/PKGBUILD)
and [Mesa package](https://github.com/omacom/omarchy-pkgs/blob/538b4824bafe9959c1b7894961ade1dc7d027ec4/pkgbuilds/mesa-aurora/PKGBUILD)
retain the previous session's kernel/Mesa pins. Reference inputs pass the
existing clean-source and immutable-pin checks. No upstream scripts ran.

The committed audit and all new host fixtures use an isolated Vinix worktree.
A separate audit snapshots the shared working tree. Its inspected Vinix inputs
differ only in `kernel/gpu/agx/event/event.v`, which another session is editing;
the retained diff identifies those bytes. Both audits return exit 1 with all
five protocol gate groups passing. The working event changes receive source
audit coverage here, not a new build or runtime qualification.

## Concrete blockers

The unchanged source auditor compares 17 selected facts: 15 differ and two
match. These counts describe that selection, not whole-driver coverage.

| Contract | Vinix | Packaged Asahi |
| --- | --- | --- |
| Nine common ioctl command numbers | Legacy ordering | Modern ordering |
| GET_PARAMS request | 32 bytes, pointer at 16 | 24 bytes, pointer at 8 |
| SUBMIT request | 56 bytes, separate sync arrays and descriptors | 40 bytes, combined sync array and flat packets |
| VM binding request | 48-byte single operation | 24-byte batch header with pointer/count/stride |
| No-barrier sentinel | `0xffffffff` | `0xffff` |
| VM read/write flags | `1` / `2` | `2` / `4` |

GET_PARAMS's command number and the 64-command submission limit match. Matching
the command number does not repair GET_PARAMS's incompatible request layout.
The retained reports list every compared value and field offset.

Review of the actual registration and submission paths adds these findings:

- `kernel/gpu/agx/driver/driver.v` installs `agx_file.drm_ioctls()`. That table
  in `file/file.v` registers the legacy request types from `kernel/drm/ioctl`.
  Its `ioctl_submit` calls `stage_command_array` and stages separate sync arrays.
  `submission.decode_packet` has no caller elsewhere in the kernel. Its tested
  modern decoder and `kernel/drm/asahi/types.v` are migration components, not
  an exposed modern userspace interface.
- The packaged driver registers 12 Asahi operations, including batched VM_BIND
  and GEM_MADVISE. Vinix registers 11 legacy operations, with single-operation
  GEM_BIND and no GEM_MADVISE handler. The latter is an additional gap beyond
  the auditor's 15 differing selected facts.
- `scripts/build-asahi-aarch64.sh` still selects Mesa 25.0.5, and
  `build-support/check-m1-gpu-image.sh` requires that runtime. Omarchy selects
  Mesa 26.3.0 development source at the pin above. Kernel dispatch, VM/sync
  semantics, userspace and image validation need a coordinated migration.

The existing [remaining-differences table](m1-agx-parity.md#remaining-differences)
also covers VM backing/reservations, complete firmware/default/error-path
comparison, scheduling, lifecycle, telemetry and family support. These remain
different or unverified even if the selected ABI facts are eventually equal.

## Corrections to the older gap inventory

Whole-batch readiness is implemented in `gpu/g13_admission.v` and called from
`file/pending.v`. It checks all three pipes' ring/event credits before granting
admission. `event/workqueue.v` owns fallible overflow blocks beyond the inline
127 tickets. The earlier statements that whole-batch admission was absent and
preparation was capped at 127 were stale; the main table now reflects the code.
The selected source gates check these contracts without certifying the complete
Linux scheduler's policy or native behavior.

The packaged `memacct.rs` explicitly limits admission enforcement and creator
RSS attribution to G17; other GPUs retain accounting totals. Its G17-only limits
must not be presented as missing base-M1 behavior. Accounting, purge advice and
backing/reservation integration remain separate comparisons.

## Fresh host checks and acceptance limits

Passed from the committed source:

- 74 V test files across `m1parity`, `g13contract`, `g13layout` and `asahiuapi`.
- Native-header oracle: all 28 generated UAPI records and every field offset.
- Sanitized flat-packet parser and source-derived packet adapter, including
  16,384 hardware-command conversions, attachments, barriers and timestamps.
- Sanitized production TLB/PTE/root-publication fixture and G13 failure fixture.
- Sanitized logical-queue ownership and complete file-close fixtures, including
  the 143 fake, 51 native logical-queue and 216 G13-record ownership cases.
- Both source audits' five protocol gate groups and the preceding evidence
  bundle's original integrity check.

The initial audit refused an incomplete historical sparse reference checkout
with exit 2. Its diagnostic is retained; a separate complete sparse reference
worktree supplies the passing final gates. No checker or allowance was weakened.

No new kernel build, Vinix/QEMU boot, GPU access, firmware execution, SSH,
deployment or reboot occurred. The previous report retains its ARM/x86 build
results and existing allocation-allowance failures; they are not new results
for the concurrent event edits. Host services and privileged operations remain
injected. Native scheduling, complete leak rates, firmware execution and
compute/render correctness still require hardware acceptance after the offline
implementation gaps are closed.

Complete source snapshots, reports, header oracle, retained test executables,
logs, remote-HEAD receipts and the unchanged evidence checkers are under
`/Users/alex/.local/state/vinix/omarchy-m1-signoff-20261117/bundle/`.
The tracked source symlink and its target are preserved. The existing
symlink-aware archive checker verifies complete restoration and both named
roots, including permissions and logical file bytes. Earlier packaging
diagnostics are retained; no historical check was weakened.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz.inventory.txt` | `e66e5364c61044cceaa4ae867e72e5744106e23cdddfd1e830d7a74574bc7093` |
| `bundle.tar.gz` | `66716262b0958e18261269b5ae9f8ad1e6431569326b2cbafd812f32988dc883` |
