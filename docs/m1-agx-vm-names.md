# File-local native AGX VM names

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` reserves a
VM name in the open file's XArray and removes it on `VM_DESTROY`. A queue
holds its own VM reference, so a name can become available before the old
queue retires. Vinix previously exposed the device-wide UAT slot as the
VM ID.
[Asahi VM publication and removal](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L574-L578)
· [VM destroy](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L650-L675)
· [Queue owner](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1322-L1342)

Vinix now selects the lowest available nonzero name under the file lock and
resolves it to the context at ioctl entry. Queue records, mapping ownership,
firmware invalidations and in-flight counts still use the hardware slot.
Private GEM objects still use the non-reused VM identity. VM destruction
hides the public name, and retained work continues to find the old VM by
slot. The tested source is Vinix `5984244ab` plus this patch.

The ASan/UBSan ioctl fixture ran the production VM creation handler through
the registered modern ioctl and exercised both request formats. It checked
two files receiving name 1, allocation of name 2 in one file, reuse of name 1
while its old queue survives, clean allocation failure, private GEM identity,
and mapping and busy checks on the replacement slot. Returning the slot as
the public name failed the fixture. The async and VM allocator suites, 82 V
test files, both kernel builds and five pinned source gates passed. The
allocation scan reproduced the same 178 existing allowance findings.

Hardware slots remain assigned at VM creation, so the device still supports
up to 63 retained user contexts. Asahi's G13 submission path acquires a slot
for the duration of a submission. Full parity and packaged Mesa execution on
physical M1 remain open. No hardware tests or reboots were performed.
[Asahi submission slot acquisition](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L709-L723)

The tested patch, reference sources, native binaries and logs are under
`/Users/alex/.local/state/vinix/omarchy-m1-vm-names-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `780becf6c9e697fe5a01697d327b11e0dbf5b242091fcf6e9cdee63488474b5b` |
| `bundle.tar.gz.inventory.txt` | `2f11ca7d2cd793e9b720a2f265deea50db4a5b8645a58227be47596bfcf52108` |
