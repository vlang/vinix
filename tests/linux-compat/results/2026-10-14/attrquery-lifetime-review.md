Independent attrquery lifetime review: PASS

Reviewed the native sched_getattr fix against frozen baseline `8175c29c1559cad97f58820770d6e88c5befaa38`, final V fixture/reference/controller/auditor sources, original and corrected production C on both architectures, final preflight1 native probe C/ELFs, original and corrected p2 native captures, unchanged-ELF Linux references, and both completed six-case native receipts. No lifetime blocker remains. This review is bounded to this query's native argument decoding, output-prefix and error controls and observed caller state; it does not qualify scheduler setters or general execution.

The kernel change introduces only signed32 PID decoding, the combined entry guard, the exact min(requested_size, sizeof(SchedAttr)) output prefix, and a full advertised-range user_range check before the unchanged synchronous copy_to_user call. Independent assertions remove exactly the getter definition and normalize only the renamed prototype parameter: all remaining generated production C is byte-identical per architecture. From the existing target lookup onward, the changed C body is its original body with only the short-size assignment and range guard changed. It adds no allocator, free, scheduler mutation or deferred borrow.

The existing thread_sched_params() validates the TID, holds the PID table lock, returns a copy of t.sched through its Option value, and releases the lock. The getter retains that value rather than a Thread pointer. Its target/owner pointers are read only while the unchanged PID table lock is held, including the early MAC-denial unlock. The stack SchedAttr remains live through the synchronous checked copy. user_range performs arithmetic and the architecture limit comparison; it neither dereferences nor retains the caller's pointer. The advertised range is validated before copying the known prefix. This scope does not establish race or peer-permission conformance.

Final probe previews and staged native/preflight C are byte-identical on each architecture. Independent assertions require eleven explicit alloca sites, fixed C matrix and count arrays, a real 4096-byte stack snapshot buffer, local scanf/wait/sched_param values, and no malloc/calloc/realloc, memdup, dynamic-array or v_fixed_index calls. Each Query immediately copies errno. Attribute verification copies at most 56 bytes into an aligned, zeroed local Attr before comparing the exact returned prefix; unaligned syscall outputs are never read with an unaligned typed load. These borrows remain within their synchronous call frames.

Each cohort owns and initializes a three-page anonymous mapping before making its middle page read-only and last page inaccessible. It retains the mapping through the matrix, guard checks and storage observation and unmaps the full range before reporting. The fixture does not directly read the inaccessible page. Cross-page output faults allow only the writable prefix to change; entry and absent-target errors must leave the observed guards intact. The separately owned top-of-user-half page is selected with MAP_FIXED_NOREPLACE and an explicit exact returned-address check. An unexpected successful mapping is unmapped before trying another limit; the accepted page stays live through all boundary queries and is then unmapped. Limit-minus-56 output and all tail guard reads stay within that page. All fatal setup/cleanup paths exit without a PASS and rely on process resource cleanup.

Root and UID 1000 cohorts run sequentially in forked children. They install and verify RR priority 1 while privileged; the ordinary child drops supplementary groups, GID and UID and verifies its real/effective credentials before querying. RR and BATCH controls restore OTHER before the main matrix. The temporary exited target is waited/reaped before its PID is queried as absent. Both processes close unused pipe ends. Child Counts is initialized and remains live through qualification and its synchronous 64-byte write. The parent reads the identical size, inspects it only after an exact transfer, closes its reader and waits/reaps the cohort. Short transfers and nonzero child status fail. There is no escaping stack buffer, worker or callback.

The slab observer opens once per successful native cohort, retains that descriptor through warmup and both snapshots, and closes on every nonfatal return after opening, including cycle/snapshot failures. Stack Slabs values remain live through comparison/reporting. Parsing bounds the pread and terminator write, caps rows at 32, and never traverses beyond the returned length. The reference wrapper's three-pointer argv alloca is live through execv; successful exec replaces the process, and failure returns an explicit error. Host controllers/auditors retain their data only during bounded one-shot sessions; process handles close after waiting and the maintained streaming hash buffer is freed after synchronous hashing.

Counts are [1920,3840,1920,23] per cohort: six PID targets, sixteen request sizes, two flag words, ten output forms, one canonical PID form, two alternate PID upper-word forms and one unsigned32 size/flag upper-word form, plus sixteen RR/BATCH queries, four top-of-user-half controls and three final state/guard controls. That is 7703 per cohort and 15406 per architecture. The request matrix includes all 48 through 57 byte sizes, native PAGE_SIZE boundaries, NULL/negative/absent/reaped task errors, valid and unaligned output, read-only/inaccessible/cross-page buffers and full-width invalid pointers. Actual Linux reference output normalizes the reference runtime field and default clamp values; native runtime bytes remain strictly checked.

Independent count checks require both CASES and FINAL sets, exact counts, both cohorts and all four kinds with no duplicates. Original kernels fail exactly [210,1092,210,8] per cohort, or 3040 controls per architecture, without setup failure; both corrected kernels and the unchanged-ELF Linux references pass all controls. Corrected cohorts run 32 warmup and 200 measured query/error/state cycles, with thirteen-second settling intervals. All 18 ARM and 14 x86 slab classes are present, unique and exactly flat in both cohorts, as are large-page totals: 63/63 ARM and 160/160 x86 in each cohort. These observations establish bounded repeated-call storage behavior, not general leak freedom. The six-case profiles contain attrquery, runtime, schedabi, rrabi, open and fcntlabi with zero statuses on each architecture.

Independent receipt assertions recompute each native source/ELF/ISO and staged kernel pin. Each architecture uses an identical final probe ELF for original/corrected native, preflight1 and actual Linux reference. The Linux receipts bind the supplied kernel, probe, wrapper source/C/ELF, initramfs, serial adapter/transcript, QEMU binary and controller source, and require passed=true, finished=true, forced=true and status=0. The successful probe pauses until its controller stops QEMU. All 15146 pinned compiler inputs were independently rehashed. All independent assertion helpers were compiled without -prod; a false assertion exits 1 and the passing Linux ARM capture supplied to the baseline checker also exits 1. The maintained auditor source, including its negative-control pathways and capture bindings, was separately inspected; its publishing execution remains with the parent.

The earlier preflight probe without the explicit returned-address check is retained intact under states/preparation-mapcheck-*; no guest used that version. The next version is retained under states/preparation-reserved-page-* with its p1 captures: the x86 Linux reference failed setup because its task limit reserves one page below the power-of-two boundary. Those p1 captures are preparation only. Final preflight1 and p2 captures use the exact map check and try both unreserved and one-page-reserved limits. The selected native limits are 2^47 ARM and 2^56 x86; Linux uses 2^48 ARM and 2^47 minus PAGE_SIZE x86. Linux v6.12 defines the x86 task limit in [page_64_types.h](https://raw.githubusercontent.com/torvalds/linux/v6.12/arch/x86/include/asm/page_64_types.h). The independent checker preparation failure from a partial C definition marker is retained byte-exact as gzip with a SHA manifest; the final checker requires the full signature and opening brace. Qualification remains native unpledged musl ELF64 only. Capabilities/RLIMIT rules, task races/permissions, FIFO/deadline/EXT execution, GNU libc, translated/ELF32 callers and broader roadmap section 15 gates remain separate. This review modifies only its owned report in the repository; the parent owns implementation and committing.

SHA-256 pins below were independently recomputed after their producers completed. Paths are relative to `/Users/alex/.cache/vinix-linux-compat/attrquery-20261014`, except repository paths beginning with `kernel/` or `tests/`.

| File | SHA-256 |
| --- | --- |
| `kernel/syscall/table/gaps.v` | `4c7577f75dbcb06f5efdcdbcb1ea6be2a6452d104497837c4c30ed4ed0d92c84` |
| `tests/linux-compat/attrqueryfixture/core.v` | `ece9c957e365646f3f37aefef75b5ff7540c58da876a1764eb67fff46b557c9b` |
| `tests/linux-compat/attrqueryreferenceinit/core.v` | `bfcb6c76d8572dcb5669adad0b8df673b5055bf93dcabe4fbcc57317d3a9f88c` |
| `tests/linux-compat/attrquery-reference.v` | `a12213e964245839f5aa05d54ef01150690571e0196a01280e4984e559516aa5` |
| `tests/linux-compat/attrquery-check.v` | `62b0e0d0dcb00a22255f9bcd6f385457bcc7d1ec1efb50e2e5f0a61979b9a22a` |
| `tests/linux-compat/run.v` | `8c638d8c145b5f799d905ac526edabd8c6e85b36ac4a10e7c657b13381a19f09` |
| `base.txt` | `e198c66b635707752c8acc859851aa5fe016342893fbb5b033b1b72ef974672a` |
| `before-gaps.v` | `94bfa493ebaa165a44cc3f4c786817778752f035bbfd91d6a5a604505c7a39d0` |
| `after-gaps.v` | `4c7577f75dbcb06f5efdcdbcb1ea6be2a6452d104497837c4c30ed4ed0d92c84` |
| `before-arm.c` | `34206c95b6ca2f02553168651106779de8a8dc2fb138cd7d634d39502fb79f18` |
| `before-x86.c` | `d93db3e5ade9bbbbac562da0b0575e19370cd55cda803b0479179ce533c66455` |
| `after-arm.c` | `0814484b06acac956674c31f7a187a512b2488c77e35e5c1b788cf7c84d0ea7a` |
| `after-x86.c` | `8aa8acfe3f5ae6e1643d5ca1d04221ccf076a264843320ca0c97b94240fd69ad` |
| `preview-arm.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `preview-x86.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `independent-code.v` | `523ae39be43bc016b7873aa53d859df611e8ad5f285d97b8159e8b6853b61bb9` |
| `independent-counts.v` | `3398196a76fc75584b9ee8eaa353e93a438058a1bf443317fde0e9027f34f019` |
| `independent-artifacts.v` | `2d55ebd9c787667cfa34d96932a97efbb870e3d13415ae048dbd4bee12d51820` |
| `independent-controls.v` | `b398229435e5bf6673474fb0a8dbaa9588d73086339816bffc99961031e96cc0` |
| `independent-false.v` | `942320b332ab01a58476252010e279cfa0e5297eb38e81572df2bff81eadd62f` |
| `independent-code` | `75e0fc663bea74f651a6bdf96749b2aef7edfc6bc0dffd16c0ece40b8fdc7ac2` |
| `independent-counts` | `a17da662648515ec7e429b11a6be2d03d655ccde2bee4da191e141107ccab5ad` |
| `independent-artifacts` | `84f695d6a61011219b4b04f47274d490ec8c62a710242deb55b52952f548f7aa` |
| `independent-controls` | `9b99c9d813ab4b7585addac67620160dfccb9a74ca31aafc7adc786a931ce540` |
| `independent-false` | `6ad463de22c4ed4ccf801697656b0a1c311185b52e2a6834a15c41f54b181726` |
| `independent-code.log` | `97bcb784513b549c445ebe25f492d059ee5f39009645120df9377cb75e2829f2` |
| `independent-artifacts.log` | `2940aa50366013a9ef1221fc38e15965cf7cd8f54fc9b72db5deadc76a93a889` |
| `independent-false.log` | `eb891d23cd975f7e23d45e02353508a1d6f3d7944af1f9e1620568edc474212e` |
| `independent-baseline-control.log` | `2abd78916b5c2188da78058203603c4ed04bf62b4ca8209da3aca877e09cd8f9` |
| `independent-preparation-prototype-marker.log.gz` | `5d192533f4e19678fa563446e3fb976c7355bff7991854c35658c29f71945cbb` |
| `independent-preparation-prototype-marker.json` | `934ce6b668fd176734a57e0e675f0f351308c0e0c13c011cf267794041d527a8` |
| `states/preflight1-attrquery-arm/init` | `43da21bb9f97a38755442078b7396f5ff8924e01ea9fac6117fc5cf86ed6f770` |
| `states/preflight1-attrquery-arm/fixture.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `states/preparation-mapcheck-arm/init` | `7e000f58fa2c7b27d15262033a0e6075eabaee83b49e05a03729daaac6f102c9` |
| `states/preparation-mapcheck-arm/fixture.c` | `d6841584fd49067447e7aed0489ecee56751ddeeb0ae7349a79517f3098faee5` |
| `states/preparation-reserved-page-arm/init` | `9b724efa610cda2f12705333fbfc382491dbad9a5e3b1500bb1e0fa92e1317fb` |
| `states/preparation-reserved-page-arm/fixture.c` | `957cd4ef323cf8758c9d1d7d5b2f7193a80a2ef0adf3d7a6efce7279d611ca79` |
| `states/p1-before-arm/attrquery/init` | `9b724efa610cda2f12705333fbfc382491dbad9a5e3b1500bb1e0fa92e1317fb` |
| `states/p1-before-arm/attrquery/serial.log` | `7c10f14cb2d1c80ded507f6a0b432aa8338e5e0d4ca0a5f21674d1a76749de33` |
| `states/p1-reference-arm/probe` | `9b724efa610cda2f12705333fbfc382491dbad9a5e3b1500bb1e0fa92e1317fb` |
| `states/p1-reference-arm/serial.log` | `26069f475d974b46773ef798fb73bac458427e130c67caf21a947e50920d8601` |
| `states/p1-reference-arm/receipt.json` | `8afb374a416afe8990c343d285904d15d6662968e53c4ced2b7742ad13cf558c` |
| `states/p2-before-arm/kernel/bin/vinix` | `e6ec9dabc87487b44636145cd9cfb61d354ed29ea7ee3100771c51eac5cec096` |
| `states/p2-before-arm/attrquery/init` | `43da21bb9f97a38755442078b7396f5ff8924e01ea9fac6117fc5cf86ed6f770` |
| `states/p2-before-arm/attrquery/fixture.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `states/p2-before-arm/attrquery/serial.log` | `91bb708141230befe9f344c0d27588804eabf8f6b3fe803a2e2e6af99e44b37e` |
| `states/p2-before-arm/receipt.json` | `379a444c6a757d53ac6f51cc09ce1c34b950bdb7ba1eae62a9247d7f89933724` |
| `states/p2-after-arm/kernel/bin/vinix` | `699b7923d7a2c07e9819103ee971a30fd23317b5053ce9058dd8c1f4d46d7a86` |
| `states/p2-after-arm/attrquery/init` | `43da21bb9f97a38755442078b7396f5ff8924e01ea9fac6117fc5cf86ed6f770` |
| `states/p2-after-arm/attrquery/fixture.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `states/p2-after-arm/attrquery/serial.log` | `1e98215e0fe664090090d69106fddf379e8183ecd029defd3047a552194d5281` |
| `states/p2-after-arm/receipt.json` | `52e7f08e30670de68a5784fd3a961e2fe52e2a36c9ab9d350163e8d18e6d075c` |
| `states/p2-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p2-reference-arm/probe` | `43da21bb9f97a38755442078b7396f5ff8924e01ea9fac6117fc5cf86ed6f770` |
| `states/p2-reference-arm/fixture.c` | `da8e885277459c06c38d8e6af963a4ee2e62380fc703a746d20bd238798b7eb7` |
| `states/p2-reference-arm/init` | `6b8ea499a70987174ff73da2aed7e72183e1061944b11291f62b29c1bf5ab469` |
| `states/p2-reference-arm/initramfs.cpio` | `4d232a8df2b19051dd14b7487d241f58e48a7db6a355e8d87b1edf76ea4c9fe3` |
| `states/p2-reference-arm/serial.log` | `7048a0d8949423813dc027c4edc65d03dc07b3bdcce1cd902e9b3806f002f051` |
| `states/p2-reference-arm/receipt.json` | `4205172413ff6d37e3578e555bc2e17d5788a77ebd514382e718c8c560bd99db` |
| `independent-counts-before-arm.log` | `d336545c836bf4db4ed84ff6b1601e810700ecc7856e5cc23bbf16db64f919ca` |
| `independent-counts-after-arm.log` | `da3b93f4a53502bf70b315d62353a93cddfd884be439b4ac7cd17dba7860c5d7` |
| `independent-counts-reference-arm.log` | `f55b99e6d65ffb6ffc88d004de3abc52379f843b859a864fda6105e0cc8d5097` |
| `states/preflight1-attrquery-x86/init` | `b2423eca23720766ec649e5facedeba510dc23496bf84d67d4dcde523b749c22` |
| `states/preflight1-attrquery-x86/fixture.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `states/preparation-mapcheck-x86/init` | `56a1a4a854ccd77cebd77abbf3dbc31268c70bba4d9ed13289f2f27c71c47bb3` |
| `states/preparation-mapcheck-x86/fixture.c` | `d6841584fd49067447e7aed0489ecee56751ddeeb0ae7349a79517f3098faee5` |
| `states/preparation-reserved-page-x86/init` | `5524ab06b9d00c7eb5c70392b3ac71a6c87d0ea8e5c2ec82b7f886ce5d06fa61` |
| `states/preparation-reserved-page-x86/fixture.c` | `957cd4ef323cf8758c9d1d7d5b2f7193a80a2ef0adf3d7a6efce7279d611ca79` |
| `states/p1-before-x86/attrquery/init` | `5524ab06b9d00c7eb5c70392b3ac71a6c87d0ea8e5c2ec82b7f886ce5d06fa61` |
| `states/p1-before-x86/attrquery/serial.log` | `f44f8eb05d1a35752c03e9ae8e344efb2091161868d87af608ad5bad54c5a205` |
| `states/p1-reference-x86/probe` | `5524ab06b9d00c7eb5c70392b3ac71a6c87d0ea8e5c2ec82b7f886ce5d06fa61` |
| `states/p1-reference-x86/serial.log` | `3f8690c0f6bc5c72bd31b9cbed21233858f28e590d104a837ba48e5727941515` |
| `states/p1-reference-x86/receipt.json` | `46f8668523b413adc674e24ff1c7d1498bc3855798b70255e48ad80c6e536941` |
| `states/p2-before-x86/kernel/bin/vinix` | `63f148af81155e5e0f59c286997295a4635924beefb219d92e3d47beda7d4ed5` |
| `states/p2-before-x86/attrquery/init` | `b2423eca23720766ec649e5facedeba510dc23496bf84d67d4dcde523b749c22` |
| `states/p2-before-x86/attrquery/fixture.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `states/p2-before-x86/attrquery/serial.log` | `e47058c37ad67e50be339251a51851e6a21eceb7a6028f272e4284d819fce92e` |
| `states/p2-before-x86/receipt.json` | `6025093b9655b79a4e3e91d438d4cde61336d40c41fe7e42745425eb5bb08314` |
| `states/p2-after-x86/kernel/bin/vinix` | `76b693be68ff44a6c1ccc3fa94d55f9c7e45f2c12f0c8a6f1758170c1af580a9` |
| `states/p2-after-x86/attrquery/init` | `b2423eca23720766ec649e5facedeba510dc23496bf84d67d4dcde523b749c22` |
| `states/p2-after-x86/attrquery/fixture.c` | `f964f8585bfbe91601cf581f04d25b1b02f2fd55e5dc31fa7782a9f9e6f60c3a` |
| `states/p2-after-x86/attrquery/serial.log` | `d38724059f56982121e91b9275fd1f41df4a2ea05cb472595b7ca6d33c84e128` |
| `states/p2-after-x86/receipt.json` | `2135a08f96ad96c4dcb1b385c352ca882c10d55cd999760ab66fc5ea296f7041` |
| `states/p2-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p2-reference-x86/probe` | `b2423eca23720766ec649e5facedeba510dc23496bf84d67d4dcde523b749c22` |
| `states/p2-reference-x86/fixture.c` | `da8e885277459c06c38d8e6af963a4ee2e62380fc703a746d20bd238798b7eb7` |
| `states/p2-reference-x86/init` | `bbf82dca74cd94f8c6c8b7364ac5cde7ae006622e49d7fbe9ffc93beeffd028d` |
| `states/p2-reference-x86/initramfs.cpio` | `16f0c18ea8ccf31a5f0f5b36b5acff088851036837f5a08c28fda617b66d4ecb` |
| `states/p2-reference-x86/serial.log` | `e470dee344c5b4e4ce8acbdbb331f110971bf2f16fd8c50e420cc5ef363cdd67` |
| `states/p2-reference-x86/receipt.json` | `734eb1fe8b56d1bae580b5e4265d08119f699b81e545b6e1fec5774f0c76db23` |
| `independent-counts-before-x86.log` | `fb83144dc6d9acf60d88f2235224f2e049a727515c9956e41aa6f49ffcf96c1b` |
| `independent-counts-after-x86.log` | `078e7c1258fb3ff8ea96b70654b92535e5ebdf64d7e12bf8bf399fb6a022cf03` |
| `independent-counts-reference-x86.log` | `58d09a1f06cea96e0da979a1ac87dd35d4bc7dd38f4c33716b953936497f7735` |
| `../proctask-20261014/compiler/v` | `9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b` |
| `../proctask-20261014/compiler-inputs.json` | `fbcba16306f70092c3b0df0cad3776ab7c3e8be13ef1a4797a07b21f3dd71074` |
