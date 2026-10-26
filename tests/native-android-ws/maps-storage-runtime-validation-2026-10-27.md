# Protected-storage Maps diagnostic: closed UART audit

The credential-free diagnostic reached GMS service construction, but service
binding remained incomplete and Maps displayed that its Android APK had exited.
`gms-exceptions.png` shows service `onCreate`/`onStartCommand`,
`ANDROID-SERVICE-FAIL service binding incomplete`, and a device-protected Chimera
configuration path. `service-construction-catch.png` shows failure to obtain
storage information during GMS application attachment. These observations prove
neither a working Maps session nor Google account authentication.

The raw UART export is invalid. The unchanged strict collector rejects the
closed log before creating an imported result directory. No archive was
reconstructed, normalized or imported; the collector was not relaxed.

## Inputs and lifecycle

External paths are under `/Users/alex/.local/state/vinix/android/`.
The immutable producer `maps-storage-r2` records stager source revision
`3e0291c128a18795c9cab0746f88385ac62b973e` (implementation `df1592ccf`,
receipt-parent fix `3e0291c12`). Its complete historical manifest SHA-256 is
`9d99d57603b86e1408980a8cf982bb0f3dabfcef789eef58e5c012c986472562`.
The diagnostic intentionally couples the protected-storage framework and JNI;
it is separate from the production stager. The exact clone `maps-storage-vm-r1`
was subsequently patched with the retained PIDFD kernel.

Owned QEMU PID 87284 started at 2026-10-26 22:59:53 UTC. The identity-checked
SIGTERM request was recorded at 23:09:57 UTC. `qemu.log` records signal 15
termination; `gone.json` records an absent PID in one subsequent `ps` snapshot.
These establish observed host cleanup; no wait/reaped QEMU exit-code receipt is
retained. This audit issued no VM launch, signal or QMP command.

| Receipt, relative to VM root except clone | SHA-256 |
| --- | --- |
| `../maps-storage-vm-r1-clone.json` | `b4f68b674532ceeff5bd6b9fd69573348fe5f3687fc4955f79ab0cfa29e1debb` |
| `stage-before-kernel.json` | `95521cb95dcf2539063646b94e8d8d2df8b72a35f5f3c8f9aa7d6e9401696a3b` |
| `kernel-patch.json` | `cc4c672d2cc96c3da7fbd8adde80bedd25982546b0bca3112457a9b0a4ee63f5` |
| final `stage.json` | `084911671b5b4e157cf38dc0445d094767fd54f481b8481d8c2c8fc6a31aab7e` |
| `launch.json` | `7ac300959d215d3b3e9238e39afde2cb9df6f1a32bcb6e80ba110e9da5ee6872` |
| `launch-result.json` | `fe4da119ceeb4270cbfeac955a9f55e6205e82df7e6b354e5f2ff3b0d5d8ce24` |
| `ownership.json` | `01d252ea910e23403ac412700792de7a297453eee38fd347687062283d5a16be` |
| `stop.json` | `ad1f911ddab9e67eb28d5f11f4d8839c4cb3da50af35e49fb702a71d0665bada` |
| `gone.json` | `71628caca12fe715caa3811298e2187e7f45184acf8395437200d892912b0e95` |
| `qemu.log` | `afdfefa0011e8cca4532cd67170820451197d71604a8c13635b9a0f31a9122ac` |

The VM's preserved `sha256.json` is the producer's **pre-kernel** manifest,
not a current runtime seal. It binds `stage-before-kernel.json`; launch pins
the final stage above. The final stage records patched boot SHA-256
`b7ac1b3d50215507e78b3dbce323a2a69ee07276655e2da201f721f2e35518eb`.
The closed-tree seal independently inventories actual boot bytes and post-run
firmware. Historical copied manifests retain their original meaning.

## Strict rejection and corruption assessment

`maps-storage-vm-r1/serial.log`: 2,271,287 bytes, SHA-256
`62ce4916527354f7bf9aabf6204ada49dbed761ed3edf1b0fa82c2d4e07a901e`.
The owner's original collector errors were tool stdout: first a changing log
size, then an unknown frame. A new closed-log rerun retained the exact error
`unknown export frame at serial line=477`, exit 1, without creating the proposed
`maps-storage-collected-2026-10-27-r1-closed-audit` directory.

The reused `maps-account-collect-r2` binary SHA-256 is
`f1245b715d75ab41a6f1c8b3c0d45e1aed9158bfe3cd097c939ee845a3b1b29e`.
Contemporaneous checkout source is separately copied and pinned; no fresh
source-to-existing-binary build equivalence is asserted. The retained rerun's
`collector.log` SHA-256 is
`c83604ddea174a8776c7104b8450d93e65c13ffb2eb0aacfe841a881eb6c3a53`;
`collector.time` is
`cbed10e7f0fdf3fd1859314e81fce3b76c18ba2099bd221d465e7efcf494ce5e`.
Elapsed 1.01 seconds, maximum RSS 10,977,280 bytes, zero swaps.

BEGIN and END both declare 1,439,711 bytes, 2,812 chunks and digest
`fa3d24d7adf77864a38f98a230abfaae5ad90a3712a0270ff8f9ca36704283c6`.
There are 2,812 CHUNK-prefixed LF-delimited lines; 2,808 match the expected
header/base64 length/alphabet shape. Four malformed frames carry indices 54,
55, 1054 and 1973 (LF-delimited lines 476, 479, 2478, 4320). Kernel `exec`
syscall-handler and `ELF auxval` messages mix into their frame text and across
adjacent physical lines. Collector line numbering differs from this LF-only
search. No base64 payload is reproduced here.

This is a shape count, not full archive validation: it proves neither ordered
chunk delivery nor integrity of the remaining payload. BEGIN/END declarations
do not verify an archive hash. GUI commands exist only in the tool transcript;
no separate command file was found. Original screenshots and UART remain the
retained observation record.

## Screenshot pins

All 15 PNGs are preserved in the closed VM root. Native SHA-256 reads verified
these exact files; timestamps fall within the recorded VM run.

| PNG | SHA-256 |
| --- | --- |
| `booting.png` | `d049ce6500aaebb6fdcb4ecc68fad67aabe1ffaf7ebc62ef18593fe114ba73cf` |
| `desktop.png` | `c000c8aa2c830574f47117d40fc848b6beb1599c2c209d57210982d15d7566ab` |
| `desktop-ready.png` | `a4c253606a65e0bc2aff6cc940533ddfc327c0ffa345b81d97052114e42a2a5e` |
| `broker-start.png` | `1cf8128c70d166458610613b617885955f0d596eff60e744b911ac7d8bc7bc7b` |
| `broker-started.png` | `a0ab319905bd0432b78082bb2ce112cc0f25563fc3320551672a995788027ea1` |
| `broker-outcome.png` | `d6ae2c392485bcdd7f1d6c94a56211bdd4bc969258e0d23d7d3ac04e1e75b15d` |
| `broker-log-initial.png` | `295a462428f44b901327d28ac6e003876ce2634c51966e6a71d74bed5b60bdac` |
| `broker-guest-memory.png` | `075ddc3fded77551f1901bd2a241414eb3032e3d9455bbccceffe69b71507cd4` |
| `broker-startup-tail.png` | `bd008b3d696aaaf01624dc145f9ef8810a5b804fe5ffa8f8594f91646f522fe7` |
| `broker-next-startup.png` | `545936bb3f08f7e0c14e63b4987555279bd4b14d87f1ed70ec1837bbbc621794` |
| `gms-exceptions.png` | `0641cc3e6d7125fc7fc279708a434e1b5e079b68369ff2eac94e01892f71b55b` |
| `gms-failure-index.png` | `bf05c83d772864739e67d6a7c0c41da9e01a04be61055e57d51ea42a97260d16` |
| `sqlite-startup-stack.png` | `0541677a9ec78fa28675327b8332639ebb0d8f9f4c999d9ef453d9001fa7cfd7` |
| `sqlite-startup-cause.png` | `d730ec5b792e14e2d046d8b891477657df40466f26573bbe19164e523dea7627` |
| `service-construction-catch.png` | `9be9a416289f449f704e349e6a1c8af1dbe04bad09dd2cd027114d3a112b0f4d` |

## Streaming integrity closure

Maintained V sealer commit `39fc26474`, source SHA-256
`148932aee91df125c2fe56f1631b4c89275868232498c6b92c3530f5415b3a6c`;
reused executable
`b12a4d0b2b133714da6876a0ed5cda623984dc72284c482d8e3ae57975304e77`.
It streams large files through a native 1 MiB buffer and retains one bounded
directory-name list per recursion level. No large image is copied.
The same binary's mutation self-test passed again: bytes/modes/symlinks,
missing/extra files, output/manifest/pin mutations, empty directories, special
objects, overlap, nested output and sparse 64 MiB hashing. Peak RSS 12,632,064
bytes, zero swaps.

The exact 13 nonoverlapping roots are frozen in
`maps-storage-vm-r1-stream-plan-2026-10-27-r1/roots.txt`, SHA-256
`6ea1575e96ae860cdbb1545d3b8a54cf4960778d4e9fc6707df4af58c839c22d`.
They include the complete closed VM, complete producer, all ten adjacent
clone/source/tool/kernel/start/stop provenance paths, and the small audit plan.
The plan contains the collector, separate current source, rejection stdout/time,
mutation-test results and audit scope. Execution logs are adjacent to avoid
changing inventoried roots while sealing.

The closed-tree manifest is
`maps-storage-vm-r1-runtime-sealed-2026-10-27-r1/manifest.json`, SHA-256
`54de0d012f175ad124003bb7bb6f76dbebe0186ed4160974892d2a1789ce0769`.
Both seal-with-internal-recheck and a separate full check passed over all
13 roots and 265 entries. The seal took 57.08 seconds, peak RSS 25,559,040
bytes; the separate check took 20.16 seconds, peak RSS 20,217,856 bytes.
Both recorded zero swaps. These actual runs remained below 25 MiB RSS;
they do not establish a universal peak for arbitrary input trees.
The generated inventory output uses 480 KiB of allocated disk space, and the
small audit plan including its copied collector uses 2,188 KiB (`du -sk`).

The adjacent execution receipts are `maps-storage-stream-seal-2026-10-27-r1`
with these suffixes and SHA-256 pins:

| Suffix | SHA-256 |
| --- | --- |
| `.seal.log` | `3c0a5f527830e0351fe6b808d4cbd304d59c1a104b99b8c5ddaf59ae62c3c32f` |
| `.seal.time` | `594556dedc08633ec61280885867f9c4b86f408df88f0108770a79795175c9a9` |
| `.check.log` | `0b4cc4e5a96f92cef94698f7759252d7476a53d019f2ffa4816f2449f9841fbc` |
| `.check.time` | `14dd769d236b933b25b40016838e0e35a9bc7ef8851801dd99f4404ed7a26163` |

This is trusted-host integrity evidence. Original complete inputs and historical
checkers remain required, including r5 base/framework/JNI/launch/browser/account/
UI/token/fixture producers referenced by `maps-storage-r2/stage.json`. This seal
does not replace their checks, resolve external symlinks, authorize deletion,
prove a valid export or establish Google authentication.
