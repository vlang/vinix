# Clean inherited-kernel checkpoint

A fresh unbooted clone of prepared `maps-framework-boot-r1` received the frozen
kernel through the exact qualified archived patcher `864cd44a...`, while its
59-module profile was still unchanged. No stopped runtime image or unqualified
new patcher was reused.

The [collector](framework-jni-load-kernel-checkpoint.v) passed compilation,
37 refusal controls and live verification on its first attempts. It preserves
original bytes/modes and four clone artifacts, verifies the typed kernel build,
patch receipts, 184 command records and 192 outputs, and independently reads
the kernel, 59 modules and Limine from FAT. The original manifest remains at
`prepared-sha256.json`; a new complete inventory covers the checkpoint outputs.

Paths use `S=/Users/alex/.local/state/vinix/android`. Root:
`S/maps-framework-jni-load-kernel-base-2026-11-04-r1`.
Manifest: `fb0b4431319d4905fde60abddfb7dfff18b0bf06ff3de2f6fe21ba6137308d8c`.
Receipt: `26e74c87fa5c4ebebbb752a7d45740d6090559daa356a5bf9d5a9e9ee51012f0`.
Collector source: `7420c02269628a7efa8540a30d286c8a9e8e0c3eecc2d70a76d17efa573719d5`.
Kernel: `a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.

Clone, kernel installation and collector verification passed in
10,592/61,678/31,617 ms with zero guard/child exits and complete cleanup.
Original 600 MiB RSS, 300-second, 1 GiB reserve and output/file caps remain;
clone/kernel use the original 2 GiB growth cap, collector uses 512 MiB.

Complete checkpoint, checkpoint-tools, checkpoint-controls and kernel-controls
roots passed a four-root, 484-entry seal and fresh readback:
`S/framework-jni-load-kernel-sealed-2026-11-04-r1/sealed/manifest.json`, SHA-256
`222fd5838b6390cb4bb68454f08b9c8ae3ef79dabb24a15953fed6d87d7c7c4b`.
Seal/readback passed in 4,809/2,382 ms under the unchanged 64 MiB growth limit.
All originals and historical auditors remain required. This root is closed;
the stager will clone its kernel-installed image and add the native overlay.
