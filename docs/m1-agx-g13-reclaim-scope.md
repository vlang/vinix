# What Asahi does on G13 for purging, accounting and power

The parity inventory listed purge, client accounting and power management as
open differences without saying which of them the packaged driver does on G13
(base M1). This page records what it does, from Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`.

## Purge and reclaim: G17 only

`GEM_MADVISE` accepts advice only for VM-private, non-exportable objects, and
returns whether the contents are retained
([file.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L775),
[gem.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gem.rs#L415)).
The shmem helper only records the advice. The one caller that purges is the
VM residency gate
([residency.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu/residency.rs#L465)).
`Vm::with_status` creates that gate
([mmu.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L2195)),
and only G17 calls it
([g17/mod.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/g17/mod.rs#L1590)).
On G13 no object is ever purged and `retained` is always 1.

Vinix applies the same validation and also always reports 1, so the two match
on G13.

## Accounting: totals only, no limits

The admission limits and creator-RSS attribution apply only to G17. Other GPUs
keep the totals, with no limit and no attribution
([memacct.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/memacct.rs#L34-L36)).
On G13 the totals are reported, per client, as `drm-total-system` and
`drm-resident-system` in `/proc/<pid>/fdinfo/<fd>`
([file.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L302)),
and device-wide in a `gpu_memory` sysfs file.

Vinix now reports the per-client lines in `fdinfo`, with two small differences
([fdinfo](m1-agx-fdinfo.md)), and the device totals in `gpu_memory`
([G13 statistics](m1-agx-stats.md)). Both are observable to monitoring tools
only and change no allocation, mapping or rendering result.

## Power management

Apart from the 2 ms idle delay, which Vinix restores, the packaged driver has
no G13 suspend, resume or reset path. Its module parameters set debug
behaviour that is off by default. The defaults that reach G13 firmware or
memory management match in Vinix: soft fault control `0xb`, an eight-block
initial TVB, and no robust context isolation.
[Module parameters](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/asahi_core.rs#L88-L111)
