# Audio preparation CPU fixture closure

The first strict ARM prepare-only attempt at `88ce889a8e2ee097fe304b1c645859d9ee77b090` linked its cross probe, then refused sandbox C generation: `nativepolicy/cpu.v` embeds the sibling `cpufixture/declarations.v` and `assertions.v`, which were missing from the audio source inventories. The tracked compatibility-module symlink resolves to that same physical sibling directory.

This change adds the existing fixture directory to the producer, retainer, preparation-control and evidence-control source trees. Their source maps remain exact; ARM pointer diagnostics, preparation/resume checks and the mandatory three-scenario qualification gate are unchanged. The frozen production source is the revision above plus exactly these four inventory additions, recorded in the retained snapshot and before/after maps. The maintained [audio-fixture-closure-check.v](audio-fixture-closure-check.v) repeats actual sandbox generation and early omission refusal against that frozen source.

Host validation on 2026-10-26:

- All four affected tools built with pinned V `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`, `-prod -nocache -keepc`, explicit LLVM 23.1.0 and the private compiler-selection markers. Build processes were reaped and their process groups absent.
- Preparation controls: **88 PASS**. Strict synthetic ARM evidence controls: **34 PASS**. Selected source/tool maps were identical before and after each run.
- The maintained `compile-v-core sandbox OUTPUT --arch arm64` command produced ordinary nonempty C, SHA-256 `fae06fbedceacc4ff1ae81ea9567a8e444a4f5f3d71d738d7d1977ac87e9b45d`.
- A separately copied source tree with the fixture directory omitted refused at its exact missing source-inventory path, before source-before output, C generation, preparation, or run output.
- Independent read-only source, helper and build/control receipt reviews passed. The frozen source snapshot uses independent copies. Synthetic preparation fixtures intentionally hardlink the worktree; detach mutable worktree sources before subsequent edits.

The maintained checker was compiled with `-prod -nocache -keepc` and explicit LLVM 23.1.0, then passed in fresh `fixture-maintained-03`; actual bootstrap and checker exit statuses were both zero. Its source SHA-256 is `6e83a61af77c7f037f06abf847168ff9c712423d7659dae2c179c3e55042fa11`. The build argv, cleared environment, exact source/guard copies, log and retained C are in that bundle. The bootstrap used an external timeout; it has no sampled-supervision claim. The two commands inside the checker use the maintained guards with 180-second wall limits, one-second allocation/actual-disk sampling and process-group cleanup. Both groups were observed, reaped and empty, with final wait `-1/ECHILD`; sandbox generation exited zero and omission refused with exactly exit one and the missing fixture inventory diagnostic.

The checker binds its own compiled source; selected compiler, frozen source, runtime, kernel and host-tool bytes; exact compiler-root entry names; complete compiler library/third-party content maps; and the pinned overlay records. Before/after input maps were identical, SHA-256 `cebf44a1e875edf28b6ad04deaafbdb91f74f89b87bc00300ae0384a16c97b95`. The selected compiler and all wrapper-selection markers were coherent, `VFLAGS=-nocache` propagated through the wrapper, and private modules remained empty. An independent ordinary-file source copy differed only by the fixture-directory rename and stayed unchanged during refusal. No source-before map, cross probe, preparation, run or qualification output appeared in the refusal directory. The generated sandbox C again had SHA-256 `fae06fbedceacc4ff1ae81ea9567a8e444a4f5f3d71d738d7d1977ac87e9b45d`. The PASS receipt is published only after the post-write actual-disk and namespace checks.

Artifacts are retained under `/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/fixture-host-01`. The complete non-following inventory is the sibling `fixture-host-01.inventory.json`, SHA-256 **`b0d4f5acf7bcc8c2cb956e8ca817ec472c1bcfb7088c4888ac1e467e06b74ab4`**; seal and independent verification passed. It binds literal links, all retained source/C/ELF/log/argv/environment files and these receipts:

| Receipt | SHA-256 |
| --- | --- |
| `host-build.json` | `5f2c9432ddca2f97430a524250fd0a338676010b13d945809b21fa0613cdd64e` |
| `prepare-controls.receipt.json` | `ebe874f9681f7bcbff7a5e5932213bbc9f49fff2503b675f07121fbffec69d94` |
| `strict-controls.receipt.json` | `d9c26acb2f245bb136bfc192fc0706fcd634825510e81a30305a5191dc1a049a` |
| `smoke.receipt.json` | `937dcb56c85d3b7a21a4e2ced4373f15c6634719e666f5b6ef9a86a1843b907f` |

The external `fixture-setup.{v,c}`/executable/build log remain beside the original bundle; `setup.json` binds the generator source and resulting retained helper sources. Its historical `du` allocation was 92,668 KiB, within that run's revised 100 MiB allowance. The initial 80 MiB projection, pause at 75,636 KiB, revised allowance and actual `df -k` observations remain in `budget-observations.json`. That metric deduplicates hardlinks. The maintained guard charges every pathname, including repeated hardlink allocations: an initial 120 MiB admission attempt refused before executing either command. With the approved 512 MiB sampled namespace allowance, the successful final run charged the complete original bundle, inventory/setup siblings, preserved attempts 01 and 02, and fresh state 03. It observed 380,764,160 bytes before its receipt. The subsequent complete inventories and logs kept the observed total below 382,000,000 bytes, within both 512 MiB and the prior 0.70 GiB phase allowance. Actual `/bin/df` admission was at least 2 GiB; sampled and post-receipt checks stayed above the 1 GiB floor.

The preserved maintained attempts and complete non-following inventories are siblings of the original bundle. Sealing and subsequent verification passed for each. The first is the 120 MiB admission refusal. Attempt 02 passed before review added exact compiler-root names and staged receipt publication; attempt 03 is the final maintained source above.

| State directory | Inventory path relative to the artifact parent | Inventory SHA-256 |
| --- | --- | --- |
| `fixture-maintained-01` | `fixture-maintained-01-seal/inventory.json` | `6f593af42fc8936d961a2d9ec4fb822c6547e9183b69b22d1bd27170d76b3d17` |
| `fixture-maintained-02` | `fixture-maintained-02-seal/inventory.json` | `bf3abc590b05333f093b32c36c82631d6730aadce11ac65a4758822c727f7790` |
| `fixture-maintained-03` | `fixture-maintained-03-seal/inventory.json` | `a6642f9e4afabe48dae961aa110bf98f32d09eb118e6b884ecd978a7f1ffb71c` |

The original `fixture-host-01.inventory.json` was verified again unchanged before the maintained runs. The complete maintained inventories bind all build/run sources, C, binaries, argv, environment, output, input maps, cleanup results and actual exit-status records under their roots; links are recorded literally without following them. The retained sealer is `/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal{,.v}`.

The original failed preparation remains separately sealed by `a3-basic-failed-01.json`, SHA-256 `94a30b5a733e8d03d1feb491cf1b04873b28a67e0f1346aca6b8232929d49749`. No failed evidence was replaced. These are trusted-host generation and admission checks using observed compiler/SDK paths, without a hermetic-toolchain or complete compiler-file link-identity claim. The guards cover inherited child groups, not hostile escaped processes. No new target compilation, image, guest, WAV or audio qualification was performed; fresh eight-program preparation and its reviewed sealed receipt are still required before a VM.
