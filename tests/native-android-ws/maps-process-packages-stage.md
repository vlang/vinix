# Process package-list image tools

The successor uses the closed `maps-traffic-stats-r1` parent and a freshly
coupled SDK/native pair. The SDK adds only the public instance `pkgList` field;
all three constructors and other methods stay unchanged. The native change
populates a fresh array from the primary package name only in
`ws_running_processes`; `ws_memory_state` remains exact. The qualified native
readback retains all 70 canonical JNI classes and the two historical raw
formatting pairs. TrafficStats remains unchanged.

Nine regular payload files change: JAR, DEX, native DSO, framework/native build
and manifest pairs, headless guest inputs and Maps deployment metadata.
Headless inputs change only JAR/DSO; deployment changes eight inputs and its
framework/native manifest fields. Current metadata records fresh native
coupling; previous provenance remains in the sealed parent chain.

Both full parent audits retain 142 flat inventories in 64+64+14 batches, with
the typed kernel inventory checked separately before and after use. The stage
retains 55 parent stages and 146 dependency seals. All 61 inherited modules and
the frozen kernel are read before cloning the closed parent directly; 62
modules are read back afterward. The original kernel checkpoint retains its
separate 59-module lineage. No kernel patcher or runtime VM is used. The
512 MiB internal charged-write budget, 1 GiB reserve and 125 MiB digest charge
remain enabled.

Qualified source SHA-256:
`2c451380f9d8f6e29c21313a99fa17019889668c29bb32057d215c14a78038d9`.
R2 executable:
`c341a1ea643046cc25adc193871726d72988275805aefa7c20f995f847a67600`.

All 15 required R2 phases passed with guard/child zero, empty reason and
complete cleanup: 69 refusal controls, the full five-bundle SDK/native audit,
helper closures 340/660 with exactly two builder changes, the complete batch
suite through 142, ancestry 55, and discovery of 284 V/408 C inputs. Capture
recorded 850 selected inputs and the explicit 13-source list, including both
repository and frozen copies of the five media sources and native checker.
Independent review matched all 82 frozen sources to the checkout and checked
saved guards, logs and all four emitted C commands.

R1 generation failed on immutable aliases after `base.clone()`. Its complete
tools/controls remain intact. R2 changes only that receipt copy to an
independent JSON tree, plus its explanatory comment. The first R2 batch test
also failed because its required parent directory was absent (guard/child
1/1, complete cleanup); the unchanged binary passed with fresh
`batches-results-r2`. Both failures remain preserved.

Every passing guard kept 600 MiB RSS, 512 MiB observed growth, 1 GiB reserve
and 4 MiB output. Selftest, full audit, helpers and batch execution used
900 seconds; the other eleven phases used 300 seconds. Peak sampled RSS was
332,316,672 bytes. Capture recorded the largest growth, 175,984,640 bytes, and
completed in 2,377 ms. The first fourteen successful shell invocations used
the stricter `limit filesize 16m`. Capture used historical
`ulimit -f 16777216`: 512-byte blocks, or 8 GiB, confirmed by its saved
`filesize 8192MB` record. This permits copying the compiler and clang inputs;
it is not a 16 MiB limit. Other caps stayed unchanged.

With `S=/Users/alex/.local/state/vinix/android`, complete originals are
`S/maps-process-packages-tools-2026-11-04-r1` and matching controls, plus
matching R2 tools/controls. The first aggregate seal stopped at its original
64 MiB shared-growth cap (85,614,592 bytes, guard/child 125/137, complete
cleanup). The successful six-root aggregate also retains that failed seal and
the external command-plan root. Its 18,189-entry manifest is
`S/maps-process-packages-tools-sealed-2026-11-04-r2/sealed/manifest.json`, SHA-256
`c2bfbf96a8d2f8b2331012b6b57f4c71b873c0831dff4291378ae6bcd98e6ef6`.
Seal and separate fresh readback passed in 1,230/690 ms, guard/child zero and
complete cleanup; growth was 6,672,384/37,081,088 bytes under the original
64 MiB allowance. Complete original bundles and historical auditors remain
required. This qualifies host tools; image preparation and ARM/GMS/Maps
execution for this pair remain pending.
