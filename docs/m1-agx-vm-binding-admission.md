# G13 per-VM binding admission

Omarchy's pinned Asahi driver keeps the VM binding mutex held while
acquiring a hardware slot. A submission from a second queue on that VM
waits for the binder before entering the slot allocator.
[Asahi VM binding](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L3296-L3369)

Both G13 submit ABIs now serialize hardware slot admission per VM.
Waiters release the file lock so job retirement and unrelated VMs can
make progress. Closed mappings are rechecked after each wake. The active
binder releases the VM gate with the file lock held. The acquired
hardware slot lease then stays with the existing job preparation path.
Vinix uses interruptible gate waits and the existing 10 ms retry timer.

ARM64 and x86-64 builds, 82 V contract files, eight host suites and five
pinned source gates passed for `dd0e0df72` plus the archived patch. The
host fixture covered both ABIs, two queues sharing a VM, progress on a
separate VM and interruption while waiting on the active binder.
Removing the VM gate triggered the expected negative-control assertion.
The independent lifetime review and generated ARM64 C verified ownership
through the waits and release of the gate on exit.

The embedded gate increases the ARM64 VM context from 448 to 632 bytes.
The allocation scan reproduced the 178 existing allowance discrepancies.
The full source audit still reports `not_equivalent`. M1 firmware and
scheduler behavior remain unverified. No hardware tests or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-vm-binding-admission-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `d27bd36a816b91391dfa1bc118f6405844481128438f698cf4fcb778ea802e2a` |
| `bundle.tar.gz.inventory.txt` | `6ee648686957147148072114fad49edaf0517b0dbbbc5a5c489ff49da59feae0` |
