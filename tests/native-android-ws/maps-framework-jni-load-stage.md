# Native-only JNI correction image tools

The stager retains the original framework-boot SDK and logical prepared parent,
then adds the qualified native correction from `09182301f`/`6290fc7f8`.
Five regular payload files change: native DSO, headless native build/manifest,
headless guest inputs and Maps deployment metadata. Other deployment inputs,
framework classes and APKs remain unchanged.

The [clean kernel checkpoint](framework-jni-load-kernel-checkpoint.md) supplies
the image with its qualified frozen kernel already installed. The stager checks
complete checkpoint byte/mode inventories and typed kernel provenance before
and after use, reads the kernel/modules independently, and appends the native
overlay: 59 modules become 60. It never invokes a new kernel patcher or reuses
the stopped runtime VM.

All 137 inherited inventories are audited twice in 64+64+9 batches, retaining
the 64-inventory helper bound. The 53-stage ancestry, native/SDK inputs and
141 final dependency seals remain covered. Kernel and inherited module hashes
must remain unchanged.

Source: `f6ab139ecafac44123e6d06f45bed694c4b540814f37aad629a05749cdb39d74`.
Executable: `7b508aa5d4a0da20d8e01ca74f3e2048482bf409691fd5f82b9de712d4a12a6f`.

Host qualification passed: 56 stager refusal controls, complete native audit,
all inventory batching tests including failure/join/repeat checks at 137,
ancestry and helper enumeration. Discovery retained 284 V and 408 C inputs;
the unchanged qualified [capture tool](media-tool-input-capture.v) preserved
726 selected inputs with original/copy/recheck hashes. Independent review
matched all 77 frozen source files, emitted commands and saved guards.

Paths use `S=/Users/alex/.local/state/vinix/android`. Complete tools/sources,
generated projects and controls remain in `maps-framework-jni-load-tools-2026-11-04-r1`
and matching controls. First generation rejected two immutable test-fixture
aliases; R2 uses independent JSON copies. The first batch invocation lacked its
required output-directory environment setting; the corrected invocation passed
with the same test binary. Both failed attempts remain intact.

Positive guards/children exited zero with complete cleanup under original
600 MiB RSS, 300-second, 512 MiB growth, 1 GiB reserve and output/file caps.
The two-root, 16,609-entry seal and fresh readback passed in 2,456/1,066 ms:
`S/maps-framework-jni-load-tools-sealed-2026-11-04-r1/sealed/manifest.json`,
SHA-256 `ef7fb7ef6976a3b4d44451bc8ba197472f4c6e5c7a2ab7399867bd0aaa71aec8`.
Seal/readback retain the original 900-second/64 MiB growth caps. Complete
originals and historical auditors remain required. This qualifies tools;
image preparation and ARM/GMS/Maps execution remain separate work.
