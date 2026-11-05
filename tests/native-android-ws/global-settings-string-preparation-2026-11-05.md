# Global String-write image preparation passed

The fourth preparation completed under the user-approved outer growth
allowance, using the unchanged [qualified image tools](maps-global-settings-string-stage.md).
Its source revision, recorded in `stage.json`, is
`bb8ffd6e8ac281c10fc15b7b94f47bf9360f2aef`.
[Earlier failed attempts](global-settings-string-preparation-attempt-2026-11-05.md)
and all their controls/seals remain retained.

Using `S=/Users/alex/.local/state/vinix/android`, the prepared image bundle is
`S/maps-global-settings-string-r4`; complete controls and the full log are
`S/maps-global-settings-string-preparation-2026-11-05-r4`.

| Artifact | SHA-256 |
| --- | --- |
| `sha256.json` | `eeb0c745f7a2d2fc18cd946586d1d5853349d52e14480352c2897151625bb892` |
| `stage.json` | `a376b734facb3573111de52250a18dac7ba46ac60f6173cdf54058dc172d9294` |
| `boot.img` | `3c494ecfeaba82881419747efb6ea0f2505da21897bbb87df2abb0a151d3ffee` |
| `efivars.fd` | `d3b3f7afddb44de7020b8544270a67791fca44a48864dcd550cefee633463cbf` |
| `maps-global-settings-string.tar` | `6b16cd37069b663b46bc9fb0a517bf4fae8434a36dfdb17a062bd985ea81b46d` |

Both complete 145-inventory dependency audits passed, preserving the separate
typed kernel inventory. The receipt retains 147 flat and one typed manifest
inputs. All 62 inherited modules and the frozen kernel passed readback before
cloning; all 63 successor modules and the kernel passed afterward. The 62
original/preserved module maps match exactly. The original kernel checkpoint
keeps its separate 59-module lineage; both current kernel digest receipts are
`a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.
Prepared and checkpoint inode modes passed the final preservation checks.

The overlay has exactly six regular files at mode 0644 and nine required
directories at mode 0755. It contains the Global String-write JAR/DEX, framework
build/manifest receipts, headless input receipt and Maps deployment receipt.
Only the JAR pin changes in headless inputs; deployment changes five input
pins and its framework-manifest field. Native bytes and build/manifest
receipts stay inherited. The SDK remains 2,117 canonical classes, with only
Global changed by one added method and zero changed old methods/fields.
Retained-native metadata and compatibility proof preserve all 70 consumed
classes, the original process-package producer/SDK coupling, and empty current
native source/C/header/JNI/export deltas. Independent metadata review confirmed
these fields, module/config counts, payload modes and the small receipt hashes;
it did not replace the complete audits performed by preparation.

Guard/child exited 0/0, with empty reason and complete cleanup in 1,048,501 ms.
Sampled peak RSS was 77,660,160 bytes and observed shared growth was
3,695,067,136 bytes. Limits stayed 600 MiB RSS, 30 minutes, approved 8 GiB outer
growth, 1 GiB reserve and 4 MiB output. No monitoring deadline was relaxed.
The stage's internal 512 MiB budget remained enabled: the receipt records
293,208,064 charged bytes before its final writes; the final `seal-complete`
log records 370,712,576 bytes. This includes 127 MiB in digest-receipt charges.

The complete two-root, 193-entry aggregate seal is
`S/maps-global-settings-string-preparation-sealed-2026-11-05-r1/sealed/manifest.json`,
SHA-256 `d7dc1f8b73ff8044060e49e47fca9dfbee6b3d33bc2901e6ea1df2ef30749d3a`.
Seal and separate fresh readback both passed 0/0, with empty reasons and
complete cleanup. Readback took 3,571 ms, sampled RSS 12,140,544 bytes and
observed shared growth 37,576,704 bytes. Both retained 600 MiB RSS,
900 seconds, approved 512 MiB sealing growth, 1 GiB reserve and 4 MiB output.
Preserve the complete prepared bundle, controls, aggregate and original
dependency bundles. This establishes host preparation and evidence integrity;
clone admission and ARM/GMS/Maps execution remain separate. No guest was
launched by these checks, and CI remains running and untouched.
