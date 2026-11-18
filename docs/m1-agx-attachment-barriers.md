# G13 attachment record barriers

Omarchy's pinned Asahi parser resolves index zero against the corresponding
engine's prior event snapshot. An attachment record can use index zero when
that target is absent. A live target requires a firmware barrier, which the
parser only emits for render or compute commands.
[Asahi snapshot](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L706-L719)
· [Asahi barrier selection](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L859-L897)

Vinix records software index-zero references in the parser and checks them
against the existing prior-event snapshot. Positive barrier indices on
attachment records return `EINVAL`. Accepted software records update
attachment state and emit no firmware barrier. Rejection returns the pins
and any early firmware operation, and preserves the output fences.

Vinix snapshots both engines under one manager lock and validates before VM
binding. Asahi snapshots each engine separately and validates after binding.
Vinix can retain a prior event until host cleanup after hardware completion.

ARM64 and x86-64 builds, 82 V contract files, four host suites and five
pinned source gates passed for `62650ae04` plus the archived patch.
The sanitized ioctl fixture covers 24 combinations of software barrier masks
and prior engine state. It exercises absent, prepared, published and retired
events. Both negative controls triggered the expected assertions. Independent
lifetime review and generated C checks passed, including compatibility with
the archived modern submit signature. The allocation scan reproduced the
same 178 baseline discrepancies.

The audit still reports `not_equivalent`. No M1 hardware tests or reboots
occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-attachment-barriers-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `77da53d7053981501ed846f4fabe887c2612cf64b23734b4662662e6a78450d7` |
| `bundle.tar.gz.inventory.txt` | `bdb500ee73ee4aecd94d669c7b9e8e2ff3bf2580ea6afdff700b52bf8f379d14` |
