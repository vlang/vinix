# TrafficStats UID image tools

The SDK-only successor uses the sealed `maps-framework-jni-load-r8` image,
retaining its native library and installed frozen kernel. Six regular payload
files change: framework JAR/DEX, headless framework build/manifest, headless
guest inputs and Maps deployment metadata. Headless inputs change only the JAR;
deployment changes only the five corresponding inputs and framework manifest.

The stager audits all 140 inherited flat inventories twice in 64+64+12 batches.
The exact typed kernel inventory is checked separately before and after use.
It retains 54 stages of ancestry, 143 dependency seals, and all inherited
modules: 60 become 61. Kernel checkpoint validation retains its original
framework-boot parent and 59-module lineage. Media is cloned directly from R8;
no kernel patcher or stopped runtime image is used. The separate 512 MiB
charged write budget, 1 GiB reserve and 123 MiB digest-receipt charge remain.

The retained native producer remains coupled to its original SDK. The pinned
compatibility proof checks all 70 native canonical classes and the two exact
historical raw formatting pairs. Only TrafficStats changes among 2,117 SDK
canonical classes: two changed methods, two added methods and one private
thread-local field. Native code, bindings and exports remain unchanged.

Qualified stager source SHA-256:
`76b78199b6c20862e3f0fd64f7c274335249d6d3186676fbd809265040510468`.
Executable:
`a63309357f0f4811b0972ebb0e5bedb780a3adf41bef7cb1faba42472ee06aa3`.

All 15 qualification phases passed on their first attempts, with guard/child
exit zero and complete cleanup. Checks cover 61 refusal controls, the full
native/SDK audit, helper closures 340/660, all historical and new 140-inventory
batch tests, 54-stage ancestry, and discovery of 284 V and 408 C inputs.
Capture preserved 848 selected inputs with original/copy/recheck hashes.
Independent review matched all 79 frozen source files to the checkout,
including the five changed sources, and checked saved guards, emitted commands
and capture membership. No historical auditor was weakened.

Each qualification guard retains 600 MiB aggregate RSS, 512 MiB observed
growth, 1 GiB reserve, 4 MiB output and the original file cap. Selftest, full
audit, helpers and batch execution use 900 seconds; the other 11 phases use
300 seconds. Peak sampled RSS was 318,734,336 bytes. Capture recorded the
largest growth, 428,699,648 bytes, and completed in 14,408 ms.

With `S=/Users/alex/.local/state/vinix/android`, complete tools, frozen sources,
projects and controls remain at `S/maps-traffic-stats-tools-2026-11-04-r1` and
`S/maps-traffic-stats-controls-2026-11-04-r1`. Their two-root, 17,354-entry seal is
`S/maps-traffic-stats-tools-sealed-2026-11-04-r1/sealed/manifest.json`, SHA-256
`20cc6ef39f611366486b337dd818257518f61ec46f2c31dc035500a2766e5180`.
Seal and separate fresh readback passed in 6,869/2,892 ms with guard/child zero
and complete cleanup; growth was 48,590,848/11,919,360 bytes under their
64 MiB allowance. Both retain the 900-second seal deadline and other limits.
Complete originals and historical auditors remain required. This qualifies
host tools; image preparation and ARM/GMS/Maps execution remain separate work.
