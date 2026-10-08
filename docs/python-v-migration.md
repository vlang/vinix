# Python to V migration

The target is to reduce the committed Python share to **5% or less** by porting
maintained implementations and their tests to native V. The work is in progress.
At source `d858ea106c61ad58784ea370277f4708f2d8eb9d`, Linguist 7.27.0 reports
**Python 5.90%** (496 files, 2,524,439 bytes) and **V 79.68%** (1,757 files,
34,079,254 bytes). The complete committed-blob inventory and reproduction
command are in [linguist-files.md](linguist-files.md).

The starting snapshot, `9a70678887e1188926d6c8eacfc6b8f1432438f6`, counted
5,206,285 Python bytes in 523 files, or 12.51% of 41,610,938 classified bytes.
The measured net reduction so far is **2,681,846 Python bytes**. Roughly another
0.39 MB must move at equal replacement size to reach 5%; replacement sizes and
the other counted languages determine the actual percentage.

No Linguist attributes changed. First-party code and fixtures remain counted;
V code is not padded to alter the graph. Historical benchmark scripts retain
their captured bytes and Git provenance. Moving an immutable snapshot to an
archive would receive zero translation credit.

## Completed stages

Counts below describe each stage's own original Python implementations and
tests, including comments and blank lines. The 118 completed stages have a gross
scope of **3,016,741 bytes**. Counted import bridges, forwarders, fixed public data, caller edits
and concurrent committed Python changes account for **334,895 bytes**
between gross scope and the measured net reduction. Adapter additions receive
no extra migration credit.

| Stage | Native source | Original Python bytes / lines | Source commit |
| --- | --- | ---: | --- |
| G13 InitData layout generator and tests | `tools/agx-re/g13layout`, `generate_g13_initdata_layout.v` | 43,273 / 1,129 | `b20290b18916e79bc9e805fc80c12b7f8ba60f7b` |
| CPU feature policy host controller | `tests/linuxkpi/cpu_feature_policy.v`, `hosttest/core.v` | 30,725 / 613 | `cd936d50fbb86bb3e709362b9c41e6d7bcd873bf` |
| AGX trace comparison and resource descriptor mapping | `tools/agx-re/traceanalysis`, `trace_diff.v`, `map_g17_resource_descriptors.v` | 38,382 / 1,027 | `16bb0b92084864049a3ec4f6ace66002fb8501fe` |
| G13 reference contract checker and tests | `tools/agx-re/g13contract`, `check_g13_reference_contract.v` | 11,783 / 346 | `6bab99862f2fdaa35ce6b4e8063cf1db88071bd8` |
| Strict allocation benchmark log comparator and tests | `tests/alloc-bench/comparecore`, `compare.v` | 33,991 / 613 | `8828abbeb4497d76998d477cf5402c6c7c4cf70b` |
| CPU mask host controller | `tests/linuxkpi/cpu_masks.v`, `hosttest/compiler.v` | 43,864 / 736 | `fc9e67b9f3e708b1c2bf535d401943b1dc981faa` |
| IRQ context host controller | `tests/linuxkpi/irq_context.v` | 25,527 / 552 | `cd509ab1abe11ba0d2a721ef3c6445535b7411cb` |
| Pagefault host controller and module generation | `tests/linuxkpi/pagefault.v`, `hosttest/module.v` | 22,314 / 486 | `7764654abe4b1e7eecfe2cf1f37fc1dd45adc394` |
| AGX firmware, fileset and PMP extraction with tests | `tools/agx-re/imageextract`, `extractionabi` | 47,310 / 1,248 | `1eb9d935609b9c7bd2e7b5f2f668dcbe612845e1` |
| Direct kernel allocation comparison, tests and validation | `tests/alloc-bench/kernelcompare`, `compare_kernel.v`, `validate_kernel.v` | 25,002 / 478 | `5e1e3f3fc0f316ff136774faaeb2c23039a60d0b` |
| Scalar read/store host controllers | `tests/linuxkpi/scalar_reads.v`, `scalar_store.v` | 39,169 / 841 | `98a1d2b40c86217f2589065026cb9c542162d569` |
| Fake-G17 plan/reference encoder/source generator and tests | `tools/agx-re/g17plan`, three V entrypoints | 120,096 / 3,008 | `e7807a42eeb0d2111ba011a17462ec8b235f5c8f` |
| Usercopy and checked-access host controllers | `tests/linuxkpi/uaccess.v`, `user_access_scope.v` | 46,230 / 1,006 | `e973e7fbb1acc808b068b74b73ea6721ef3035cc` |
| Nocache ABI/primitive host controller | `tests/linuxkpi/nocache.v` | 26,985 / 512 | `c395bd3093a50f1a42816984d1e22dbe0626ae25` |
| User-pointer compiler controller | `tests/linuxkpi/user_pointer.v` | 9,179 / 214 | `95bcfdf680f943b6521593d4110f12c388f8521d` |
| G17 Mach-O, instruction and static register recovery foundations | `tools/agx-re/g17decode` | 39,334 / 1,056 | `6868e76fc6498c6efbb9a423972e10b0c9528e97` |
| Structured ABI header generator | `tests/linuxkpi/hosttest/abi.v`, `generate_abi.v` | 18,887 / 349 | `5c3e48b4e94a6b5d629996f68faa76522e4bfa8b` |
| G17 power model/generator and linear recovery with tests | `tools/agx-re/g17power`, `generate_g17_power_model.v` | 48,309 / 1,240 | `87b211013d61f77cf24396cdf1c50fdd78fc0946` |
| Overflow type compiler controller | `tests/linuxkpi/overflow_type.v` | 13,758 / 273 | `4069c0c7430ce41033f7376dc9cadc2c7ef3edd2` |
| Apple DeviceTree/PMGR/PMP primitives | `tools/agx-re/appleadt` | 15,469 / 347 | `5c9b3749bb722a6c8a20f1fb6a776323b81416f1` |
| macOS inspection, property lists and tests | `tools/agx-re/macinspect`, `inspect_macos.v` | 54,793 / 1,388 | `bb18890e06488335a8e2e69ea10b8348900b721d` |
| PCI topology compiler controller | `tests/pci-config/topology.v` | 36,084 / 673 | `3befd345377bad2ce884c456e39086c7cda0a6c4` |
| Complete T8103 recovery and tests | `tools/agx-re/t8103adt`, `recover_t8103_adt.v` | 35,013 / 918 | `50ca897fcbe4aed8d06c2a182b9103d2a07ec8a2` |
| G17 expressions, CFG and selector recovery with tests | `tools/agx-re/g17expr` | 119,297 / 3,050 | `7e8c6874ac10d893d9e49d0f88574b7973856d7d` |
| LinuxKPI bounds generator foundation | `tests/linuxkpi/hosttest/bounds.v`, `generate_bounds.v` | 20,254 / 423 | `f662e77d095afed829c6dd2efecd05b4094a1747` |
| Independent heap transition specification | `tests/memory/heapmodel` | 13,042 / 360 | `7fa9a2fbc0150dcfce24b763369ecfed6edc6178` |
| T6050 DART/PTD instruction contracts | `tools/agx-re/t6050power` | 29,053 / 726 | `cd14a887431246e3b3716fe490ec08bc072ac608` |
| Independent XNU zone protocol specification | `tests/xnualloc/zonemodel` | 12,764 / 320 | `184f59417ef960311dd5fb4e3bc0c70821dd08eb` |
| G17 command and queue recovery with tests | `tools/agx-re/g17expr` | 187,668 / 4,662 | `21520b90c1c26d5494d69319eea42ec5eeb04e28` |
| Bounds publication test controller | `tests/linuxkpi/bounds_generation.v` | 22,687 / 394 | `dfadf7b328fc6b1702d336d60f5272b1dd96cbe7` |
| T6050 readiness and transport contracts | `tools/agx-re/t6050power/transport.v` | 33,982 / 829 | `e4917cc2c2a1a3c388d66e5ca8e2304817051f83` |
| Pinned upstream fetch/verify and tests | `tests/linuxkpi/upstreamsource` | 7,651 / 198 | `97eab0f419b1e832de3ed98046df0692c83d6860` |
| Independent allocator reference/model harness | `tests/xnualloc/refmodel` | 15,234 / 350 | `7b45ee15947d3d93b1503c35af3bc901dc3f54e4` |
| G17 work/resource/runtime recovery and tests | `tools/agx-re/g17expr/runtime*.v` | 177,382 / 4,842 | `817216de7261cde54bd9f8f3f210d8afd468bd17` |
| T6050 diagnostic/dashboard contracts | `tools/agx-re/t6050power/dashboard*.v` | 54,938 / 1,339 | `250a71e8df694f1fb02521d899d18f091feff882` |
| Original generated-ASM header controller | `tests/linuxkpi/asm_generated_headers.v` | 17,568 / 355 | `20be6f5958ed9e57b32b985940149c0ae6ee0c10` |
| T6050 PMP firmware and RTKit boot contracts | `tools/agx-re/t6050power/firmware*.v` | 61,485 / 1,555 | `17f53d17dfe6b34db3e4752e5eeb44d6d4d6a5d5` |
| SMP/CSD type and generated-header controllers | `tests/linuxkpi/smp_types.v`, `smp_headers.v` | 41,367 / 709 | `212eb9dbe0da88be25e0203b51dd1ebba7a38132` |
| Captured desktop transcript verdicts and tests | `tests/desktop-perf/perfreport` | 19,333 / 345 | `f4b8496f83c2bfa155ac95c308e2b62519166380` |
| T6050 image instruction proofs | `tools/agx-re/t6050power/image_proofs.v` | 44,775 / 1,102 | `6c150c08da46466209b4c8d0d10d9c3d302ba077` |
| Static-key declarations and page types | `tests/linuxkpi/static_key_declarations.v`, `pgtable_types.v` | 24,388 / 493 | `55ec8ab8b3021b5ebc7342980cf4f1b046282e43` |
| G17 configuration/channel recovery and tests | `tools/agx-re/g17expr/config*.v` | 146,167 / 3,803 | `2909aa80ab11b007910962308f5432f2abc08d86` |
| Original special-instruction compiler controller | `tests/linuxkpi/special_insns.v` | 12,994 / 244 | `18daaab0ed1bda245c96c70a05ad23297deed7d4` |
| T6050 power and PMP DART topology | `tools/agx-re/t6050power/topology*.v` | 36,327 / 870 | `9238aaf2920c12292c9a09a3d7642ec1d93b8c83` |
| Original/V FPU instruction controller | `tests/linuxkpi/fpu_headers.v` | 4,937 / 89 | `8ead088e53de1613cb33a2698ebe31a4da75ece6` |
| Header primitives, spin and standalone controllers | `tests/linuxkpi/{compile_primitives,spin_sequencing,standalone}.v` | 13,733 / 251 | `9fe8543a87a6d7b82fe4560e4f54e4fb3e0c3a7f` |
| T6050 patchbay image proofs and fixtures | `tools/agx-re/t6050power/patchbay*.v` | 12,332 / 300 | `7d20071e6a19c53e3ebe85f5f659afcb81e795d3` |
| Original overflow arithmetic controller | `tests/linuxkpi/overflow_policy.v` | 12,342 / 211 | `0be99bc503222705cb26fdd32e18c0035672e09f` |
| Verified-root geometry, image builder and Merkle checks | `tools/verified-root/verityimage` | 14,421 / 254 | `f61b6c420aae82d52a38be67a9e32fae62ba737b` |
| T6050 complete controller compositions | `tools/agx-re/t6050power/controllers.v` | 14,745 / 399 | `350662064f72406a6b2d48b5a8aa1a5dd76aec9d` |
| T6050 public constants and final fixtures | `tools/agx-re/t6050power/public_constants.v, frontend_test.v` | 16,097 / 390 | `7841d5a689c4bcc1cfbf8676ac1b426c058aac27` |
| G17 event recovery and validators with fixtures | `tools/agx-re/g17expr/events*.v` | 83,043 / 1,924 | `2a21daef57eebb71b35c8eb5b54a464e5f45ce89` |
| Verified-boot literal policy and PE/ELF helpers | `tools/verified-boot/bootpolicy` | 7,380 / 122 | `cd6abfb63ab0eb89720a4f336c57dff9e3c1377c` |
| Android host DEX, ELF and path validators | `build-support/android/androidhost` | 5,448 / 111 | `c3bdbff00efd57c7e879a495ce835215ff42e3be` |
| G17 firmware, hardware and allocation layouts with fixtures | `tools/agx-re/g17expr/layout*.v` | 74,464 / 2,375 | `c5577fae4bd4a55dd498ffc5b4ae4c0ee9ade7b3` |
| Content and desktop cache keys with fixtures | `build-support/cachekey` | 20,145 / 501 | `8902fbff78630752ab73e3a32233747be65bc81f` |
| Generic V module producer and metadata contracts | `tests/linuxkpi/hosttest/module*.v`, `generate_module.v` | 8,940 / 162 | `42c0c8dd4e40b170d9035c88eaf879e246f2da21` |
| G17 executable-memory store census and decoder fixture | `tools/agx-re/g17expr/census*.v` | 23,623 / 542 | `71ff04f9102adb23269430272853828b5cfdcb06` |
| Staging and VOffice cache policies | `build-support/cachekey/build.v, source_text.v` | 10,382 / 276 | `07266f68972c3680451c45b649ea548c11fe3f1f` |
| Android ART runtime manifests, path policy and installation | `build-support/android/androidhost/runtime*.v` | 10,005 / 162 | `332d24b8ee49c46dcc062488810b33fae4149c6d` |
| Dota compatibility producer and constructor/mmap controllers | `build-support/dota2/compat.v`, `tests/dota2/{early_client,mmap32}.v` | 7,959 / 136 | `51de8b2a1ce7097de3dbe1d6bb77208bbea1db02` |
| Android launcher contract fixtures | `tests/android/launcher-test.v`, `launcherfixture` | 12,100 / 241 | `e62a13eb625b6a2f3c4025acbfdd86df287c78ec` |
| G17 legacy frontend helpers and original fixture | `tools/agx-re/g17expr/legacy*.v` | 60,540 / 1,530 | `394df238fa61eeaa094844886a55f5d4bdb88597` |
| Dota launcher host regressions | `tests/dota2/launcher.v` | 14,628 / 307 | `b0dae5385062c2eaba6d2051e2215e6eeb119d8d` |
| G17 complete report orchestration | `tools/agx-re/g17expr/controller*.v` | 18,004 / 394 | `747a7bb78225afd95565904342a1b37d32f1f87f` |
| G17 fixed public data | `tools/agx-re/g17expr/public_constants.v` | 30,049 / 729 | `0007a0fd2aa9347c9861d354d6b473342fba3b51` |
| Android Java, split APK, ART and AVF probes | `build-support/android/androidhost/probe*.v` | 14,186 / 242 | `194f22c94afc21c6508b68600abbcf21fb7b8500` |
| Dota serial transcript parsers | `tests/dota2/transcriptcore` | 9,497 / 170 | `29439c388978ea53bf547a9d2b699e604e47d112` |
| Android Dalvik and sample application probes | `build-support/android/androidhost/simple_probe.v` | 4,903 / 78 | `886f308e463fde99fe7f0aea4574f58879926380` |
| QEMU core fixture build controllers | `tests/qemu-core/fixturehost, fixture_controller.v` | 54,129 / 858 | `908d60934e8eeeda34207c31842909521a5a3da6` |
| Android guest runner helper policies | `build-support/android/androidhost/runner*.v` | 3,398 / 56 | `e2cde544961091c40a7a1e83362681284531d756` |
| AGX host verifier and trace producer | `tests/agx-fake-g17/agxhost` | 4,491 / 61 | `f090cba9b53e062746a57b1238310ad8f82d7716` |
| Apple ANS, SPI and speaker provider controllers | `tests/apple-protocols/applehost/providers.v` | 8,204 / 147 | `2286b3336d34436468f343636d38c4717ec4b5c9` |
| Dota build and runtime cache policies | `build-support/dota2/buildcore` | 6,320 / 106 | `cdce2e9d1074bd357ec3b3e70858f1f792ec1913` |
| Android EGL and split probe controllers | `build-support/android/androidhost/advanced_probe.v` | 12,872 / 185 | `ac262fdb9c5570b5f1cfe5ea7a8188f09d4ff64e` |
| Android deployment and optional launch scripts | `build-support/android/androidhost/deployment.v` | 7,418 / 105 | `b13d145ab1c7e4b852e1920ea653025e36af8a5f` |
| AGX complete trace workflow | `tests/agx-fake-g17/agxhost/trace*.v` | 10,251 / 134 | `26d6b3ad04d8e43b3cb8cc03ebc90e40bd91835d` |
| Android ART and Bionic independent fixture controllers | `tests/android/runtimefixture, art-runtime-test.v` | 12,118 / 237 | `f75ef88bbf2c74347adec79a26d910d4b562ee7a` |
| Font coverage, fallback, layout and output policies | `desktop/tools/fonthost, font_query.v` | 17,972 / 416 | `6fa66c2d3660c97b13f23bf88af1224163595a92` |
| Android musl independent receipt fixtures | `tests/android/runtimefixture/musl.v` | 7,174 / 151 | `edb0b66cfcd29b150f36f246754130239548d6df` |
| AGX native fixture guest builder | `tests/agx-fake-g17/agxhost/native*.v` | 4,698 / 65 | `d2a477101d31e1d69649fbfa7c5a9fc9157a5350` |
| Complete offline OVMF fixtures | `tests/qemu-ovmf/ovmffixture, test_patch.v` | 16,807 / 419 | `57be4858aa1cc8ffa925e9769c69bdf37acec813` |
| Complete Android bootclasspath fixtures | `tests/android/runtimefixture/boot.v` | 8,996 / 166 | `f4fc4156ed65d07381350627896b71fc140d2d36` |
| Complete QEMU source/build/staging workflow | `build-support/dota2/qemubuild, qemu_builder.v` | 13,128 / 251 | `34ee6a12833c915014aaab218134bae88ee604e9` |
| Generated syscall, permission and disk-policy controllers | `tests/generated-policy-host/policyhost` | 29,558 / 597 | `15113790448ee4c3f675fb62633c15c3ff0605e3` |
| Mesa AGX guest PTY and QMP ownership | `tests/agx-fake-g17/agxhost/vm*.v` | 6,982 / 190 | `8ecc7c264d31ce58d9c8a78eb94dceade459c161` |
| CPU assembly and scheduler-frame probe controller | `tests/generated-policy-host/policyhost/assembly*.v` | 10,810 / 220 | `10dcea973ec9189fb2b148459edb648ec188e015` |
| Complete Android bootclasspath build workflow | `build-support/android/boothost` | 14,939 / 268 | `1b8efef098379574776d4f950dba19a60aff9d39` |
| LinuxKPI production host controllers | `tests/linuxkpi/hostfixturebuild` | 7,196 / 139 | `528d19676f65a649305af0811de87f5cc305f4a9` |
| Desktop and ui2 source staging workflows | `desktop/tools/stagehost` | 16,046 / 401 | `9878439f2a2bbb920aab8dbd6af38f535a426f19` |
| Complete Android ATL independent fixtures | `tests/android/runtimefixture/atl.v` | 13,582 / 246 | `0ca7c62a8d672ea269430a6bd324ff4a17ab2363` |
| Complete QEMU core guest controller | `tests/agx-fake-g17/agxhost/core_vm.v` | 8,478 / 238 | `11e7c8e5ea5a84ca12adad5c90724782472c33cd` |
| Independent LinuxKPI audit regression controller | `tests/linuxkpi/auditfixture` | 8,245 / 170 | `9587ce0d1f13b5d2923b431756178750bac37639` |
| Complete Dota game fixture preparation | `tests/dota2/prepcore` | 14,524 / 276 | `2b4ff1ce4c661c427027b381c7c8ac1f0047eb86` |
| Complete LinuxKPI disposable guest workflow | `tests/agx-fake-g17/agxhost/linux_guest.v` | 5,981 / 93 | `4541994a0aa1a76b39463005b081fe2e47f18381` |
| Android image preparation and runner validation | `tests/android/runhost` | 24,592 / 406 | `4d5b5e18737218eccb73d4d687d073ab9a6ad988` |
| Android session result and probe verification | `tests/android/runhost/result.v` | 10,692 / 176 | `35c6681c63a8f41040d668d58c7ff316ae777150` |
| Complete Minecraft fetch and staging workflow | `build-support/minecraft/fetchcore` | 13,897 / 315 | `3a036e652430a9a021cbdd8528da793ed02cc7dc` |
| Private Vulkan staging workflow | `build-support/dota2/vulkanbuild` | 19,099 / 375 | `bf87b9fe9dae758ee6656aaaf0f983eafeee31f2` |
| Android pre-fork VM snapshot and boot plan | `tests/android/runhost/vm.v` | 2,181 / 38 | `74c18849102a5056f109b86dea78d3704ffb939f` |
| Android QMP, keyboard, screenshot and shutdown policies | `tests/android/runhost/input.v` | 3,894 / 98 | `017ea1a761338a63c2da19ef90e3d334739a8b1d` |
| Desktop performance setup and serial supervision | `tests/desktop-perf/runnercore` | 10,056 / 186 | `821b88a8d1751e887386b69995abcd92bc2a63ed` |
| Complete kernel-gap disposable guest and hypervisor forwarding | `tests/kernel-gaps/gapcore` | 11,449 / 234 | `30f971351d3c85edc95b77bc93e016cc219c6f59` |
| Loopback QEMU package-store and clipboard policy | `tools/packagestore` | 16,798 / 443 | `89ee70b6829fd6de8093acb85ade4b14331afcd2` |
| Complete independent private Vulkan fixtures | `tests/dota2/vulkanfixture` | 18,652 / 333 | `0f462c73a3862732987df768d9b854eba2363abc` |
| Android serial workers and foreground supervision | `tests/android/runhost/supervisor.v` | 3,352 / 66 | `76e20056a2b52ee3ae381906746f6401c31f6f08` |
| Complete lavapipe compute guest workflow | `tests/dota2/lavacore` | 12,047 / 192 | `1a6d769b3ac822bba2eb8d3cf4c296469477834c` |
| Complete independent package-store fixtures | `tests/packages/packagefixture` | 11,421 / 253 | `e13414842c314c690032035dc79c78f4243dbb39` |
| Complete ext2 image and manifest construction | `tools/dota2/ext2build` | 11,962 / 256 | `da3885cafa750831a11db8ada48aa81e14d7e5c1` |
| Complete independent ext2 NBD fixtures | `tests/dota2/ext2fixture` | 8,563 / 147 | `a1c58a96c20e13b4d8b45d6463e61704e8621936` |
| Complete translated Vulkan rendering guest workflow | `tests/dota2/vkcore` | 11,647 / 236 | `653cc62818bf17ac62540839534d94f6592cd4b3` |
| Complete Android runtime and archive build workflow | `build-support/android/runtimebuild` | 17,986 / 314 | `e498309c4cad1e073e40509c953a28b033b911cb` |
| Ext2 source cache and read-only NBD protocol | `tools/dota2/ext2build/{export,protocol}.v` | 7,180 / 143 | `d1918f0ccfe70330d666817ff9b1dd5cb0b1f436` |
| Complete OpenGothic cross-build and game staging | `build-support/opengothic/gothicbuild` | 10,713 / 222 | `8aaf12979e5d2c704e34782921cd82c30250ab83` |
| Alpine index parser and provider closure | `build-support/alpinecore` | 2,174 / 56 | `77d02a150cb1e224654a521eb0d4c23e882b1dbc` |
| Complete N64 upstream archives and staged source workflow | `build-support/n64/n64build` | 17,077 / 308 | `a084b53a29d54bc497b15d2f2cf2238144e82212` |
| Complete Dota game launch, observation and retirement | `tests/dota2/gamecore` | 10,440 / 208 | `e2271dba1f4b43d9b3580a7cd6f12dd4ec6d70da` |
| Complete VOffice compilation and incremental build workflow | `desktop/tools/officebuild` | 8,816 / 255 | `d858ea106c61ad58784ea370277f4708f2d8eb9d` |

Shell entrypoints compile V executables in a private temporary directory using
`build-support/run-v-tool.sh` and the compiler selected by `find-v.sh`. They
preserve the caller's working directory, literal arguments and exit status.
Commit `29395517` corrected V's default adjacent output path, which otherwise
could overwrite an extensionless launcher. The launchers stayed intact in
subsequent integration tests. Commit `a8297b76` separately preserved the
generator's argument-error behavior; it receives no additional port credit.
Commits `2f201134` and `bc8577ef` select the platform C compiler and preserve
the V compiler binary's architecture when launched through Rosetta. Actual
x86 tests exercise shell routes as well as the independently compiled binaries.
Commit `5bd3b6bb` preserves explicit empty Path options, option-value parsing,
help actions and abbreviations across the LinuxKPI controllers. Commit
`683cbc7c` preserves the argument error for a bare `--`; 310 actual CLI
controls cover the ten prior controllers. Commit `bc28715b` adds the malformed
`-h=` status edge across all ten (370 CLI controls); `fbae5cba` covers the same
edge in both ABI/bounds generators (200 controls). These fixes receive no extra port credit.

Commits `51f8b95e` and `2c64eab9` consolidate already-native G17 and T6050
public forwarding declarations into structured V metadata and one stdlib
function binder. They remove 41,583 and 10,263 counted Python bytes, including
shared binding changes, and receive **zero repeated algorithm credit**. G17
retains 191 public declarations; T6050 retains 54 native forwarders and its
unported Python tree helpers. Function signatures, annotations, defaults,
argument errors, dynamic module globals and generator laziness remain checked.
Linux guest fixed marker data moves another 4,771 original bytes/46 lines to V;
its table row counts only the 5,981-byte workflow, with data accounted separately.
Commits `9f19e7d2` and `e575156d` preserve context-manager entry/exit, exception
context, suppression and ignored successful-exit return values, with zero new
migration credit. The Minecraft first consumer counts all 4,506 bytes of new
shared transport and adds 29 Python bytes overall. Vulkan's 19,099-byte newly
ported scope excludes 1,458 bytes of prior native forwarders; its counted
bindings exceed that eligible scope by 499 bytes. Those bindings stay counted.

The desktop supervision stage counts all stdlib/owner bindings and adds
1,872 Python bytes overall. Android VM-plan and input stages remove 1,800 and
98 bytes respectively. Commit `92998c1c` consolidates Android's already-native
transport onto the shared owned controller, removes 1,745 counted Python bytes
and receives zero repeated port credit. Shared factory/EOF configuration in
`30c75713` and `53f28be4` adds 175 counted bytes and receives zero algorithm
credit; default consumer behavior and exact caller-specific errors stay checked.

The subsequent twelve stages remove 70,649 measured Python bytes overall,
including all counted adapters and simultaneous committed changes. Five
context/error/concurrency corrections (`2bd0606f`, `cdc36ad7`, `c48777c8`,
`ff66bafb`, `52bc7b30`) receive zero additional algorithm credit. Native
contexts preserve the original exception object, supplied traceback, active
cause during exit, suppression/error precedence and deliberate traceback
clearing or replacement by libraries such as `unittest.assertRaises`.
Exact traceback frame lists and Python 3.9 `sys.exc_info()[2]` parity are not
claimed. Query resources remain independent across concurrent callers.

The next four stages remove 27,483 measured Python bytes overall,
including all counted adapters and simultaneous committed changes. Native
exception-constructor binding `d8ed6c81` and N64 parser correction `31fda527`
receive zero additional algorithm credit; their 137- and 906-byte Python
binding growth remains counted. The N64 CLI parses help, usage and the jobs
argument before starting its native controller. VOffice follows the same
frontend ordering. Neither CLI requires a compiler for these parser results.

## Validation

Each stage retained frozen Python originals until the candidate passed its
comparison gates. Originals remain recoverable from the source commit's parent.
Tests executed actual Darwin ARM64 binaries and independently compiled x86_64
Mach-O binaries through Rosetta. The host compiler was
`/Users/alex/code/v/v`, **V 0.5.2 6d549c2**. Host-only stages do not establish
kernel builds or guest workloads. Guest runs below identify hashed prepared
kernels and images; they do not establish new kernel builds or physical
GPU/CPU execution.

- G13 generator: 26 native tests, all 324 GPU/version structure layouts and
  11,188 field offsets per architecture, 20 CLI/layout controls, and exact
  generated source/report bytes. Explicit 4 GiB tests check wide counts and
  offset-return widths. Production generated kernel source did not change.
- CPU feature policy: GNU99 and GNU11 each retain 1,116,514 sanitizer
  assertions on both hosts. Nine emitted original fixture/scaffold files,
  19 generated bodies, 18 native objects and two cold-header objects match the
  original controller. Literal arguments, environment, dual-pipe draining,
  the original 120-second deadline and timed-out child reaping were checked.
  The existing frozen e690943 compiler/LLVM profile generates the production
  policy model; current V builds its host controller. Independent C observer
  fixture text stays byte-exact and receives no C migration credit.
- AGX trace tools: all 16 original tests plus eight native edge cases,
  1,435 differential API cases and 29 CLI cases per architecture. Raw JSON
  numbers preserve 64-bit GPU addresses and arbitrary-width ABI integers.
  Nested filter values retain Python-style representations. A narrow libc
  `strtod` binding preserves decimal-to-binary64 rounding.
- G13 checker: eight native tests and 60 differential controls across both
  architectures, including live contracts, source mutations, missing sources,
  synthetic Asahi ordering and CLI error cases. Mutations used copied source
  trees. The maintained make targets and combined Python/V AGX test suite pass.
- Allocation comparator: all 19 unchanged original test bodies exercise the
  native implementation, alongside 21 native tests, 1,052 differential API
  cases and 21 CLI controls per architecture. Controls include complete saved
  benchmark logs, malformed records, unsigned boundaries, exact checksums,
  raw medians and unmatched-run statuses. Exact integer division and narrow
  libc decimal parsing/formatting preserve Python's binary64 rounding. An
  independent peer reviewed numeric and host-allocation lifetimes.
- CPU masks: GNU99/GNU11, native V/original C model, 15,810,213 assertions per
  combination on both hosts; 68 cold host processes, 16 emitted files, 28
  selected bodies and 16 native objects retain their original bytes. Exact JSON
  decoding preserves nanosecond provenance above 2^53 and signed/unsigned limits.
- IRQ context: GNU99/GNU11 each retain 280,732 assertions per host, 11 original
  helper/observer bodies and the actual 256-vector interrupt assembly object.
  Checks retain all 224 maskable enter/exit pairs, 32 exceptions, CS offset 152,
  IF gates, fences, jumps and relocation-table entries. The original compiler
  commands remain without a deadline; generation/runtime deadlines remain 120/30 s.
- Pagefault: GNU99/GNU11 each retain 494,347 assertions and eight fatal
  invariants per host. Complete generated C, all 130 bodies and four x86/ARM
  O0/O2 objects match exactly. LLVM IR differs only in private temporary paths.
  Compiler-only ordering, absence of allocator imports and absence of hardware
  fence instructions remain checked. Fixture and production-header bytes are unchanged.
- Extraction: 20 native tests, all 13 unchanged original Python checks,
  5,419 differential API cases and 107 CLI controls per host. Real LZFSE growth
  and decoder scratch retirement are covered. A 10,000-iteration ASan/UBSan
  fixture calls the actual exported native ABI with foreign threads. Inputs
  remain borrowed for synchronous calls; JSON/binary outputs use libc ownership
  and explicit release. Repeated foreign-loader/ownership batches retain zero
  owned outputs and bounded post-collection heap use. A dedicated loader thread
  keeps Boehm's initial thread alive when first imported from a short-lived worker.
  Narrow Python bridges remain for unported recovery callers: net reduction
  36,999 bytes. The combined AGX suite passes 270 remaining Python tests and
  four V modules. Nine real shell routes pass with the final dispatcher.
- Kernel comparator: all 26 original test bodies, 27 native tests, 1,052 exact
  API cases and 52 CLI controls per host. ARM ASan/UBSan repeats the original
  tests and differential controls. Shared helper regression retains the earlier
  comparator's 19 original tests, 1,052 API cases and 21 native tests. Twelve
  native/shell validator controls cover complete/incomplete logs, a 120 KB pipe
  and late panic. The guest runner sends the captured log snapshot to V through
  stdin; benchmark deadlines and workloads stay unchanged. A peer reviewed
  numeric behavior, error ordering and host lifetimes.

- Fake-G17 tools: 14 native tests per host, all 17 original test bodies routed
  to native APIs, 3,944 exact API cases per host and ASan/UBSan, and 638 CLI
  controls. Generated 51,435-byte kernel V and 1,583-byte ABI header remain
  byte-exact. Wide offsets, selectors and external keys retain their full
  integer values. The maintained make test/check targets and four shell routes
  pass; integration is committed separately as `e54a156e`.
- Scalar access: GNU99/GNU11 each retain 1,033 read and 26,260 store assertions
  per host. The 123 read bodies, 123 store-frontend bodies, 124 word-module
  bodies and independent invalid-width fixtures remain exact. Six x86
  O0/O1/O2 proof objects retain CPUID and immediate MOV widths, with no RMW
  or allocator imports. Supplied-header profiles and 32 CLI controls per controller pass.
- Usercopy/checked access: 197/143 generated bodies remain exact. Usercopy
  retains 9,200 assertions per standard on both LLVM 23 host ABIs; scope
  retains 449,253 per standard on both AppleClang 21 ABIs. Untouched scope
  fails on LLVM 23's unused-global diagnostic; native negative controls retain
  that failure instead of weakening warning flags. Fixtures, headers,
  compiler-only fences, normalized IR/width diagnostics and 29 CLI controls per
  controller match. Runtime deadlines remain 30 seconds.
- Nocache: 25,299,139 assertions per standard per host and a supplied-header
  ARM profile, 123 frontend and 127 primitive bodies, all eight freestanding
  frontend/ABI combinations and six x86 O0/O1/O2 primitive proofs. All 22 native
  objects match the originals. Typed inline-assembly widths, memory operands,
  CPUID ordering, NT instruction selection and the SFENCE memory clobber remain
  checked, along with no runtime imports. The fixture retains its 60-second
  deadline; 32 CLI controls pass.
- User pointer: 25,603 assertions per standard per host, byte-exact fixtures,
  headers and extracted pinned macro, all six wrong-type diagnostics and no
  runtime imports. The 30-second fixture deadline remains; 32 CLI controls pass.
- G17 foundations: 63 original functions moved to V. Each ARM/x86/ASan build
  passes 121,304 decoder/Mach-O controls, including exhaustive UTF-8 byte pairs,
  logical masks, random encodings, signed offsets and wide branches. The real
  driver retains all 6,545 symbols, ten code spans and six vtable targets.
  Nineteen recovery and 21 extraction native tests, 227 unchanged recovery tests
  (12 original private-fixture skips) and the integrated 253 Python/six-module
  suite pass. Foreign-thread tests retain zero owned output buffers and bounded
  collector use. Net Python reduction is **26,531 bytes**, including the
  loader's 13-byte fingerprint addition; `python-accounting.json` pins exact
  committed blob sizes. The public alignment helper now accepts arbitrary
  signed integers in native V.

- ABI generator: 123 original/native source and metadata controls, 44 CLI
  controls and 19 decimal rounding/limit controls. Three actual production
  headers match byte for byte with both pinned and x86 host compilers. Exact
  unbounded constants, source-root confinement, adapter arity, local capture,
  type/width validation and JSON error category remain checked. Original
  overflow/exchange and all four ABI audit-generation fixture tests pass.
  The unchanged spin controller fails in current transitive headers on both
  hosts; native negative gates preserve that baseline diagnostic. Commit
  `52a79217` changes the kernel make recipes to native V; 12 isolated make and
  original-generation controls verify exact headers, repeat timestamps and
  helper-triggered regeneration. This does not claim kernel execution.
- G17 power: 13 native tests, 4,307 model and 197 recovery controls per host
  and sanitizer profile, 48 CLI controls, four original generator tests and
  three original recovery tests. The actual driver recovery dictionary and
  11,490-byte generated kernel table match exactly. Arbitrary-width voltages,
  Q40 arithmetic, binary32 overflow and original instruction-proof mutations
  retain their errors. Platform `powf` rounding is compared with the original
  oracle running on the same architecture. Foreign-worker import calls return
  to zero owned output buffers. Net retirement is 47,947 bytes.
- Overflow types: the complete C fixture is byte-exact. Both production and
  immutable original headers retain 454 boundary cases and 4,099 assertions
  for GNU99/GNU11 on ARM/x86. Nine provenance/header/declaration mutation
  controls, 32 CLI controls, exact file-scope diagnostics, no runtime imports
  and the original 30-second deadline remain checked.
- Apple ADT: 23 native tests and 54,690 exact API controls per architecture,
  including the production import boundary. All 43 original T6050/T8103
  fixture tests and both actual T6050 manifests pass. Real LZFSE growth and
  scratch retirement, copied payloads, numeric predicates, error ordering and
  unaligned instruction matching are covered. Each host completes 8,000 calls
  across 32 distinct simultaneous foreign workers with zero owned outputs and
  bounded collector retention. ASan/UBSan also covers 10,000 direct ABI calls.
  Gross scope is 15,469 bytes; counted wrappers/bridges leave 10,241 net bytes.
- macOS inspection: 28 native tests, all 22 unchanged original test bodies,
  36 full original contracts, 2,383 additional API controls, 2,472 property-list
  controls and 168 CLI controls on each host. Binary/XML integers retain
  arbitrary precision; literal read-only registry commands, simultaneous pipe
  draining, Unicode, sorted ASCII JSON, selected-property filtering and saved
  plist behavior match. Four maintained shell routes pass from `/tmp`.
  Sanitizer gates use Boehm with the real stack and a separate `-gc none`
  fake-stack build, retaining every wide-integer assertion. An independent
  unchanged `math.big` test reproduces corruption when Boehm is combined with
  ASan fake-stack relocation; the incompatible configuration is recorded
  separately. System Expat remains an upstream parser primitive; conversions
  and binary-plist parsing are V, with parser retirement reviewed by a peer.
  Commits `5c9b3749`/`789653b1` integrate native power/ADT/inspection callers and
  the complete AGX test suite; original generated producer comments remain
  unchanged to preserve the byte-exact table provenance.

- PCI topology: GNU99/GNU11 retain 7,150,771 assertions per compiler profile
  and host, with current and pinned production generation. All five complete
  independent fixture/header inputs, selected bodies and compile/link arguments
  match. Seven native metadata tests, 138 API controls, 32 CLI statuses and
  three maintained shell routes pass per host. ARM sanitizer controls cover
  parsing and lifetime behavior; 300 KB simultaneous output pipes retain
  literal arguments. A real 120-second timeout terminates and reaps the child
  while preserving its log. This is a host config model, not hardware execution.
- T8103: 32 native tests, all 23 unchanged original tests, 11,224 exact API,
  169 file and 239 CLI controls per host. Three malformed help controls retain
  status 1 with a clean diagnostic. Real driver/live-capture dictionaries and
  actual shell routes match; 8,000 calls across 32 simultaneous foreign workers
  return to zero owned outputs and bounded collector retention. ARM sanitizer
  gates retain every numeric and file assertion. Native recovery and the AGX
  make/test callers are integrated by `7c2b42c5`.
- G17 expression/CFG/selector: 33 native tests, 30 unchanged original test-body
  replays and 24,416 exact full-output controls per architecture and sanitizer
  profile. The actual ABI covers 20,384 cases per host, including 4,032 rank
  controls preserving unsigned target versus arbitrary signed use-offset
  comparisons. The actual 25 MB driver selector/inline maps match, with inputs
  unchanged. Each host completes 1,600 simultaneous foreign-thread calls with
  zero owned outputs. Native instruction offsets keep arbitrary precision.
- Bounds foundation: four real GNU99/GNU11 generations, 11 publication/input
  rejection cases, three malformed markers and seven stamp cases per host.
  Headers, assembly and native compiler flags match byte for byte. Fifty-three
  API, 44 CLI and eight execute-only compiler-cache controls cover exact wide
  constants and compiler identities. ASan covers archive extraction and error
  lifetimes; copied libarchive path/error strings survive archive retirement.
  Streaming SHA, source identity and ordered atomic publication live in V.
  The 1,181-byte system archive declaration header remains counted as C.
- Heap specification: all ten unchanged original scenarios and ten native
  scenarios pass on both hosts. Each host matches 106,066 seeded MT19937/bit
  controls and 7,154 complete PMM/slab state snapshots, including every payload
  byte through hashes, recycling order, invalid frees and exact arithmetic
  boundaries. ARM ASan/UBSan retains all ten native scenarios. A peer reviewed
  model ownership and invariants. This remains an independent executable model
  and source check; it does not execute the kernel allocator or concurrency.

- T6050 DART/PTD foundation: ten native tests and 13,773 exact API controls
  per architecture; 20 frozen and 18 remaining original checks, actual driver
  manifests, 8,000 calls across 32 foreign threads with zero owned outputs,
  and 10,000-iteration C ABI lifetime/sanitizer stress pass. The returned
  metadata describes checked instruction evidence, not physical firmware execution.
- Zone specification: all six original and six native scenarios pass on both
  hosts, including 80,000 seeded operations and 10,017 complete state snapshots
  per host. Magazine identity, queue order, bitmaps, failed batches, cache swaps
  and backing retirement remain checked. ARM ASan/UBSan passes. Commit
  `49b12d88` additionally accommodates the pinned release's field/array compiler
  behavior; the same complete snapshot and sanitizer gates pass again.
- G17 command/queue recovery: 40 native tests, 35 unchanged original methods,
  6,638 full-output/error controls and 22 actual-driver outputs per host pass,
  alongside the existing expression and power suites. Arbitrary-width symbol,
  vtable and instruction offsets, strict UTF-8 diagnostics and clamp behavior
  retain their original semantics. Each host runs 1,600 foreign-thread calls
  with zero owned outputs. ARM ASan/UBSan covers the same native API.
- Bounds controller: four positive GNU99/GNU11 profiles, 11 rejections, seven
  stamp cases, three malformed markers and 37 CLI controls per host pass.
  The original 847-byte independent C fixture is unchanged. Commit `5675044e`
  uses V directly in the kernel make recipes and tracks helper V/header inputs.
  Sixteen isolated actual-make/original controls pass, covering unchanged
  timestamps, header dependencies and compiler flags. Actual raw assembly
  hashes stay in provenance: unique source-directory names and their derived
  DWARF string-offset comments are normalized only in comparison evidence.
  Four untouched-original repeat pairs independently prove the raw debug hash
  variation. There is no new kernel execution claim.
- T6050 readiness/transport: 15 native tests, 14,232 exact API controls,
  18 frozen and 16 remaining original checks, actual manifests and sanitizer
  lifetime stress pass on both hosts. Tests preserve initial publication before
  readiness, patchbay copy/writeback and ASCWrap lock/mailbox policy. Repeated
  8,000-call/32-thread batches retain zero owned outputs.
- Upstream fetch/verify: three original and three native scenarios pass on both
  hosts, including sanitizers, seven archive cases, 43 CLI and 34 API controls,
  nine transport/publication controls and the exact 7,668-file pinned import.
  Thirty-two phase-proven fault controls check cleanup against unchanged open-FD
  sets; a real 60-second inactivity timeout and immediate progress output pass.
  Initial ineffective interposition and disk-full exploratory logs are excluded.
  A 269-byte declaration-only system archive header remains honestly counted C.
- Reference harness: all four original/native scenarios pass on both hosts,
  with 5,125 complete arena snapshots, 12,000 rotating scans, 3,091 merge cases,
  40,000 mixed buddy operations and the original exhaustive slot counts.
  The unchanged independent C fixture retains both UBSan compile profiles;
  six native compiler argument controls per host match the originals. ARM
  ASan/UBSan passes. The pinned V 0.5.2 `7647ce1` Darwin release passes all 20
  independent model scenarios plus the unchanged 18 actual allocator tests
  in debug and production configurations. A Linux ARM heap-model check passes;
  additional shared-mount Linux checks blocked in FUSE directory reads and were
  stopped, so they receive no success claim. CI now runs the models separately
  from the actual allocator tests. No production allocator or SMP port occurred.

- G17 runtime: 42 unchanged original methods, 45 native functions and 14,086
  complete controls pass on both architectures and ARM sanitizers, along with
  30 real-driver outputs and foreign-thread ownership checks. Commit
  `a82845e9` separately corrects unsigned segment-size narrowing: 11,872 exact
  caller outputs, populated highword/overflow images, immutability and 10,000
  sanitized ABI exchanges pass. That correction receives no port credit.
- T6050 dashboard and firmware: 22,600 and 9,864 complete API controls per
  architecture, 16 and 14 frozen original tests, exact real-driver manifests,
  native regression suites, sanitizers and 8,000-call/32-thread ownership
  batches pass. Shared ABI stress retains zero owned response buffers.
- ASM/SMP controllers: original C fixture text and complete compiler arguments,
  headers, dependency receipts and result reports match after private paths and
  independently checked producer/stat identities. ASM retains 16 objects/eight
  rejections; SMP headers retain 22 objects/six rejections. GNU99/GNU11 SMP
  fixtures retain 420,004 CSD initializer sanitizer assertions per host.
  Current and pinned V compile the controllers on both actual architectures.
  Untouched strict sign-compare failures remain recorded; supported profiles
  keep that diagnostic visible. Controller deadlines and child reaping remain.
- Desktop verdicts: 23 native functions, 41,003 numeric/transcript controls,
  all 29 unchanged original harness tests, 800 summaries and 120 complete
  stdout/stderr/JSON byte comparisons pass on both hosts. ARM ASan/UBSan and
  success/failure installer stress preserve exact FD sets and remove private
  executables after exit. All Unicode13 nonprintable/digit properties were
  checked exhaustively. Qualified production summaries contain finite rows;
  long direct NaN lists have interpreter-specific unordered-sort artifacts and
  are outside the qualified summary domain. Guest workloads remain unchanged.
- T6050 image/topology: 15,001 evidence and 6,549 raw-image controls, then
  21,898 complete topology controls per architecture and sanitizers, match the
  originals. Frozen tests, native suites and full manifests pass. Synchronous
  inputs, copied outputs, 10,000 sanitized ABI exchanges and foreign-thread
  batches retain zero owned responses. Wide SID tests check canonical key
  enumeration separately; no billions-of-iterations original replay is claimed.
- G17 configuration: 48,313 complete boundary/mutation outcomes per host,
  34 unchanged methods, 38 native configuration functions plus 131 regressions,
  24 recursively typed real-driver outputs and 13,201 public type/error cases
  pass. Highword MOVZ offsets and INT32_MIN negation retain their widths.
  Sanitizers, fake-stack checks and 10,000 shared-ABI exchanges pass with no
  owned response remaining after foreign-thread batches.
- Static/page/instruction/FPU controllers preserve every original C fixture,
  full report/dependency/Clang argument checks and actual host profiles.
  Static keys retain six objects/four rejections and 4,001 sanitizer assertions
  per standard per host; pages retain four objects/two rejections with visible
  sign-compare warnings. Instruction headers retain 16 objects/four rejections
  and exact disassembly without executing privileged or MOVDIR64B instructions.
  FPU's unchanged x86 fixtures retain 1,024 x87/MXCSR borrows under sanitizers.
  Current/pinned controller CLI gates and ARM controller sanitizers pass.
  These host checks make no new kernel, QEMU, device or scheduler claim.

- Header primitives: 16 complete generated-C comparisons cover all eight modes
  on both actual host ABIs; 528 CLI and 345 allocation-regex controls pass.
  The supported x86 spin fixture reports zero errors, and standalone preserves
  all seven sanitizer markers. Untouched strict ARM/x86 compile failures retain
  their original warnings and target restrictions.
- Overflow arithmetic: independent unchanged fixtures retain 589,824 checks,
  the exact digest and 13 type domains (nine accepted, four rejected) in each
  supported host/controller profile. All 176 CLI and 28 macro controls pass;
  strict original target failures remain recorded.
- T6050 patchbay/controller/public stages: 5,283 and 1,505 complete original
  outcomes, exact reader-callback traces and all 199 public values/types pass
  on both hosts. Native suites, unchanged fixtures, real-image manifests,
  sanitizers and foreign-thread exchanges return zero owned responses.
  Secondary image decoding remains lazy at the original reader boundary.
- G17 events: 36,349 exact typed results/errors, all original methods, eight
  real-driver outputs and complete controller reports pass on both hosts.
  Sanitizers, fake-stack and four real shared-ABI profiles retain zero owned
  outputs. Numeric equality, float rounding and callback tuple/list identity
  retain their original conventions.
- Verified-root: 5,661 full original helper outcomes per host/sanitizer profile,
  46 CLI cases per host and all four original tests pass. Private executable
  installation/retirement, publication races and failed builds are checked.
  The unchanged independent production verifier passes on both host ABIs under
  sanitizers for images of 1, 2, 128, 129, 16,384 and 16,385 blocks; its source
  remains independent. This is host validation of image algorithms, not a
  new kernel boot or actual Linux veritysetup claim.
- Verified-boot: 7,223 original PE/command-line/configuration outcomes per host
  and sanitizer profile, streaming digest boundaries, ELF header checks and
  21 filesystem error cases per profile pass. All five original policy/bundle
  tests pass through the facade, and their two maintained bundle bodies remain
  unchanged. A genuine ARM64 Limine 12.8 loader is accepted; the older cached
  x86 loader retains its original rejection. Native executable installation
  and retirement pass under concurrency. Signing/CLI/integration controllers
  remain counted; real signing tools are absent, so no new signature, Secure
  Boot or QEMU execution is claimed. Qualified PE buffers are bytes and
  bytearrays, alongside the documented scalar/path policy inputs.
- Android validators: 1,212 full original outcomes per actual host and sanitizer
  profile include two real ART boot DEX payloads. All 45 retained original
  fixtures, four native functions, independent DEX cases and 200 repeated ELF
  reads pass with exact descriptor baselines. JSON, ZIP and runtime/install
  frontends remain counted; this stage ports six validator bodies.
- G17 layouts: 12,773 exact typed/error controls per profile, 15 native tests,
  11 real-driver outputs and all original/remaining methods pass. Missing-read
  subsets, wide signed addresses and callback ordering remain intact. Two
  production shared ABIs, fake-stack checks and foreign-thread stress retain
  zero owned outputs. Eleven algorithms, twelve methods and seventeen audited
  sole-use fixture recipes are retired without overlapping previous credit.
- Content/desktop caches: 1,332 full tree/root/resolver controls, 46 direct
  environment/tool controls and 20 complete desktop keys per host/sanitizer
  profile pass. All eleven original methods pass the final production facades
  on both hosts before retirement; thirteen native functions and both shell
  launchers pass. Streaming boundaries, wide signed nanoseconds, symlink loops,
  Unix backslashes and filesystem errors retain their original behavior.
  Content formats retain v1; desktop v2 adds three native implementation inputs
  to invalidate cached images after implementation changes. Cold 128-request,
  eight-thread installers preserve exact descriptor sets, private 0700 mode
  and cleanup after success/failure. Retained Python shlex, version/package
  probes and compatibility framing receive no algorithm credit.
- Generic module producer: 28 complete original/native generation pairs cover
  seven real families, two targets and both actual hosts; 16 whole primitive
  outputs, 14 functional CLI pairs and 264 argument/error controls pass.
  Another 1,507 parser/header and 33 filesystem/error controls per profile,
  five native tests, real copy failures/metadata and constrained EFBIG writes
  preserve diagnostics, partial bytes and descriptors. Exhaustive Unicode13
  word/uppercase checks cover 1,112,064 valid scalars across current/pinned host
  profiles. A 256-request, sixteen-thread installer retires private storage on
  success/failure with exact descriptor sets. Unordered readonly set diagnostics
  compare membership rather than process-dependent repr order; directory atimes
  are normalized only in cross-run comparison evidence, with raw evidence kept.
  The remaining Python file is a counted import/process binding. These host
  checks do not establish new kernel or QEMU execution.
- FPU argument ordering: commit `64b19e9f` preserves eager rejection before
  help actions; 212 current/pinned CLI cases pass on both hosts. It receives
  no additional migration credit and supersedes the earlier CLI receipt.

CLI help/usage, JSON decoder and OS-specific filesystem diagnostics may differ;
algorithm diagnostics, data schemas, success output and failure statuses are
checked against the originals. Assertions, timeout limits and original fixture
workloads were not weakened.

- G17 census: 3,304 exact typed result/error controls per ARM/x86/sanitizer profile,
  10,896 conservative decoder controls, four actual driver invocations, all
  16 remaining original tests on both hosts, and 1,600 foreign calls per host
  retaining zero results. The 10,000-call sanitizer harness also used fake-stack
  C callers. Kernel alias last-wins behavior remains intact.
- Staging/VOffice: 2,121 full original tree, predicate, resolver and source-parser
  controls per profile; 186 complete consumer key/completion controls per profile;
  11 CLI/state-publication cases per host. The explicit v2 reference changes only
  the namespace and three native-helper source inputs. All 16 retained compiler
  and orchestration bodies have identical ASTs. Twenty native tests include every
  Unicode13 valid scalar and 200 decode plus 200 directory failures with an exact
  descriptor baseline. Both shell routes and 128-request/eight-thread cold
  installers preserve private cleanup and descriptor counts. A peer reviewed lifetimes.
- Android runtime: 1,248 full policy/path/metadata controls and 30 installation
  states per ARM/x86/sanitizer profile, eight native tests and all 45 retained
  host fixtures per architecture. Literal Unix backslashes, embedded NUL rejection,
  preflight-before-mutation, modes and hardlink isolation remain covered. Failed
  installations retire descriptors and temporary files. Python JSON/ZIP/XML codec
  and arbitrary-key pair-validator bindings remain counted with zero extra credit.
- Dota controllers: complete original/native source, Clang/nm argv, environment,
  fixture output and cleanup controls on both host ABIs; 24 actual producer/source
  pairs, 336 CLI controls plus 132 prior shared-parser controls, 20 genuine failure
  and cleanup pairs, and four real shell-route fixture runs. Constructor and
  mmap checks retain their independent C/V inputs. The sparse ext2 exporter is
  separate unfinished work and receives no credit here.

- Android and Dota launcher fixtures compare complete argv, environment,
  working directory, limits, filesystem modes and cleanup on both host ABIs.
  Android retains all nine original tests plus ten native cases; Dota retains
  26 original/native cases and 28 whole-process trace pairs. The Dota test CLI
  now uses `run-v-tool.sh tests/dota2/launcher.v --case` instead of unittest
  selectors. Android probe qualification covers complete original pipelines,
  archive bytes, truncated ZIP comments, partial failure state, temporary
  retirement and failed spawns on ARM64/x86-64 and with ARM sanitizers.
  External Java/D8/aapt processes are controlled in these tests; no new Android
  guest execution is claimed.
- G17 legacy helpers compare 3,919 typed outcomes per profile and all 16
  original methods on both ABIs. Report orchestration preserves all original
  typed values and integer keys; the exact 935,250-byte CLI control is the
  committed pre-controller frontend, whose earlier insertion-order changes
  are retained. All 264 final public names, tuple/dictionary key types,
  import-time state and mutable dictionary identity are checked. Foreign
  result ownership and borrowed Mach-O lifetimes retain zero owned results
  after repeated calls, including 10,000-call C sanitizer/fake-stack harnesses.
- Dota transcript parsing compares 2,725 frozen outcomes per host/profile,
  including Unicode13 digits, arbitrary-width counters and capture keys.
  Cold concurrent bridges retain exact descriptor baselines and retire every
  private directory. Shared work-directory fixes and the G17 fixture stack
  adjustment receive zero Python credit; original diagnostic literals and
  independent assertions remain unchanged. Thin exported filesystem/UTF-8/
  Unicode helpers are covered as source-bound QEMU dependencies.
- QEMU fixture controllers retain all original CLI ASTs, oracle provenance,
  generated source/header/schema bytes, compiler argv and allocator guards.
  Sixteen real host fixture comparisons cover both ABIs; 32 native build
  comparisons link both SDK targets. Other gates cover 64 source preparations,
  114 integration groups, 21 strict-output error groups, 16 full process traces,
  12 cold entry/cleanup groups and 24 Git failure/raw-byte controls. Seven
  native lifecycle/IO tests pass per final profile. Broad compiler gates
  preceded the final isolated Git cwd/raw-output refactor; final Git/entry/unit
  gates cover that refactor. Mach-O comparison accounts only for validated
  UUID/timestamp/signature metadata and retains raw executable hashes.
  These host-tool stages do not establish fresh kernel, QEMU or device results.
  A peer reviewed new lifetimes before each implementation commit.

- Android runner helpers compare 330 ELF and 140 split cases per profile,
  four native tests, 55 existing fixtures on both host ABIs, and 100 repeated
  descriptor-error paths. EGL/split controllers compare 109 whole pipelines
  and 208 ELF cases per profile, mixed caller/controller architectures,
  inherited descriptors and signals. Deployment compares 231 complete phase,
  file and error observations per profile, seven native suites per host and
  ten existing interactive fixtures. Lazy optional-script order, exact bytes,
  modes and final launch policy are retained. Controlled compilers and external
  applications do not establish actual Android or guest execution.
- SDK architecture preference support preserves universal and single-slice
  fallback, argv, environment and signals in 108 actual command comparisons.
  Native tests cover raw output, cwd and copied SDK storage on all profiles.
  The public preferred capture and receipt wrappers delegate existing bodies.
  These support commits receive zero additional Python migration credit.
- AGX host verifier/trace production runs the complete original C encoder and
  verifier on each profile, 61,344 Unicode13 guard controls, eleven failures,
  five producer cases and four concurrent cold installers. The complete trace
  workflow retains immutable C oracle modes and compares 15,506 policy/error
  controls plus fourteen ordered typed failures per profile. Both production
  Darwin targets, mixed caller/controller ABIs, five CLI controls and cold
  entry cleanup are checked. Arbitrary-width trace integers and typed Path
  error metadata retain their original values. No GPU or guest is exercised.
- Apple providers compare 249 complete original/native outcomes per profile:
  manifests, ordered inputs, hashes, copied bytes and modes, partial failures,
  Unicode/raw filenames and overlapping source/destination trees. Four native
  functions per profile and concurrent cold installers check retirement and
  exact descriptor baselines. Broader unchanged ANS/SPI/speaker consumer
  fixtures fail with the same V 6d549c2 generated-C diagnostics against both
  original and native providers; x86 ANS also rejects the existing ARM assembly.
  Six paired baseline failures have identical diagnostics and provider input
  hashes. This stage claims passing provider gates, without claiming passing
  consumer fixtures, kernel builds, QEMU or physical Apple operation.
- Dota build policies compare 6,955 pure and 2,072 runtime outcomes per profile,
  1,386 real pinning calls per ABI and eighteen original/native fixtures.
  Forty-two streaming, EINTR and fault cases retain single-close ownership and
  the original 1 MiB digest buffer. Native dependency hashes are included in
  Mesa/Venus/QEMU cache keys. Concurrent installer checks retain exact descriptor
  baselines. Whole build workflows remain counted Python at this snapshot.
- ART/Bionic fixtures port all seventeen original test cases and assertions to
  V, preserving the original unittest IDs and filters. The frozen complete
  26-case corpus passes on both actual host ABIs; the combined seventeen native
  and nine retained ATL cases passes all 26. Native cases also pass sanitizers.
  Shared payload helpers and the public production-API binding remain counted
  Python and receive zero extra scope credit.
- Font generation compares 206 API outcomes per profile, including 42 ordered
  Pillow method/error controls and three lazy Japanese-catalog failure cases.
  All profiles produce the exact original 18,075,442-byte atlas (SHA-256
  `3557458fa182dec44f9b783fb7f4931ac4383230308fdc478f2286bf236757b7`)
  and identical Japanese subset files from the pinned source. Four native tests,
  the five unchanged baked-font tests, fifteen subset/download/lifetime groups,
  and twelve actual-ABI cold entry/CLI groups pass. Each profile retires 100 raw
  Pillow fonts and 100 open/clear cycles; cache owners, temporary masks and
  residual fontTools objects are independently reviewed. Pillow 11.3.0,
  FreeType 2.13.3 and fontTools 4.60.2 remain library primitives. Original direct
  library/import/argparse bindings are excluded from the 17,972-byte credited
  scope. No committed atlas, bundled fonts or provenance records change. Real
  source/artifact arrays below 2 GiB are qualified; advance integers are unbounded.

- The ten original musl receipt fixtures run with identical unittest IDs and
  filters on both host ABIs and native sanitizers. Existing ART/Bionic cases
  and the complete 26-case runtime corpus pass. A parent-owned scratch guardian
  preserves independent assertion failures while retiring descendants even
  when native assertions exit without running defers; forced failures in all
  three fixture families preserve status/stderr and remove their roots.
- The AGX native guest builder compares eight complete architecture/oracle
  variants, eighteen ordered failures, four actual inherited-environment
  cases and seven CLI/cold-entry controls per profile. Four fresh independent
  encoder/verifier guests pass, one of each on ARM and x86, using explicitly
  hashed prepared kernels. This establishes new guest runs, without claiming
  fresh kernel builds or GPU operation.
- All twelve original offline OVMF fixtures run in V with their original Git,
  shell, patch and optional-environment assertions. Nineteen ordered builder
  status/stdout/stderr/driver-byte observations match per profile at identical
  isolated paths. Constructor/assertion failures retire exact directory and
  descriptor baselines; four actual-ABI cold-entry groups pass. Upstream mode
  tables, the firmware patch and build script retain their committed bytes.
  These tests do not build edk2, publish firmware or boot a guest.
- All nine original bootclasspath fixture cases run on both actual host ABIs
  and sanitizers, including exact DEX builders at 0/1/10/1,687/3,297 classes,
  provenance mutations and strict JSON float types. Parent guardians retain
  assertion status and remove the original case directory on forced failure.
  The unchanged combined runtime corpus and musl fixtures pass through the
  additive primitive bindings. This fixture stage invokes controlled production
  APIs; it does not establish Java/compiler/application or guest execution.
- QEMU staging compares 38 complete original/native workflows per profile,
  thirty CLI controls and isolated cold public-front controls on each host ABI.
  Three native ownership functions also pass sanitizers. Actual pinned upstream
  source preparation, patching, static AArch64 compilation, ELF validation and
  staged publication pass. Native helper sources participate in cache identity.
  One accidentally nonterminal original CLI control wrote default build/staging
  artifacts; it is excluded from passing evidence, and only proven new staging
  artifacts were archived. The existing shared build cache was never reset.
- Generated-code controllers compare nine whole build plans and exact
  independent C fixture bytes, 780 extraction/error/Unicode controls and 122
  ordered whole-policy failure cases per profile. Six complete original/native
  sanitizer fixture pairs pass on each profile for syscall, execute-only and
  disk-policy inputs on both architectures. Nine forced primitive failures keep
  the original exception objects and retire scratch. One hundred repeated
  requests restore exact descriptor baselines; abrupt controller exits also
  retire parent-owned scratch. Twelve CLI controls and full cold entry pass
  on both actual host ABIs. Existing generated-C inputs are frozen and hashed;
  they do not establish fresh kernel builds or QEMU boots.
- AGX Mesa PTY ownership compares 9,105 marker/prompt/resource/status controls,
  eleven real PTY/QMP flows, eleven public socket/borrowed-child controls,
  three interrupt flows, nine typed timeouts and seven CLI controls per profile.
  Native owners retire 100 sockets and 100 children to exact descriptor counts.
  Further interrupts cannot abandon a child during retirement; overflowing
  timeouts retain their original error while retiring the original leaked PID.
  Two fresh original/native Mesa guests match the same prepared-image FAIL:127:
  missing Wayland/dri_loader/arc4random runtime symbols prevent rendering. Exact
  final diagnostics and hashed kernel/image/runtime inputs are retained. This
  is paired baseline failure evidence, with no rendering or fresh-build PASS.
- The CPU assembly controller retains exact generated assembly/C fixture bytes
  and all six tool/execute commands, twenty-two ordered adapter/layout/tool/symbol
  controls and three forced scratch-retirement failures per profile. Unbounded
  symbol addresses retain decimal precision; int(base16) remains a narrow
  counted stdlib primitive. Both original and native actual sanitizer workloads
  pass 1,024 per-CPU cases, all fifteen register thunks and independent scheduler
  frame assertions. Three ignored-argument CLI pairs and full cold invocation
  pass on both host ABIs. The other three generated-code fixture controllers
  also pass their actual ARM and x86 regression workloads. Kernel assembly
  inputs remain unchanged; this host stage adds no kernel or guest claims.

- Android bootclasspath production compares 121 complete workflow/type/error
  controls, three full main pairs and six transport failures per profile. All
  nine unchanged boot fixtures and the 26-case runtime corpus pass on both
  actual host ABIs; native fixture/sanitizer runs also pass. ZIP ordering uses
  path components, wide integer equality stays exact and probe resolution
  retains its position after staging. Source closure hashes include transport.
  Compiler/Java/device execution is controlled; no new guest claim is made.
- LinuxKPI host controllers produce byte-identical V-generated sources for all
  21 fixture groups on ARM, x86 and sanitizers. Whole controller, namespace,
  template, symbol, CLI and cleanup controls pass. Actual strict host suites
  retain their original failures: ARM x86-ESP assembly constraints and signed
  comparisons, and x86 signed comparisons. No runtime-object, kernel or guest
  PASS is inferred from these host-controller tests.
- Desktop staging compares 345 independent pure/whole/error/Unicode controls,
  nine CLI/live-source pairs, seven abrupt-controller/stream cleanup controls
  and 100 repeated requests to exact descriptor baselines per profile. Actual
  six-case package HTTP fixtures pass for frozen originals and native code on
  both host ABIs, including cold copied-source compilation. Canonical icon data
  and the generated C ABI header stay byte-exact and receive zero C port credit.
  The normal compile overhead is retained; no desktop/QEMU rendering claim is made.
- All nine remaining ATL fixtures are native, with frozen original full/ATL
  sweeps and unchanged 26-case front IDs. Real stage/cache production pairs,
  native ARM/x86/sanitizer fixtures, existing boot/musl regressions and forced
  assertion retirement pass. Original independent ELF/DEX builders, hardlink
  coherence and manifest mutations remain checked by the same assertions.
- QEMU core compares 8,644 policy cases, 17 real PTY flows and the original
  CLI/path, environment, stdio, typed timeout and interrupt controls per profile.
  Frozen/native ARM guests pass all 47 features and the persistent reboot using
  identical prepared inputs. On x86 two earlier native runs fail the untouched
  first-touch free-page assertion; two frozen originals and the final native
  inherited-environment run pass on the same retained ISO/kernel/firmware.
  All attempts remain recorded. Darwin execvp inheritance preserves XPC service
  identity. This establishes new guest runs, without a fresh kernel build claim.
- Audit fixtures preserve the production baseline of two PASS and two unchanged
  FAIL cases on every profile. A cache-only complete frozen surrounding bounds
  implementation gives all four original/native cases PASS with the actual
  independent C syntax caller/compiler. Nine identity/retirement controls per
  profile and cold invalid-metadata entries on both hosts pass. The fixture
  source and assertions remain unchanged; there is no C or workload port credit.
- Dota preparation compares 190 complete workflow, header, closure, iterator
  and error controls per profile, including real APFS runtime copies. All eight
  unchanged host regressions, three native unit functions, seven forced process/
  stream cleanup controls and both hosts' CLI/cold entries pass. One hundred
  requests retain the exact descriptor baseline after stdlib imports; the
  initial cold measurement separately identifies Python random's single owned
  urandom descriptor. Namespace reads, original exception objects, partial queue
  mutation and preload iterator failure order remain intact. Whole fixture
  compiler commands are controlled; no new game/kernel/rendering claim is made.

- LinuxKPI's disposable guest workflow compares 24 complete frozen/native
  branches per profile, single and repeated interrupts, exact descriptor
  baselines, cold entry and marker-list identity. Both frozen and native default
  x86 guests pass on the same hashed four-CPU prepared inputs, with a final new
  state repeat. Earlier fake-compiler path mismatches are excluded. This is a
  default guest check; it does not claim the full opt-in LinuxKPI suite or a new
  kernel build. Existing 9,105 AGX and 8,644 core policy regressions also pass.
- Android image orchestration compares 22 complete preparations, 49 main
  controls, 140 split cases and 14 file/archive cases per profile. Eight forced
  retirements, seven CLI pairs, both cold installs and the unchanged ten-case
  PTY corpus pass. The separate manager fix extends file/manager coverage to
  18 cases, preserving partial tar bytes and exception context. No Android
  device, Java runtime or kernel/QEMU boot claim is made.
- Android results compare 239 frozen/native transcript, wide-numeric, namespace,
  probe-precedence, raw-JSON and exception controls per profile, alongside the
  original ten PTY assertions, eight retirements and both cold installs. Private
  controller reaping retains the five-second bound while remaining independent
  of the caller's VM wait/sleep mocks. No guest functionality is inferred.
- Minecraft compares 284 policy/type/error and 48 complete workflow controls,
  18 manager/process retirement controls and eight actual local HTTP main/cache/
  retry cases per profile. The three independent original tests pass unchanged.
  Both hosts retain 16 public metadata contracts, nine CLI/cold controls and
  exact descriptor equality across 100 repeated hashes. Parallel worker call
  order is scheduler-dependent; its exact invocation set and ordered map
  results are checked. Original ordering-only qualification failures remain
  recorded. No official game download, launch, kernel or rendering claim is made.
- Vulkan production compares all 18 unchanged independent staging snapshots and
  ordered effect plans, plus 107 original/native controls per profile. Actual
  bare mmap32 and early-client helper rebuilds retain identical generated C,
  x86 ELF and undefined symbols on both hosts. Five CLI/cold entries pass per
  host; the existing unused-import warning remains an explicit cold stderr
  difference. APFS rejects invalid UTF-8 names for both candidates. Fake driver
  builds do not establish GPU or guest operation, and no C port credit is taken.
- Binding-only G17 checks cover all 191 metadata records and 1,542 call controls
  on both hosts, actual image/public outputs, 264 constants, a byte-exact
  935,250-byte ordered report and owner retirement. Its 181-case older mock
  suite retains 95 PASS, 12 SKIP and 74 identical baseline failures; Python mocks
  cannot enter its existing native provider. T6050 checks 54 bindings/445 call
  controls, lazy constants, three public fixtures and the exact 49,676-byte
  manifest on both hosts. Its older 20-case suite retains 17 PASS and three
  identical errors. Shared G17 requalification also passes after the module
  globals adjustment. Both native metadata modules pass sanitizer gates.
- The separate Dota stream manager correction compares 198 complete original/
  native controls per profile, all eight unchanged host fixtures and seven
  forced retirements. Successful exit results are ignored; exception-time
  truth errors retain the read exception context. Both cold entries and
  100-request descriptor checks pass. This correction has zero port credit.

- Android's pre-fork VM plan compares 57 complete original/native branches
  per profile, including 100-digit payload sizes, boot-size boundaries, snapshot
  bytes/modes, partial failures, exact environment/argv and original exception
  identity. All ten unchanged interactive fixtures and both cold installs pass;
  this stage does not establish a new Android or kernel boot.
- Android input/QMP policies compare 98 exact API branches, eleven actual-library
  pairs including blocked UNIX-QMP interruption, six unexpected resource exits,
  eight transport retirement controls and ten unchanged interactive fixtures
  per profile. The default 8-second key acknowledgment and shutdown phases
  remain intact. Parent managers retain entered-value and exit-error context.
- Android transport consolidation repeats 539 preceding workflow/file/result/
  VM-plan pairs, 98 helper pairs, twelve actual-library pairs including process-
  group interruption, 34 previous-binding error reconstruction/identity pairs,
  fourteen retirement controls and all ten unchanged interactive tests per
  profile, plus cold installs on both hosts. Query-only session isolation lets
  terminal interrupts reach the caller's cleanup; compiler installation keeps
  its original session. This is a binding correction with zero new port credit.
- Desktop supervision compares 80 complete dictionary/manager/compiler/main
  workflows, ten actual stream/controller/guest retirement branches, exact FD
  equality across 100 dictionary requests and two actual group-interruption
  pairs while blocked on a serial queue or UNIX QMP per profile. The 12 original
  runner fixtures remain unchanged. Both hosts preserve 13 public metadata
  contracts, the complete argparse AST, six CLI pairs and twelve cold fixtures
  under the original guest mocks. Captured private primitives keep controller
  retirement independent of VM wait/sleep/temp mocks.
- Prepared, copied and hashed four-CPU ARM inputs pass frozen/native desktop-idle
  and wakeup checks with identical 15-second settling/five-second sampling plans.
  A native pointer sweep also passes with an actual 2048x1536 QMP screendump and
  independent serial draining. Two earlier one-second native attempts complete
  but fail intact report checks because concurrent kernel diagnostics corrupt
  metric fields; those logs are retained. No fresh kernel build or new manual-
  free kernel lifetime result is inferred from these host controller ports.
- Shared transport factory/default/argv checks pass, and all preceding Minecraft
  284+48 workflow controls, eighteen manager/retirement controls, 100 FD requests
  and eight actual local HTTP cases pass per profile. Default/custom EOF texts
  and exact descriptor retirement also pass; the EOF follow-up repeats all
  eighteen retirement controls and 100 requests per profile. These API changes
  leave their original default consumer behavior intact.

- Kernel-gap/hypervisor workflows pass 58 builder/helper, 12 QMP, 29
  forwarding, 123 whole-policy and retirement/API controls per profile,
  including 100 exact-FD requests and all 12 original fixtures. Prepared,
  hashed ARM/x86 guests pass frozen and native full suites; these inputs are
  not fresh kernel builds and do not establish actual VMX execution.
- Package-store policy passes 150 whole, 14 API, five broken-controller and
  two group-interrupt controls per profile, all six real local-HTTP fixtures
  and cold CLI checks on both ABIs. Its independent fixture port repeats
  every original case and exact byte/mode/assertion plan on all profiles,
  22 owner and 13 API controls, 74 production regressions and both cold CLIs.
- Private Vulkan independent fixtures preserve all 18 cases and original
  assertion/deadline plans; 15 owner and six late API controls pass per
  profile, with cold complete fixtures on both ABIs. The zero-credit traceback
  correction adds 16 manager/mutation controls and repeats 107 production
  controls per profile. No physical renderer validation is inferred.
- Android supervision passes 54 worker/observer, 75 foreground, five whole
  PTY and four retirement controls per profile, all ten unchanged fixtures
  and both cold installs. Concurrency/context corrections repeat 649 prior
  controls, 34 decoding and 14 retirement controls and exercise real QMP,
  screenshots, keyboard input, concurrent errors and traceback ownership.
- Lavapipe compute workflows pass 56 whole/helper, 19 owner, 100 exact-FD,
  seven fallback-context controls per profile and cold CLIs on both ABIs.
  Prepared, hashed ARM kernels pass all 12 compute cases against both
  workflows. Vulkan rendering workflows pass 104 whole, 17 helper, 16 prepare,
  13 owner, two nested-interrupt and 100 actual-PTY controls per profile,
  with all preceding kernel-gap/lavapipe controls and both cold CLIs.
  Frozen/native prepared ARM guests complete 3,000 translated-rendering
  frames; both independent color samples exceed the original >8 threshold.
  This evidence establishes neither a fresh kernel/Mesa build nor a game,
  physical GPU or Venus result.
- Android runtime construction passes 112 frozen/native filesystem, archive,
  six-worker, stage/cache and workflow controls per profile, 13 retirement
  controls and 100 exact-FD requests. All 45 original Android fixtures,
  five CLI pairs, three actual curl transfers and group interruption pass per
  profile, plus both cold installers. Two original key identities and 51
  independently checked new source-closure invalidations preserve ordered
  original inputs and cover the translated implementation.
- Ext2 construction passes 480 frozen/native controls per profile, 17 owners,
  100 exact-FD requests and independent image/manifest/e2fsck/debugfs/QEMU NBD
  checks. The independent fixture port preserves all six cases/assertion
  plans on every profile, 73 ownership/protocol controls and both cold suites.
  Earlier original APFS sparse-size assertions failed in both implementations;
  final real runs pass after allocation reuse. An additional positive stat
  control is identified separately. No assertion or deadline was weakened.
- Ext2 cache/NBD policy passes 562 protocol/cache comparisons and 64 ownership,
  partial-initialization, mutation and property-order controls per profile,
  500 source reads with the original 64-descriptor cache limit and 200 reads
  from eight concurrent callers, with exact final FD equality. All six frozen
  and native real fixtures pass per profile, including QEMU NBD reads, plus
  seven no-compiler CLI pairs and actual cold build/fsck/full fixtures on both
  ABIs. One competing sanitizer attempt exceeded the unchanged shortened
  100 ms negotiation deadline; the isolated complete rerun passes.
- OpenGothic construction passes 81 whole frozen/native controls, twelve real
  curl/Git/command/six-worker controls, two blocked group interruptions and
  five forced exits per profile, four CLI/cold/atexit controls on both ABIs,
  and all 74 shared package regressions per profile. Offline complete builds
  use identified source/compiler fixtures and claim no new upstream renderer,
  kernel build or guest result. New host managers and borrowed lifetimes were
  reviewed independently; no kernel manual-free lifetime was changed.

- Alpine resolution passes 172 frozen/native parsing, Unicode, repository,
  provider, dependency and public-override controls per profile plus 26 CLI,
  error, EOF, spawn, 100 exact-FD and group-interrupt controls. Android's
  112 workflow, 13 retirement and 45 original fixture regressions, CLI/curl
  controls and both cold installers also pass. Counted shared library binding
  growth is included in the stage's 606-byte net reduction. An identified
  1,000-record resolution workload retains exact output; native timings are
  slower than the frozen Python implementation and are recorded in its receipt.
- N64 construction passes 73 complete frozen/native controls per profile,
  three actual HTTP comparisons, 100 exact-FD hashes, a group interruption
  pair and five forced exits. All 81 OpenGothic and 74 shared package controls
  repeat. Fresh pinned upstream archives are byte-identical to the original
  builds on ARM64 and x86-64, with the unchanged bridge fixture passing. Cold
  distributed source builds and five CLI controls pass on both ABIs. The
  zero-credit parser correction repeats the whole corpus and actual archives,
  adding ten unavailable-compiler/query help/usage/argument comparisons.
- Dota launch workflows pass 152 complete comparisons, 18 signatures, ten
  markers, four actual module imports, nine screenshots, six reader policies,
  twelve weak-owner controls and the unchanged eight original/native fixtures
  per profile. Nine stop, four dynamic exception-class, fifteen read-context
  and fifteen owner controls pass, with 100 complete PTY/server/worker
  retirements returning to the exact final FD baseline. Both ABIs pass cold
  installation and seven CLI plus six unavailable-compiler controls. Frozen
  and native prepared ARM guests preserve the same `VINIX-DOTA2-PROBE-FAIL`
  before game launch, 25 reads/51,200 bytes/zero errors and final capture.
  This is baseline-failure parity; no game, rendering or fresh kernel pass
  is claimed. Original non-OSError stop cleanup omissions are identified
  separately from preserved normal cleanup behavior.
- VOffice passes 111 helper/thread-worker comparisons, 41 complete build/cache
  plans and 37 manager, suppression, exception-class and caller-binding
  controls per profile, 100 queries with exact final FD equality and group
  interruption after all three workers start. The unchanged independent
  complete shell fixture passes per profile and with actual cold compilation
  on both ABIs. Five unavailable-compiler/query CLI pairs preserve the parser;
  65 native source inputs and three module symlinks each invalidate the key,
  and restoring each input restores the exact original key. New inputs follow
  the unchanged ordered cache policy. ENOSPC interrupted intermediate source
  and cold fixtures; all affected gates passed after disk recovery, without
  changing fixture assertions or deadlines. These host checks use the original
  fake-toolchain fixture and claim no fresh VOffice application or guest build.

Machine-local evidence is under `/Users/alex/.cache/vinix-python-to-v/`:

| Stage directory | Qualified receipt | SHA256 |
| --- | --- | --- |
| `g13-layout-20261008` | `final-wide-source-qualification-v2.json` | `764b6228e84cf4604d1a0613aa240f1d89ec887e6f456066524665f205da9d5e` |
| `cpu-feature-policy-20261008` | `qualified-differential.json` | `81cc725dbbb222983a3393176659260948c4c6d06742d2d9d8aa42506dcca5a4` |
| `agx-trace-20261008/final-v2` | `pre-retirement-validation.json` | `517f985360c37009eb0fde8e89c06478af11c68b04ec85ba6dba33e83611ddcf` |
| `g13-contract-20261008` | `final-qualification-v2.json` | `82b2490e20dc7a0432dd24e445cfbd09ee69b7db5249fe071f681b5213751571` |
| `alloc-compare-20261008` | `final-qualification.json` | `635b83e54f2740841689ebbd42a7fbbeb6c2002385023e295031ddc7a5f5768f` |
| `cpu-mask-20261008` | `qualified-differential.json` | `26991750c66c6fea2f9a0d216a4658dfedc83f57a58961c63e443c10810909b8` |
| `irq-context-20261008` | `qualified-differential.json` | `c9682c6a274d92a82e38307602772e31d64193f279ca09d3a8f1a0518a88d807` |
| `pagefault-20261008` | `qualified-differential.json` | `b790c3692173edab83cc1d6c3d2d5908ec93ab72028c5a71f2fe1e2a75f47032` |
| `agx-extract-20261008/final` | `precommit-validation.json` | `7494ef3012d3fd3ed1404f66c9beeecb7d0cdffc835e28a86935bca217da54af` |
| `kernel-compare-20261008` | `final-qualification.json` | `51e8f6b99a83a0e1b324f93b7a2bd00fa6ba3b4becde57041596a9495699765b` |
| `scalar-20261008` | `qualified-differential.json` | `7b6b7f1b49faab37067e01a634f9c2ef44ffef93fb86ff87d3f2cdcee0c383bd` |
| `g17-plan-20261008` | `final-qualification-v1.json` | `654687dc35ee1c3f4a8b728b29973e7a0c3570623514c55cd1fdebb470ffcd05` |
| `uaccess-20261008` | `qualified-differential.json` | `3a09d15a59eebbbfa52f4edf59495072941087cbe145fdb9fece37b3bb7ee730` |
| `nocache-20261008` | `qualified-differential.json` | `db8fc5edcc7a632ad24ff8d52bf3725d84a9391c477988d88420fc879fd3b147` |
| `user-pointer-20261008` | `qualified-differential.json` | `ffd668b7e0b1ce5ffc1de3b7faeed5b5f125b761f6a6a9b65a470ebc1f7aa6ae` |
| `agx-recovery-20261008/final` | `precommit-validation.json` | `06dbaf60ec1254e4542815831d7cd956e0a90fd866941c379941750e2cd678f5` |
| `abi-generator-20261008` | `qualified-differential.json` | `5dfac93ff16b90315ce8a4f72e9ce18ce4a57d9054b7acd4e4d1db7069a619a3` |
| `abi-make-20261008` | `qualification.json` | `a2d4cd0684cbcac830672234255faa17f56091855cec15dfeb6db99b63784f8d` |
| `g17-power-20261008` | `final-qualification-v1.json` | `db7ca98b76c32ff4d812db2ad2250b6276f433efa2a84641360b75a5161d0162` |
| `overflow-types-20261008` | `qualified-differential.json` | `8b405a83166d6bc694d2db9d037397c70c4d106585e81f004cec7b1284f8ca68` |
| `agx-adt-20261008/final` | `precommit-validation-v2.json` | `576bcd4ed65b47c183390c22af548c5ad1bf0eb5025183b9413b3788affb84a6` |
| `mac-inspect-20261008/final-v2` | `qualification.json` | `d35a167b17766851319a55692d435a80c10e3794d923f5a3e4481f28e7f72aa3` |
| `pci-topology-20261008/final-v2` | `qualified-final.json` | `80ce667aaefeca08f348c33756926daa9d98f653fc25c91a8992bf7daed0230a` |
| `agx-t8103-20261008/final` | `qualification.json` | `a49e0a3a0d1c24926c214ebf0557281ca09d94246e314855b849ed48e2eb66c8` |
| `g17-expression-20261008` | `final-qualification-v1.json` | `275e897b66eda2a44802fd6fec9837936de072d048aa511ff4efd4972ee235b4` |
| `bounds-foundation-20261008` | `qualified-differential.json` | `f622b8fa789e0c6ac48834dd30d85c1981ba7efbf3ed259546488688295ca76c` |
| `heap-model-20261008/final-v2` | `qualification.json` | `0fbd8e02f55065e26be8d1a531924cba8ad9d20f7618286580215c3c86c01c60` |
| `agx-t6050-20261008/final` | `qualification.json` | `f6373c11c8f5a46a302d17086de12f52597cee739e8ae2f5c19d4649c1f2891f` |
| `zone-model-20261008/final-v1` | `qualification.json` | `1fdcbb11cc4385b2b6d909ed0f5fef21278815a1615766511ee4cffbc1713b6d` |
| `zone-model-20261008/release-compatible-v3` | `qualification.json` | `433b9dfade73bfa3341ae26c4458d2886d8eb677105ef4c616fc3a4528e08863` |
| `g17-command-20261008` | `final-qualification-v1.json` | `c155a371887a0728da1f87182c1819dae195ed6f94fad7f067263ef0c85069c3` |
| `bounds-controller-20261008` | `qualification.json` | `4a514d4e0824591b5438ba350356f45420ff9403dc95e1824ca4c32c7863543a` |
| `bounds-make-20261008` | `qualification.json` | `64627194efb2bde571c58928e58f6418c0b0f12b2b6412aa9bacc7fcc952da13` |
| `agx-t6050-contracts2-20261008/final` | `qualification.json` | `e8f16f73c39fce61da58defb41e017c41ce34abcbdb241a2eeeff9c7eb737d5e` |
| `upstream-source-20261008` | `qualification.json` | `6462c4c499f7327d56d21646a958309fcde3dae93ad37715ab6a30630b43b801` |
| `xnu-reference-20261008/final-v4` | `qualification.json` | `d758074c6892ec7e0ce35359e3210224dcc7b581b038b5373d22b2a731f67a56` |
| `g17-runtime-20261008` | `final-qualification-v1.json` | `6220ca770db0656414899153fd0513f99991eea7a617b72021ab1823c0dd7206` |
| `agx-t6050-dashboard-20261008/final` | `qualification.json` | `769475a6e350a79417d93334a11e1432b8bb2668b7696b9b89720a1c7403bb68` |
| `asm-headers-20261008` | `qualification.json` | `f69848e63d5df306b45d763e6d1b69e6107d84a6612ab76bf34693c68d42611b` |
| `agx-t6050-firmware-20261008/final` | `qualification.json` | `f1732269659b7160451dcf7baf9099975d38052c7cc263570b1b96a023f3e970` |
| `smp-types-20261008` | `qualification.json` | `06bae0188c0dd854a5f03cf60aeaf1326098b59f04c4cad4781e56a59451f850` |
| `desktop-perf-foundation-20261008/final-v3` | `qualification.json` | `30ea179c963746ce60b9aaec1e89887ac4e0605129180c289fe2ead56200877f` |
| `agx-t6050-image-proofs-20261008/final` | `qualification.json` | `40e4a1721b7e4aad3f7c5a7a1a99ceb87d626cb1239d531095f9835080076e29` |
| `static-page-types-20261008` | `qualification.json` | `489b78a3bf256e75e4e1b1100e55f2e25ee59e0f8a3b9a86e38faeecdd721780` |
| `g17-config-20261008` | `final-qualification-v2.json` | `a82b731d518630334c59710da44e3c8a41788c8d31f08259f3d578772cda4324` |
| `special-insns-20261008` | `qualification.json` | `30ac4df57a0f9d2cef4fe1218d221f4f31ad941cf2d088f8a677ca44868d019b` |
| `agx-t6050-topology-20261008/final` | `qualification.json` | `08fd4006fa1aa8563fc4ab4a90ba48985d284834e35f18cccfec52b611c64c18` |
| `fpu-headers-20261008` | `qualification.json` | `c52fe2ee6f994e25d9690cd623338b69f85b18092a159bfa07d407daa6369998` |
| `g17-caller-span-20261008` | `qualification.json` | `61b651601e28491fa91a15fee410fefe7219ff5572ee9189db9870f36fa23dcf` |
| `header-fixtures-20261008` | `qualification.json` | `c4fb28c74dca09be4b64f9b9de8f14c122558b23d7b1ad906f6e3fac7b12d5ff` |
| `agx-t6050-patchbay-20261008/final` | `qualification.json` | `ba5d8acd7f5f9aaa60aff479c94adfe24f5f923e8b8ac1ed8878e887f822bc4b` |
| `overflow-policy-20261008` | `qualification.json` | `db2f40b1b3a90ef9571fe3e766d09148f9350018babcd75ba69fc000259f6ca1` |
| `verified-root-20261008` | `qualification-final.json` | `fa1e9f27d62e28b6bda0b36afacaf28dc8cb567204fb1c78ef3b84ff95fc79b8` |
| `agx-t6050-controllers-20261008/final` | `qualification.json` | `e18557239ff281a223b1ad21ad3d666a29394637d1e7092f84d55a926a33a328` |
| `agx-t6050-public-20261008/final` | `qualification.json` | `52d3e62152da8c99fb6c451d21ead069c450584f75d27a5ab28c5126fa54ba3a` |
| `g17-events-20261008` | `qualification.json` | `264d3280901c3cffeefaf9d34d013f67185c77c687ee4ce2d3bc8ff48cbea9cd` |
| `verified-boot-policy-20261008` | `qualification-final.json` | `ed7773e94dbc37de08d302aabbc9d436a61d389e7f90759e185d577d092c8b2c` |
| `fpu-cli-order-20261008` | `qualification.json` | `bb2bc4e0f863003a688a041f3e8853c15305b00a4d2fb76ef20d151dee16a057` |
| `android-tools-20261008/validators-final` | `qualification.json` | `7b69bf3434e5a7c607ea14305cf1c83ff03365e3b15ab14821c750e6440c1a75` |
| `g17-layout-20261008` | `qualification.json` | `726b88833cccd40064fe112f1c879cb9476952517f705ba22d0cdbd532c21fcc` |
| `build-cache-20261008` | `qualification.json` | `453886473c329517cd7c9c5eceb557209af1de7aeb040adcb1c67dd6ea27cb18` |
| `module-generator-20261008` | `qualification.json` | `4cab5ece6d867dac5b0bbe2a6dd007b9ccd16e5c3d74bec00ec8698c8534cf38` |
| `g17-census-20261008` | `qualification.json` | `d1ba91e4503688fcf807f9474253a6c7fc9a4f3ba96d985629c5fd2a1abeb495` |
| `build-cache-staging-20261008` | `qualification.json` | `a6334328981ffb818a3da6e54cc45bd2d46158473045a821d2be745db4faeb1d` |
| `android-runtime-20261008/final` | `qualification.json` | `914f968431675a87ce21018953e425836e5020921f724b632af0edaaf13963bf` |
| `dota-family-20261008` | `controller-qualification.json` | `0ca063ee1f03719bfe5f23cefc7efb4c29a1e74244258ddcbae64ea1adbdbb41` |
| `android-launcher-20261008/final` | `qualification.json` | `ecdb954dd9c1241d35cb1f848f5d096b1adabb1579b3a543097afa2cad593e3b` |
| `g17-legacy-20261008` | `qualification.json` | `cc6ea5a7454b0cd4fdfcddbe089ec1bc5f4155e60c6948cbf36007f6de69f621` |
| `dota-family-20261008` | `launcher-qualification.json` | `0acf61fc4e8f1e9edfbb0e41bab8b50d300c1022b617a8743b61bbc3ed243a99` |
| `g17-controller-20261008` | `qualification.json` | `0db41df0ae96123b990df6dde42b432ee1557b76eac5fe2858c28e7282bd2866` |
| `g17-public-20261008` | `qualification.json` | `e2c65af7cc8a5784e4c78e6d028b124887883f9c7b80a2523b980e15feced1a0` |
| `android-probes-20261008/final` | `qualification.json` | `3b6f5e8b41ee9a01afc4ec4c29c253f97ced9e6d353d64df127db1deeb7356d3` |
| `dota-family-20261008` | `transcript-qualification.json` | `4fba2f7fccf4b4ea64107913978ebdb7b44075fc49889b00aa850b4b21d979e1` |
| `android-simple-probes-20261008/final` | `qualification.json` | `f8dfe210e482b36c627125e33ce5f7277917faa034e0a1a7be84119f5765a067` |
| `qemu-core-controllers-20261008` | `qualification.json` | `6e2998310e347898e344e6c7ea9c7f1c960cb680df26aac34e423f10d22213df` |
| `dota-family-20261008` | `work-dir-qualification.json` | `4a181c6a6034df08b6b5d0dca4c6762f046fa227129f0c0523c8b87d96b4f5a3` |
| `agx-host-20261008` | `stack-qualification.json` | `c908a95a1e2204cac8c18141058cfea1da80cf00baf7a1cb48fad6fa32dfbd52` |
| `android-run-helpers-20261008/final` | `qualification.json` | `cb54627b79d909d5cbcde3c3afbd94799279fb8afbea58b6fc3d3f6614f2016c` |
| `android-run-helpers-20261008/final` | `post-commit.json` | `195e6fa0a15b7c7e83297d0c6737010b54834f5dab693eb4f7fc502f98ca5510` |
| `agx-host-20261008` | `qualification.json` | `b6593e7c09dc4e829f19c8f0f75b8981bc71bd360acf342c2fe690ec091a7965` |
| `agx-host-20261008` | `post-retirement.json` | `ee8a352ce2728be4c7a5ea88f454d5a5416876040976a8926f71d44a688f1d5f` |
| `apple-host-controllers-20261008` | `qualification.json` | `f0937c0ac17f831744a5a9c34f4c6b059fcfafc86c3cf6490ebfee91beb50ea8` |
| `apple-host-controllers-20261008` | `post-commit-verification.json` | `716a351c1ad9892d7734ac02a7e3083351627d7c0fe7f5060754892e45069e79` |
| `dota-family-20261008/build-policy-stage` | `policy-qualification.json` | `657e5daac7317f708f9336e23f4af4c46feccec4e70115f38dadadaa1c03bfbf` |
| `dota-family-20261008/build-policy-stage` | `policy-committed.json` | `0ecf565cef7bf2f11656379077ed5e4d906ccd56c38ec472cf1a1024456886b7` |
| `android-advanced-probes-20261008/final` | `qualification.json` | `70f26f52339bf0ddfc211941404c4db9585b0466878c3497e75771efee67819b` |
| `android-advanced-probes-20261008/final` | `post-commit.json` | `3af5518d6aafc09bdd8d6b8f96144981f846730f0fa20fff587ea48a4c7419df` |
| `android-deployment-20261008/final` | `qualification.json` | `43a1e6cee3411735b8a6be4a584b9e37b76a67a3a87058f606260ce984d890b4` |
| `android-deployment-20261008/final` | `post-commit.json` | `2089fa875500bfd1dcb6b1a0f5f3a0bd198806182c9dbde4bb4c1028bc30b464` |
| `agx-trace-runner-20261008` | `qualification.json` | `856daac0240868bc0d3857b040052ced94d9ffeb6d5b1e0f05579a90a20f464d` |
| `agx-trace-runner-20261008` | `post.json` | `f6b2aa8feb7f48525c2c562578ad8826f6eedcf6b4592de6b5b4990528aced07` |
| `android-runtime-fixtures-20261008/final` | `qualification.json` | `1e52c2bf778aea3882f402afe5afc0bc27491bbfdf082e34fb233b1937ac7eb8` |
| `android-runtime-fixtures-20261008/final` | `post-commit.json` | `4789eaab0edd78acf6c1b2cb1a3f6d02f5082f61765f92732dc2e0a14a7e4e97` |
| `font-generator-20261008` | `qualification.json` | `76dd53addbb3c3cb442afef7e80ff4348aba62fb122885faf1933d4150cd887a` |
| `font-generator-20261008` | `post-commit.json` | `6a5daf1d607044d5be47484e77736b27806f3eaef8868cdde6d88b8fe5f07d03` |
| `agx-host-20261008` | `preference-qualification.json` | `876ada7bb2edf4bdf2ed54635aed585010557c972862d0d89c5b21ee9ba5bcca` |
| `agx-trace-runner-20261008` | `preference-api-qualification.json` | `0f5261b0f44958880f426db86a7b322102c2a10c36cc01bc5c779c1e0cd47850` |
| `agx-native-builder-20261008` | `schema-qualification.json` | `803db3ab268997be6c5be887c77a123258ed56add1b6a63d8e85f75d45c48912` |
| `android-musl-fixtures-20261008/final` | `qualification.json` | `11e19cc5c880d44fc52b2e25ffe196d6ca7a4b82a6b6d5fb8be12bceb27649c9` |
| `android-musl-fixtures-20261008/final` | `post-commit.json` | `7650a1fd12f54b7967b5c50ed0db6ee602e13d5bd0948a617a4059a7d3048cf1` |
| `agx-native-builder-20261008` | `qualification.json` | `6a7db91e1e471210d494c572d5ef0312664a2253063d05e7a6070f023a746892` |
| `agx-native-builder-20261008` | `post-commit.json` | `9e8e32284cf4aead49e5b9250e05138bd0c1a83f136f29c5a5cda88e1fa19af4` |
| `ovmf-fixtures-20261008` | `qualification.json` | `12c20d64d8d7ab5e1d939180b6465e21dccce5b9aaf616c28d76a4b1a2670558` |
| `ovmf-fixtures-20261008` | `post-commit.json` | `b1e44ed2d3f6a9bc67a2be9149cbac34ddf038ecfe56697a31e60b42afcadfd1` |
| `android-boot-fixtures-20261008/final` | `qualification.json` | `3233e9c899bf6eb7ea9361622f8e8f2576f1134e820f8ad07eee80e11391dd18` |
| `android-boot-fixtures-20261008/final` | `post-commit.json` | `ab60d592909b0a9d46214207a7a580848b46685b9bff60af3dad163ddaea3bdb` |
| `dota-family-20261008/qemu-builder-stage` | `qemu-builder-qualification.json` | `3cb16adaba86cfe58348737e6ab6a6f361b1576d03aab88bd56dadcd705bf5f6` |
| `dota-family-20261008/qemu-builder-stage` | `qemu-builder-committed.json` | `b6565fe1ed936be1f88ab9ec18888ed9a8057f35206de31fe40484278b8d71b0` |
| `generated-policy-host-20261008` | `qualification.json` | `640b318e32596e2649fb5b7ef6d1405b562208ee33e390b70ff7e18cdc90e655` |
| `generated-policy-host-20261008` | `post-commit.json` | `63d48b78635cdbeedd3469ac09132d111ab6fd03993e60f7422ddd166649df7e` |
| `agx-pty-20261008` | `qualification.json` | `5c5be3aad8657c700dffeec59e3012fd143e75516f933540bf4e52175c946d73` |
| `agx-pty-20261008` | `post.json` | `e68df69d699520fe5bb51ebfdf63a8c747a39b2cef8fd1127148eb5a5f52afe6` |
| `generated-policy-host-20261008` | `assembly-qualification.json` | `edccc6ac6b76c3bc36a42dc00b309d54bf6d8bde7cad3e9556b4a85cb27f3a31` |
| `generated-policy-host-20261008` | `assembly-post-commit.json` | `26c61d5771b1bc7c0d6a5e2b203392d9c428a0f600ebf8a156e18cd53a7bbcae` |
| `android-boot-builder-20261008` | `qualification.json` | `e6f4903c40636add23b0d29efa0222e1bd91c92694140ff7de81a15fb35620d3` |
| `android-boot-builder-20261008` | `post-commit.json` | `ae393c94d18adabb51c54b0124556974e25ba328ab2a2c596040e00b93db374b` |
| `linuxkpi-host-controllers-20261008` | `qualification-final.json` | `97b20081e3848c37deb9c31a69b46dc5e7bd9e22ddfd45ecc252cc2872fc9232` |
| `linuxkpi-host-controllers-20261008` | `postcommit.json` | `58c739a5f1d3d1be4bcbc089b8969fe00a0bbc7631a431138d4b479fc4618129` |
| `desktop-stage-20261008` | `qualification.json` | `be5524894ae8de78b983a704f393a07e10e05e6ec8a82992e03be11d8e4b07d0` |
| `desktop-stage-20261008` | `post-commit.json` | `12836456a4fa9debe7774c9c63ac3413fa5ecbb7363764906687f540c48b0204` |
| `android-atl-fixtures-20261008` | `qualification.json` | `27fc2994b3768432c17b475097569e57db5ca4579625b5d1f3e7a1ca6d14b617` |
| `android-atl-fixtures-20261008` | `post-commit.json` | `fac1d1e13d916c4ec4c685ae53c7645cd935fc1b0a0fb5ba3d27fb3b92e102c3` |
| `qemu-core-pty-20261008` | `qualification.json` | `a767ef5b7a1d5e5b7970430b66ccc5e2edde9b8103e6ab935043b8ed880880fd` |
| `qemu-core-pty-20261008` | `post.json` | `4d58c84f7cec3538260ac88d22858d8e6e08db9d05932f8984851954ac51d877` |
| `linuxkpi-host-controllers-20261008` | `audit-qualification-final.json` | `53b7729ae22bbc0f89332b9dd3943a960b1fda0a520de5174f4d643f879a3a4a` |
| `linuxkpi-host-controllers-20261008` | `audit-postcommit.json` | `0981d12ae3eb10bbb9ae399bfc5450a1ef143991b8d2be36d8b24adfaac4ef3e` |
| `dota-preparation-20261008` | `qualification.json` | `1c0088a171894ccaeb4cfb8ca9222a0ab05e88d7b225c455d8b55aed48d3ad2c` |
| `dota-preparation-20261008` | `post-commit.json` | `e1eb4e9e82cc0a927850279a43f7540ae9fabf0def4435e6ad2733196442f1e1` |
| `linuxkpi-guest-20261008` | `qualification.json` | `7c6b2910d08aeac98a85278afa4bae2f0958d757334447304ce49e686c00def0` |
| `linuxkpi-guest-20261008` | `post-commit.json` | `ec199dacf1e4b12b2650cfb95b0d0b893040d8f545e005622d96fe9c398527f8` |
| `android-run-orchestration-20261008` | `qualification.json` | `b8993234dd6074b8fdc0dbfec896e34de16d9f9ea0a304df738bb6c5d98be670` |
| `android-run-orchestration-20261008` | `postcommit.json` | `0aa30ef012fb8d860fa018f32bb439eb03bdc4f3db2aba8b854feffa37bbf626` |
| `android-run-result-20261008` | `qualification.json` | `6177db32240029f3604ed9431df5a698df988e01af7fd6748fd4119777f85b84` |
| `android-run-result-20261008` | `postcommit.json` | `88a2cdad4ea8b12625334d19a0154356389821c1e860193b6e35ce1101384ba4` |
| `minecraft-fetcher-20261008` | `qualification.json` | `db89ad28755f2a1e79937a695cccf3c0099e340ed0f209ea6baf25f9ec2a8cdc` |
| `minecraft-fetcher-20261008` | `post-commit.json` | `3f39d77d9d09e13fc2f11e182902900f9f267b4548888572a012212d85056f05` |
| `vulkan-stage-20261008` | `qualification-final.json` | `7027d3a2336fbc3bf834911b60933f631991010ec3f8f6cbbb399ce4c496c5dd` |
| `vulkan-stage-20261008` | `postcommit.json` | `522edbf55f6ec086195a742c08271d83117072b44f07e7a3550b84d603601b50` |
| `android-run-orchestration-20261008` | `manager-qualification.json` | `bd4eb1ef5e734702b03d0a95f31f5319a939c0b2d01f006129e4713e560d787c` |
| `android-run-orchestration-20261008` | `manager-postcommit.json` | `b1fd606117d0cf1f4be64a861592bbe5e44fe3aab631d5bf75366d1142d03378` |
| `dota-preparation-context-20261008` | `qualification.json` | `7bf8ba05e9c81a26bd4aa7aaff840072192b93aff45c971a39325fcf7079b99e` |
| `dota-preparation-context-20261008` | `post-commit.json` | `c40b650eb84c629ecd56c9a9284d46fce3795bd2aa52a0ed3ca7ef8aa6331bdd` |
| `g17-binding-20261008` | `qualification.json` | `c9c553bfe6b994f5b09852f00e220a4aa431ca04e5d718431a640f7f3c6d5e4b` |
| `g17-binding-20261008` | `post-commit.json` | `4e41b3495290304f8a6f3b7f0b53ee9c2927e3497a97a96e4f410ba16b4ffbc8` |
| `t6050-binding-20261008` | `qualification.json` | `521a1def63db203ec967489a7d29e33ce67b34070100a1a6738c36c864f1e091` |
| `t6050-binding-20261008` | `post-commit.json` | `a0dfe0547a037809b2af3910fc52e09e0c85b29d4b58fdab70189613a638d79d` |
| `android-vm-plan-20261008` | `qualification.json` | `e1222df03ed021dc372f44a7a9275d7a9b6f0bfbbf10d00b384b4cf2a575632c` |
| `android-vm-plan-20261008` | `postcommit.json` | `5e10de64fa7186b45915b818db4393295a9d1e18d3977d89441d5a7a3ae6ec0f` |
| `android-input-policy-20261008` | `qualification.json` | `f968245858dfc30ef4f09b58a5562959c585d5a2a12392c9d9fbce57f433e6f4` |
| `android-input-policy-20261008` | `postcommit.json` | `8d0226b4146e7d8c3c074d12c2ff73576340fd4acb3fe453bde978b83f883c2b` |
| `desktop-perf-runner-20261008` | `qualification.json` | `9d2693eaaa53a2ad3513c43b97b5f019a14e426737cbfbba7fb7b6f125a66378` |
| `desktop-perf-runner-20261008` | `postcommit.json` | `5f98723986191ad03664ba75f99010b5286cb58f27af02a6aa98c57b9fea10a6` |
| `android-run-transport-20261008` | `qualification.json` | `cebf595aeb33b442ab3a898e469dbf4f5598c2dc2ead6098b2c14b6fb94b147a` |
| `android-run-transport-20261008` | `postcommit.json` | `46c14c0ca7d4b36204c6a4a3dd786f6200d711471233c7b46a542d44325ee122` |
| `shared-host-process-20261008` | `qualification.json` | `59d1fcbc8614c03c39f34f2f0fc817212959b5937a4f10a07bc55496ab86fde5` |
| `shared-host-process-20261008` | `postcommit.json` | `7837217300bf52bb647cf7a8f0d709521968c38296de5c1668e6f496d21f185a` |
| `shared-host-process-20261008` | `eof-qualification.json` | `a8909fcaa2199f7e758cb319e7315d629d7620cc368fb6fcc042a754166e491f` |
| `shared-host-process-20261008` | `eof-postcommit.json` | `1be60100faa37fce168615b86bbd728079ffa7457d787182af24766fea8816dc` |
| `kernel-gap-guest-20261008` | `qualification.json` | `d50e7b74456a68051b19989173d1ad453e606d2aa792420c9fd03804d98c716c` |
| `kernel-gap-guest-20261008` | `post-commit.json` | `11a0d991bb1c948f0f1bb0660ea0a7bf8f29c0c59291d2817a69598d8ce8a1e7` |
| `qemu-package-store-20261008` | `production-qualification-final.json` | `ab27fd1e167bd2e3693c63912d93a8ac648a81fc0056d98d913463e00a5ad55e` |
| `qemu-package-store-20261008` | `production-postcommit.json` | `bf336339b78b9fc4e54d21cecb8ebac18adc694c1442469b0e9c2123e51f4d08` |
| `vulkan-stage-20261008` | `fixture-qualification-final.json` | `ae91d7a55cf2c62cd448d893050237e1249f44cb0d0222e8925bd451272f73d0` |
| `vulkan-stage-20261008` | `fixture-postcommit.json` | `faadafce7b1fd5c1658b1f312512a00beb9bddb452859f26fd9f8e2b31f25d5f` |
| `android-supervisor-20261008` | `qualification.json` | `4bf06671b73925df5bb5062bd7f3e70e0e8f7024c204aeb8b6574f7d07d1106f` |
| `android-supervisor-20261008` | `postcommit.json` | `ccf415ea1e76d1ea28a40ae7cf1b2ed72c93e9a91aeb0dcd776707c7e090c76a` |
| `dota-guest-workflow-20261008` | `qualification.json` | `14ab28e5d9ca7f00760564bdf091d77dc5b40d628196a23e63fd7287458474dc` |
| `dota-guest-workflow-20261008` | `post-commit.json` | `0059d32760f12181e166853da4dc0fc5c65c4b289e0374529631b484f6e5a08c` |
| `qemu-package-store-20261008` | `fixture-qualification-final.json` | `b2f33885de4f056722d8f57f898af08684cc5ec150dcbc32aa40a187a90f01a9` |
| `qemu-package-store-20261008` | `fixture-postcommit.json` | `6bc39b9efd868c853c181a7e83e610ab219ff2a1ac578a6bcbf7a7443e9df41a` |
| `dota-ext2-export-20261008` | `qualification.json` | `c8f47d2b75bf40bc3d38d9cb165919224fe38244e8990f4e04d30e3a76a97d24` |
| `dota-ext2-export-20261008` | `postcommit.json` | `949b91e50c004ed5e5324f40cdb4a9d74581323cf02f9dbf7ec331173f3aa39f` |
| `dota-ext2-fixture-20261009` | `qualification.json` | `f84d1b7f77f2dd11aa4ce29133ec285d5114789b61c52229900fa8017d128fe0` |
| `dota-ext2-fixture-20261009` | `postcommit.json` | `9194fe02e18089a735814f6bdd31441730184b7fe7602cf8eb4e9b5cd8e6b641` |
| `dota-vulkan-guest-20261009` | `qualification.json` | `37ca72d804c4a294ad1b4546349a1cdd80f2778e38550e777c7e09c7ce1eb1af` |
| `dota-vulkan-guest-20261009` | `post-commit.json` | `53563c7a3f522a4d81074bb94ae4367e3c1ea7e9b1cdd0b5a37ca7cc5ee62b13` |
| `android-runtime-builder-20261009` | `qualification.json` | `f4c7eebe02dcc7fd51f23a0ac30d83ce2cb763087e27b9f4dd4c14d8f0c214a4` |
| `android-runtime-builder-20261009` | `post-commit.json` | `6da726a60a1234b53486dc318032097d3db1b81921ef6b4f2a40a597aa36bc16` |
| `dota-ext2-protocol-20261009` | `qualification.json` | `12f32d8dbac63485c220da9c768af50d5a2cd6233292ec9776866af69e7d5375` |
| `dota-ext2-protocol-20261009` | `postcommit.json` | `f135e2ffacd697f1d9a077eafb95e7ac400cee337f011b283b13d7cc4627bdc9` |
| `opengothic-build-20261009` | `qualification-final.json` | `d268fb87df1e0b9e1e4bec206b03794ced9b72c4657532c695bfa15d85e7af45` |
| `opengothic-build-20261009` | `postcommit.json` | `a9b1c869464bb788be6705a23ea13029ea812ecdb12fd8bcdf4af718e57a363b` |
| `android-helper-concurrency-20261008` | `qualification.json` | `c64f1fa1f7b0985e6bd8ea20c2b35545fcd754871bd4b3eb0835752e15638656` |
| `android-helper-concurrency-20261008` | `postcommit.json` | `3d8fb191902f072d83c615a9eddd162ea1dca6406888334d0272710fefe4f9ed` |
| `android-manager-traceback-20261009` | `qualification.json` | `4ec6d6dcdacd8a6e771cae598fe21814f96241b85b41a7a9feda8c2f9081cc2c` |
| `android-manager-traceback-20261009` | `postcommit.json` | `1e4f7fd01597f75b39224c5eeb7ed2d397eb042b763c38bd96cd7d180c2cfec6` |
| `android-manager-mutation-20261009` | `qualification.json` | `abc91b395906b7c7e84de38bc53ee9baaaaf11287a8e445ee9d899351b1891e0` |
| `android-manager-mutation-20261009` | `postcommit.json` | `d8486361cfd94f9340a03278f47f4ff8e07e534685ab7d5198d890db0b6ca261` |
| `vulkan-stage-20261008` | `traceback-qualification-final.json` | `0affc3f50de32c4ec1a9d294556f3aee76e58f0816e5b09b586f38010d1c469c` |
| `vulkan-stage-20261008` | `traceback-postcommit.json` | `7be13b99afd7b3bbc91835af62d10087d34acdbc7ce0249cc02f03a7bb8dbdd3` |
| `traceback-property-20261009` | `qualification.json` | `e857590956c08c8cf8426a926f2e010106fe8135266d4de652bac939bba6507c` |
| `traceback-property-20261009` | `postcommit.json` | `392dd4eb273c35d7605e5227629bb028e492f36d2783055117e5bece6a527ec1` |
| `alpine-resolver-20261009` | `qualification.json` | `8e77dbe90ab4b46ce8011569ebcc5cb92a4e97ce4dbc27a46fcac0ba22a8ad4c` |
| `alpine-resolver-20261009` | `post-commit.json` | `3abce422d46e15f5dfd39402eddbaf1bf890983a166cf833221cf151128421cd` |
| `n64-builder-20261009` | `qualification-final.json` | `b318d71ae65f03a9e6605b3c19ba26d1759c979fc17d0a90ddd9b065dbf40cf4` |
| `n64-builder-20261009` | `postcommit.json` | `fa5fc711fcbe2179760d9409c0064c84f26270609edf6afec977235ff726197d` |
| `dota-game-guest-20261009` | `qualification.json` | `b295ae8bc2035d4f2c84cf0113c64e6da6e3962e6ddb3e960b15255e3231035a` |
| `dota-game-guest-20261009` | `post-commit.json` | `00cb37b2ce84f07057e9e09ab5b265a0962dbd39ed437987e0715642f5d7459a` |
| `voffice-builder-20261009` | `qualification.json` | `b846fa9f503e2898c8a583057104cfecade44f23386c4f28dd8d648b2ca2607d` |
| `voffice-builder-20261009` | `postcommit.json` | `e394599bb3aca630d3a29a40cc67c10a412c8902e4cefc25bc76e29c0c4f25fb` |
| `package-raise-binding-20261009` | `qualification.json` | `09014b2ff5a1c66f9cefd002db10211a4ac247d07d3f1f3459cc55b854796fd2` |
| `package-raise-binding-20261009` | `postcommit.json` | `38eeaef6c6eeb803a1c6bb3795d4891b372d83f29e953728ce969ebf7cc95ded` |
| `n64-cli-20261009` | `qualification.json` | `53ad69397b85f0e804a37ddca585fa65d6da027568a99496a8b118f088a5024a` |
| `n64-cli-20261009` | `postcommit.json` | `d2088754fa0a1387ae9a40b6659e41b87c606274006b48e89f1200be1945389c` |

The allocation comparator's `alloc-compare-20261008/final-qualification.json`
and `postcommit.json` bind its source, compiler, control results and exact
seven-path commit. Each other stage also has a post-commit path/input receipt.
Local caches are supporting evidence, not a required dependency of the tools.

## Continuing work

Complete Android/Dota/AGX guest and build workflows, native independent fixture
controllers and remaining host build tools are active.
They count only after qualification and exact-path commits. Native numeric
decoding must preserve large provenance timestamps as well as addresses; decoding an unconstrained JSON integer through `f64` loses
information. When an unported Python caller still imports an API, retain a
narrow adapter to the native implementation until its caller is ported too.

Remaining large scopes include Android/Dota build and guest runners,
other build tooling, desktop generators and benchmark controllers.
Keep original protocol, build profile, fixture identity, deadlines, allocation
and lifetime behavior. Commit finished stages using only reviewed owned paths,
then regenerate the language inventory from an explicit committed source SHA.
