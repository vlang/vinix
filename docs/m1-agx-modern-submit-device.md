# G13 modern submit device errors

Omarchy's pinned Asahi G13 path resolves the queue and syncs, takes a
userspace command snapshot, then checks device loss before parsing the
packet. An empty command snapshot reaches that check.
[Asahi staging](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1381-L1454)
· [Asahi device check and parser](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L683-L756)

Vinix now checks the manager after staging and copying, before allocating
parser scratch or decoding. A lost device returns `ENODEV` for empty and
malformed packets. Queue, sync and copy failures still return their staging
errors. An empty buffer uses no packet storage and does not read its user
pointer. The shared submitter checks again before job preparation. Vinix's
queue and VM admission still follow parsing.

ARM64 and x86-64 builds, 82 V contract files, three host suites and five
pinned source gates passed for `70fa433d3` plus the archived patch.
Nineteen sanitizer cases covered the order of queue and sync lookup, copy
faults, packet and parser allocation failures, and shutdown between the
two checks. The exact prior modern submitter failed the lost-device matrix.
Independent review and generated C checks passed. The modern ABI checker
accepts both retained decoder signatures and rejects all six mutations on
the current and historical ARM outputs. The allocation scan reproduced the
same 178 baseline discrepancies.

The audit still reports `not_equivalent`. No M1 hardware tests or reboots
occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-modern-submit-device-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `65584d23d8fee608996252f6d03993cffba81e1ae527099dbfb4bfde3015abd6` |
| `bundle.tar.gz.inventory.txt` | `b9e21f0f70db78cd493058163d864ae1947962fa957f158a894008f5b126b70c` |

## Command-buffer allocation error order

Modern G13 `SUBMIT` reserves storage for a nonempty command buffer after
staging syncs and before validating the command pointer. Allocation failure
returns `ENOMEM` even for a null or wrapping pointer. Once storage is
reserved, a bad pointer returns `EFAULT` and the handler releases the buffer,
staged syncs and queue capture. An empty command buffer still reaches the
device check without an allocation or pointer read.
[Pinned Asahi staging](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1413-L1444)
[Pinned userspace reader](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/rust/kernel/uaccess.rs#L370-L380)

The sanitizer suite passed 400 null and wrapping pointer cases alongside
700 existing submission checks. The prior handler returned `EFAULT` at the
new forced-`ENOMEM` assertion. Both kernel builds, 81 focused V test files,
the firmware reference checks and the AArch64 generated-C checker passed.
The allocation scans reported the same 177 allowlist discrepancies before
and after the change. M1 hardware validation remains open.

The evidence archive contains the validation results for
`b44f7e5304e1fdd1715f9349529e9d5d0aff1303` plus `source.diff`. The original
and restored copies passed archive verification. The archive is at
`/Users/alex/.local/state/vinix/omarchy-m1-submit-buffer-order-20261118.ZcQ5Lt/bundle.tar.gz`
with SHA-256 `bb89d526172fee7cd57f44adc775145dd67b427fe195fc89aefba22e929c7eb9`.
