# Python to V migration

The target is now **0% committed Python**, replacing maintained implementations,
command entrypoints and tests with native V. The work is in progress; zero has
not been reached. At source `0a74a26758fce778e4565c826589f76ec858ee10`,
Linguist 7.27.0 reports **Python 0.23%** (11 files, 97,587 bytes) and
**V 83.78%** (3,961 files, 36,102,019 bytes). The complete committed-blob inventory and reproduction
command are in [linguist-files.md](linguist-files.md).

The starting snapshot, `9a70678887e1188926d6c8eacfc6b8f1432438f6`, counted
5,206,285 Python bytes in 523 files, or 12.51% of 41,610,938 classified bytes.
The measured net reduction so far is **5,108,698 Python bytes**. All remaining
97,587 classified Python bytes must be addressed to reach zero. Absolute
bytes and the presence of Python implementations are the completion criteria;
the relative percentage also changes with other languages. In particular,
the concurrent font-atlas compression in `9013d012` removed substantial V
source text, raising Python's share despite a reduction in Python bytes.

No Linguist attributes changed. First-party code and fixtures remain counted;
V code is not padded to alter the graph. Immutable benchmark captures and
original script Git provenance are preserved. Historical commands included
in the table receive functional V replacements. Moving an immutable snapshot
to an archive would receive zero translation credit.

## Native command ports toward zero

The 88 stages below remove **517 Python files / 2,263,277 original bytes** and
replace their commands and selected tests with V. These are complete command
ports: their maintained entrypoints compile and invoke V directly. No Python
import bridge is required by these commands. Caller edits and concurrent source
changes remain separate from this per-stage scope and the measured graph.

| Stage | Native source | Original Python bytes / lines | Source commit |
| --- | --- | ---: | --- |
| N64, PS1, PS2 and iOS framebuffer extraction | `tests/emulator-desktop/framecore`, four `frame.v` entrypoints | 7,639 / 180 | `25b91867` |
| Deterministic disk-root file generator | `tests/disk-root/make-large-file.v` | 700 / 25 | `0507542f` |
| ANS, SPI, speaker, Wi-Fi, SMC and ACPI compiler commands | `tests/apple-protocols/fixturecompiler`, six V entrypoints | 7,008 / 162 | `7d4ce889` |
| Kernel allocation source copier and runner tests | `tests/kernel-allocs/copycore`, `copy_sources.v` | 6,589 / 162 | `2c873e8d` |
| Kernel link-layout checker | `tests/kernel-link-layout/check.v` | 2,215 / 41 | `44ac7e4b` |
| Ext2 owner and ELF interpreter mutations | `build-support/imagepatch`, two V entrypoints | 4,711 / 124 | `8943b85b` |
| Apple boot loader and fixture compiler commands | `apple-boot/hostcompiler`, two V entrypoints | 2,807 / 56 | `7580864c` |
| ISO screenshot decoder and desktop/change checks | `build-support/screenshotcore`, `check-screenshot.v` | 5,382 / 156 | `1837f95d` |
| Offline Docker rootfs archive generator | `build-support/dockerimage`, `tarcore`, `make-docker-image.v` | 2,796 / 81 | `ab508446` |
| Initramfs archive duplicate-file linking | `build-support/tarlink`, `tarstream`, `link-duplicate-files.v` | 4,475 / 127 | `ab00fde3` |
| Allocation and user-access log symbolizers | `tests/kernel-symbols/symbolcore`, two `sites.v` entrypoints | 5,395 / 147 | `5a189a86` |
| Standalone Alpine dependency resolver | `build-support/alpinecore`, `alpine-resolve.v` | 1,830 / 63 | `5b750ff8` |
| Wine binary patch commands | `build-support/x86-translation/winepatch`, five V entrypoints | 17,908 / 508 | `52f93ab8` |
| Java trust-store host and guest commands | `build-support/javacacerts`, `java-cacerts.v`, `java-cacerts-stage.v` | 2,285 / 70 | `0c7a52b8` |
| Resource-accounting, pagecache and procfs generated-C guards | `tests/generated-source-guards/guardcore`, three V entrypoints | 6,326 / 139 | `2886191c` |
| Kernel archiver selection and archive test | `tests/compiler-selection/test-kernel-ar.v`, `archivercheck` | 3,039 / 68 | `fb58af4e` |
| Procfs, IPv6, socket, POSIX timer and process-churn generated-C guards | `tests/generated-source-guards/guardcore`, five V entrypoints | 10,860 / 220 | `03b19974` |
| Process-churn report checker and callback bridge | `tests/process-churn/churncheck`, `check-results.v` | 5,355 / 170 | `12d47222` |
| Native header boundary differential runner | `tests/native-boundaries/boundarycheck`, `run.v` | 4,283 / 81 | `0caa1c87` |
| VMX checker frontend, ELF reader and subprocess leaf | `tests/hypervisor/vmxcheck`, `check-vmx.v` | 5,665 / 118 | `05d938f0` |
| Limine compatibility patch test and command fixtures | `tests/limine-aarch64/test-patch.v`, `commandfixture` | 4,292 / 108 | `951bf973` |
| ANS read-only reference verifier and independent tests | `tools/apple-ans/ansreads`, two V entrypoints | 10,400 / 252 | `a99c83e8` |
| Complete AGX extraction/recovery command and trace boundaries | `tools/agx-re/recoverycli`, native extraction modules and trace entrypoints | 36,385 / 959 | `3b2c914d` |
| Eight QEMU syscall comparison commands and fixture generator | `tests/qemu-core/fixturecli`, nine V entrypoints | 22,028 / 593 | `ad94fe98` |
| Base/memory and futex comparison tools and final fixture import bridge | `tests/qemu-core/fixturehost`, three V entrypoints | 25,447 / 517 | `e89a298a` |
| QEMU/desktop archive splitting, module ISO construction and independent tests | `tools/archivehost`, three native commands, `tests/archive-tools/archivetest` | 24,812 / 639 | `fd303029` |
| Build archive pruning and desktop launcher bootstrap tests | `tools/prunehost`, `tests/build-cache/test_prune_build_artifacts.v`, `tests/desktop-bootstrap/test_runner.v` | 19,696 / 446 | `52b0601a` |
| Desktop image preparation and disk-root recovery suites | `tests/desktop-bootstrap/bootstraptest`, two native tests and `run.sh` | 18,412 / 412 | `1eb8dcc8` |
| Wi-Fi firmware packaging, C producers and linked-artifact verifier | `tools/m1-wifi/wifihost`, five native commands and `tests/m1-wifi/test-tools.v` | 14,627 / 321 | `d2036214` |
| QEMU firmware test launcher | `tests/qemu-ovmf/test-patch`, existing `ovmffixture` | 1,565 / 49 | `170f9cf6` |
| Scheduler, TLB and CPU policy host launchers | `tests/host-policy/policyhost`, four native commands | 4,174 / 93 | `6a533e64` |
| Generated policy fixtures, CPU assembly and linked ELF checks | `tests/generated-policy-host/policyhost`, four native fixture commands and `tests/cpu-mitigations/linkedcheck` | 9,359 / 258 | `defd59e4` |
| Production init, tracker, console, fault, CPU and network host commands | `tests/native-policy-tools/nativepolicy`, seven native entrypoints | 21,098 / 378 | `e7e2b615` |
| Guest controllers, PTY/QMP supervision and independent verdict tests | `tests/native-guest-tools/guesthost`, eight native entrypoints | 20,584 / 434 | `6d2661b6` |
| Independent tracker, console, diagnostic and random-hook guests, compiler APIs and hypervisor ABI launcher | `tests/native-guest-tools/guesthost/policy.v`, seven native entrypoints | 23,919 / 482 | `543480fb` |
| Fifteen ABI guest runners, strict marker controller and native ARM ext2/ISO setup | `tests/native-guest-tools/guesthost/abi*.v`, fifteen native fronts | 66,059 / 1,172 | `da792787` |
| Steam and Office generators and host/guest proofs, randomness and N64 bridge tooling | `build-support/native-compat-tools/compathost`, eight native fronts | 38,461 / 684 | `2fed61f8` |
| Security/volume staging, volume host/guest and X11/Wine guest tooling | `build-support/native-compat-tools/compathost`, twelve native fronts and V host fixtures | 29,757 / 529 | `76466b67` |
| Process, scheduler, TLB, memory retention, backlog, procfs and signal-return guest commands | `build-support/native-compat-tools/compathost`, nine native fronts | 31,440 / 542 | `70c0a19c` |
| CPU/job/SysV regression supervision, retention, stack canaries, ELF host/guest, greetings and uname | `build-support/native-compat-tools/compathost`, eight native fronts and native PTY completion policy | 37,579 / 659 | `59fc4cc3` |
| Stack guards, CPU mitigation and segments, paired SMT boot policy, isolated-worktree ACPI | `build-support/native-compat-tools/compathost`, four native fronts and physical ARM home setup | 14,815 / 284 | `091cdf32` |
| Resource-group swap/guest workflow and independent speculation host/guest oracle | `build-support/native-compat-tools/compathost`, two native fronts | 12,528 / 229 | `7b27042a` |
| Resource accounting, read-ahead and sparse filesystem power cuts | `build-support/native-compat-tools/compathost`, shared native PTY controller and three fronts | 19,639 / 339 | `d22c958f` |
| Hypervisor ABI, mounted-disk admission, securelevel parser, append dispatch and attribute faults | `build-support/native-compat-tools/compathost`, bounded native subprocess API and five fronts | 13,014 / 304 | `cca2fa35` |
| Apple ANS, SPI, speaker and Wi-Fi controllers, aliases and provider adapters | `tests/apple-protocols/applehost`, seven native fixture controllers and eleven shell fronts | 25,600 / 573 | `a2fd5c1f` |
| SMC mailbox and display-hotplug command paths and borrowed-object adapter | `tests/apple_smc/run.v`, `tests/apple_display_hotplug/run.v` and native work/signal owner | 11,669 / 221 | `4a88dcb6` |
| Standalone init and init-policy, process-churn, memlock and RSP budget commands | `tests/native-guest-tools/guesthost`, scoped native process-group and serial owners | 18,962 / 334 | `63c3fc16` |
| PS1 core/download and N64/PS2 MIPS homebrew builders | `build-support/native-emulator-tools/emulatorbuild`, four native commands and streaming build log owner | 19,437 / 404 | `e4ad8a3f` |
| N64 and PS2 core builder commands | `build-support/native-emulator-tools/emulatorbuild`, joined native worker pool and core fronts | 4,990 / 142 | `39bb040f` |
| N64, PS1 and PS2 guest/desktop controllers | `tests/emulator-desktop/emulatorhost`, six native commands, native QMP and logged child owner | 50,249 / 1,097 | `486ce887` |
| No-sync, mapped writeback, journal, mounted-disk and reboot controllers | `tests/native-disk-tools/diskhost`, five native commands, journal serializer and PTY owners | 45,864 / 979 | `d1534430` |
| Disk root/writeback, Docker, security, mount, IPv6, NUMA, paging and securelevel controllers | `tests/native-system-tools/systemhost`, ten native commands and shared PTY session owner | 50,430 / 1,315 | `b17c4f04` |
| Native block, fsync, read-only storage, export, sound and PCI commands | `tests/native-system-tools/systemhost`, `tools/dota2/ext2host`, eight native fronts and two checkers | 44,662 / 1,043 | `f0ec18fb` |
| Glibc environment, Lavapipe, WAKE_OP, mapping and Steam guest controllers | `tests/dota2/nativehost`, five native commands and independent host checks | 26,828 / 615 | `eff690f6` |
| Game capture, screenshot, export diagnostics and Venus QEMU preparation | `tests/dota2/nativehost`, native PTY/NBD/QMP owners, screenshot encoder and QEMU patcher | 40,602 / 1,030 | `7a27a254` |
| Verified-root and verified-boot builders, pinned loader, host tests and guest controllers | `tools/verified-boot/bundlehost`, `tests/verified-boot/verifiedhost`, eight native commands and sparse-image helper | 55,350 / 1,199 | `dc893c8b` |
| Minecraft fetching, Microsoft sign-in, LWJGL JAR patching and guest staging | `build-support/minecraft/minecraftnative`, `lwjglpatch`, four native commands and four independent host suites | 29,709 / 824 | `9b5e25ee` |
| Saved allocation-campaign comparison, recomputation, integrity fixtures and Git evidence recovery | `tests/alloc-bench/comparecore`, `reportcore`, `reportfixture`, `evidencearchive`, ten native commands and two host suites | 149,927 / 2,760 | `b1f701ca` |
| GL source generation, guest staging, sanitizer and Mesa guest runners | `gl-triangle/glhost`, `tests/gl-triangle/glvm`, four native fronts and the native AGX PTY owner | 11,449 / 143 | `6012b9d3` |
| Desktop source/presenter staging, loopback package service and clipboard host/VM tooling | `stagehost`, `gpustage`, `packageserver`, `hostclipboard`, `clipboardvm`, native command owners and independent fixtures | 32,617 / 783 | `5b9e309d` |
| Desktop performance current/saved runners, native fixtures and saved v6 validation drivers | `perfrunner`, `perfconsole`, `runnerfixture`, `savedworkflow` and native saved entry points | 146,185 / 3,224 | `541134e8` |
| Offline Dictionary preparation, native fixtures and utility source-processing blocks | `dictionarycore`, `dictionaryfixture`, `utilitysource`, native preparer and desktop cache inputs | 8,204 / 176 | `45a0f271` |
| Core VM runner, launch bridge and five saved allocation-campaign runner copies | `corevm`, `vmfixture`, native current/saved entry points and core shell caller | 74,727 / 1,953 | `73741f9d` |
| Content/staging/desktop cache commands, import bridge and VOffice builder | `cachecli`, `officenative`, native fronts and cache/Office fixtures | 17,638 / 473 | `88708dd9` |
| Apple image pack/build, IORegistry/FDT/ABI checks, iBoot runner and host fixtures | `boottools`, eight native commands and Unix-socket qualification fixture | 42,568 / 1,006 | `4f93ffc9` |
| Memory runtime and large-I/O differential controllers | `memorytools`, native fronts and compiler/guest owner fixtures | 13,403 / 246 | `d6492152` |
| Fixture/module, security/X11, LinuxKPI, benchmark and static kmod generators | `generators`, native fronts and independent ABI/compiler owner fixtures | 25,780 / 531 | `6937b43c` |
| Allocation C/V fixtures, VM/SSH/kext controllers and saved drivers/serial observers | `allocationhost`, twenty native fronts and process/socket owners | 72,433 / 1,562 | `e8fa673a` |
| Current/saved musl recipes, cache, ABI checks and atomic staging | `muslnative`, current and saved native entrypoints, build callers and cache inputs | 16,518 / 320 | `cfe94898` |
| Saved allocation cohorts, correctness, core integration, audits and diagnostics | `campaignhost`, 45 saved native fronts and independent process owners | 140,552 / 1,829 | `2f9d9953` |
| Android host builders, APK probes, generated runtime and runtime fixtures | `androidtools`, native public fronts, direct SDK API and typed fixture hooks | 48,003 / 1,097 | `6c3f2998` |
| Android app supervision, runtime APIs, Roblox staging and host fixtures | `androidrun`, native PTY/QMP owners, image codecs and direct V APIs | 55,087 / 1,215 | `f21c1a5e` |
| OpenGothic builder, guest, KekVM agent and desktop input closure | `gamehost`, direct V APIs, PTY/QMP owners and shared native input | 20,483 / 518 | `c961bf9e` |
| Debian, dhewm3 and Dota runtime command and fixture closure | `runtimehost`, native Debian/JSON/newc, driver and LLVM tooling, PTY owners and Vulkan fixtures | 68,010 / 1,694 | `109cc28b` |
| Launcher, GPU, DNS, CLI smoke and X11 checker closure | `validationhost`, `guestvalidation`, native event streams and process owners, guest ELF staging and checked cache | 36,139 / 972 | `af928324` |
| LinuxKPI audit, fixtures, build recipes and VM closure | `kpihost`, native ABI/bounds/upstream APIs, literal golden reader and native guest supervisor | 54,042 / 1,127 | `8f4b4b4d` |
| iOS C++ builder, symbol generator and graphics staging closure | `iosbuild`, pinned native archive reader, four-worker compiler/cache owner and ELF dependency staging | 10,889 / 213 | `99cb5e31` |
| G17, VirtIO/VirGL and production random controller closure | `renderhost`, direct native G17 APIs, owned PTY/QMP paths and isolated native build runner | 23,037 / 586 | `eca3cb2e` |
| VNC, Venus and Steam launcher helpers | `launcherhost`, native socket-owner/archive commands, streamed decoder owners and static guest helpers | 18,820 / 419 | `92eff41e` |
| Browser, Activity Monitor and pointer-scroll host closure | `vmhost`, direct PTY/pipe controllers, native QMP and static guest recipes | 26,216 / 524 | `2a63a2ea` |
| Roblox Windows runner closure | native manifest/ZIP/layer/USTAR, owned PTY/FIFO, concurrent uploads and XWD/PNG reports | 12,279 / 278 | `e892a4d9` |
| Native stdio transport test closure | `nativequery`, private SDK stdin/stdout actions and exact native callback errors | 3,995 / 126 | `e9d7f0f0` |
| Android binding closure | native `androidrun`/`androidtools` contexts, cold dispatchers and actual native suites | 21,866 / 537 | `3fe13236` |
| Native wallpaper generation | libjpeg-turbo SDK, V Lanczos-3, native cache/download/index and CLI owners | 5,952 / 144 | `1a9c278d` |
| Ext2 host fixture generator and runner | native generator, original V fixtures and direct production test-suite builds | 6,852 / 147 | `f0a0c4f6` |
| Native font generator and atlas test closure | direct FreeType/HarfBuzz owners, native SFNT metadata, cached SDK driver and PNG previews | 21,749 / 574 | `8d358c7a` |
| Native iOS UIKit, 2048 and desktop UI tests | native duplex protocol, direct host app checks and isolated QMP desktop workflow | 17,035 / 373 | `b9443a23` |
| Native CPython runtime smoke controller | V C API, owned callbacks and native dynamic-musl guest builder | 9,112 / 270 | `0a74a267` |

Follow-up `29ccceb7` updates the kernel's ACPI make rule and dependencies to
invoke the native compiler. Make recipe checks on both target architectures
select the qualified ARM/x86 profiles. This caller repair adds no translation
credit; other sessions' makefile edits were excluded from its commit.

The first seven stages checked actual ARM and Rosetta x86 host binaries against frozen
Python originals. Frame extraction passed 240 cases with PNG dimensions, CRCs
and decoded pixels compared; compressed bytes may differ. The disk-root fixture
matched all 3,145,728 generated bytes. All 46 Apple protocol compiler profiles
and eight Apple boot compiler profiles emitted byte-identical C. The allocation
copier matched complete inventories, bytes, modes and nanosecond timestamps on
both kernel architecture source lists (537 ARM and 472 x86 files). Native tests
also preserve both-architecture report enforcement and refusal to update an
allocation baseline after compiler failure.

The link checker passed real LLD/llvm-nm checks on isolated AArch64 and x86 ELF
objects, plus 21 controlled success/failure and cleanup cases. Image mutations
matched 21 ext2 cases and ten interpreter cases on both hosts; four ext2 cases
used real mke2fs images. Native parser/image tests and the existing storage
helper tests passed. The Apple boot AArch64 loader cross-build passed, along
with the 78-field host ABI check and loader-core allocator-import guard.

Qualification limits remain explicit: the SMC and Apple boot host suites hit
existing compiler-generated undeclared `memdup` calls; original drivers emit
the identical failing C. The shared kernel object directory mixes architectures
and duplicate fixture symbols, so its original and native link checkers both
fail until it is rebuilt cleanly. These ports do not establish new kernel builds,
guest boots or hardware runs. Detailed commands and limits are recorded in each
native module's README. Local comparisons and logs are under
`/tmp/vinix-python-zero-20261010`.

The next four stages remove five Python files / 18,048 original bytes. They
were verified with native V fixtures and independent tools, following the
repository's current prohibition on running Python. Screenshot tests decode
144 RGB/RGBA fixtures, exercise all five PNG filters and unknown-filter behavior,
PPM comments, desktop thresholds, percentage rounding, changed pixels and CLI
status. ARM and x86 tests passed. Truncated and oversized screenshots now return
bounded read errors; native decompression diagnostics may differ.

Docker tests independently inspect all 64 USTAR members and payloads for six
binary sizes, then use system tar to list and extract the output. ARM and x86
tests passed. Archive deduplication passes plain/gzip/bzip2/xz inputs, PAX/GNU
metadata, exact Unicode names, streamed data and publication-failure checks on
both hosts and under ASan/UBSan. System tar independently supplies three input
formats and confirms output hard links share inodes. Sparse and unknown member
types fail before publication rather than attempting an unreliable USTAR rewrite.

Both log symbolizers passed native parsing, subprocess and stdin checks, plus
real LLVM symbolization of isolated ARM and x86 ELF debug fixtures on each host.
These stages establish host-tool behavior, not new image builds or guest boots.
Their commands invoke V directly, and existing ISO/Docker shell callers and
kernel-diagnostic documentation use the native entrypoints. Qualification
artifacts are under `/tmp/vinix-python-zero-20261010/continuation`.

Between the `29ccceb7` and `5a189a86` inventories, counted Python
declined by 16,895 bytes. That graph delta includes concurrent source changes;
it is separate from these four stages' 18,048-byte translation scope.

The following two stages remove six Python files / 19,738 original bytes.
The standalone Alpine resolver retires its Python entrypoint and callback
controller, retaining strict UTF-8 reads, universal newlines, Unicode splitting,
repository and provider preference, FIFO traversal, ignored dependencies,
deduplication and sorted manifests. All maintained shell and V build callers
invoke it directly, and staging cache keys include its native policy sources.
ARM, Rosetta x86 and ARM ASan/UBSan checks passed, including a 1,000-package
closure and exact cached Java, Go and QEMU manifests. The Debian controller still
compiles against the shared whitespace helpers. No Python was run.

The five Wine patchers retain their pinned Alpine 9.17 bytes and offsets.
System tar independently extracts seven original PE/ELF payloads; all native
outputs match the pre-existing patched images byte for byte and remain stable
on a second run. Input and reference hashes are committed. Both host
architectures and ARM ASan/UBSan passed the native fixtures, CLI checks,
malformed/truncated inputs, pointer overflow, mode/link behavior, failed
publication and 100 repeated success/already-patched/error resource cycles.
This establishes host patching behavior, without new guest or Office runs.

Follow-up `ba45ee8c` routes compiler messages to stderr in the shared V launcher.
Cold compiler cache-status text could otherwise enter a tool's stdout and corrupt
its first package manifest. A native compiler fixture verifies stream routing,
literal arguments, working directories, exit statuses and temporary cleanup on
ARM and x86. All five Wine launchers and fourteen caller shell syntax checks
passed. This fix adds no Python translation credit. Native qualification logs
remain under `/tmp/vinix-python-zero-20261010/continuation`.

Between `5a189a86` and `52f93ab8`, counted Python declined by exactly 19,738
bytes, matching these two stages. Other sessions also committed V changes;
their bytes affect the language shares independently.

The next three stages remove five Python files / 11,650 original bytes. The
Java writer matches every byte of the existing 119-certificate Mozilla trust
store, whose SHA-256 is
`a25f4464a74cfba595a04f135b3ee2f6927479161baac152feef2161cc893bad`.
OpenJDK independently accepts its default and supplementary-Unicode passwords
and rejects wrong passwords. OpenSSL verifies the JKS checksum independently.
Native tests cover permissive PEM padding, all byte values, sorted files,
empty/duplicate blocks, read errors, output preservation and CLI status.
The host command, image builders, Android controller and package frontend now
invoke V directly. Both static Linux musl guest executables cross-build with
the expected ELF architecture and no dynamic interpreter. Staging rejects a
wrong compiler target and cleans temporary files after failed publication.
The full package-command suite passes using a native download fixture and the
real V trust-store writer. Other Minecraft download/login paths still contain
Python; no Python was run during these qualifications. No new guest Java run
is established by these host checks and cross-builds.

The three generated-C guards preserve function selection, Unicode word and
whitespace matching, allocation detection, stack-slot counts, loop ordering,
procfs template identity, lock/return accounting and ancestry-before-retarget
checks. Native fixtures cover passing sources and ownership regressions,
truncated/invalid input, argument errors and partial stdout before a failure.
Follow-up `42eac0bc` preserves Unicode line separators when selecting the
root-creation receiver; text on a later line cannot satisfy that ownership check.
All three pass against the current ARM production blob. The cached x86 blob
is older: the guards correctly reject its missing caller-stack record, hidden
read-ahead allocation and unchecked procfs dispatch. These checks do not build
or boot a kernel and do not establish new retention measurements.

The archiver test isolates the committed kernel makefile and snapshots the
untracked compiler-runtime makefile into a private fixture. A V `uname`
stand-in exercises macOS LLVM discovery, configured/explicit precedence,
Linux defaults, missing-tool errors and cleanup goals. Clang and LLVM build
and list the real one-object AArch64 ELF runtime archive. Both successful
runs and forced compiler failures remove their temporary directories.
ARM, Rosetta x86 and ARM ASan/UBSan checks pass for all three stages. Local
logs are `/tmp/vinix-java-*`, `/tmp/vinix-guards-*-final-v3.log` and
`/tmp/vinix-ar-cleanup-*.log`.

Between `52f93ab8` and `42eac0bc`, counted Python declined by exactly
11,650 bytes, matching these three stages. Concurrent V and C changes affect
the language shares independently.

The next stage removes five standalone Python source guards / 10,860 bytes.
The native commands retain their function selectors, exact scratch counts,
allocation boundaries, loop rules, shared socket flags, interface-box release,
queued FD shallow-transfer backreferences and buffer/path ownership checks.
Native fixtures cover each function and ownership regression, Unicode matching,
multiline timer arguments, nested/truncated braces, invalid UTF-8, CRLF/CR input,
argument errors, optional operations and partial stdout before a later failure.
ARM, Rosetta x86 and ARM ASan/UBSan builds and all three V test files pass.
All five cold launchers pass against the current ARM generated C with clean
stdout/stderr. No Python was run.

Follow-up `d99bfe83` updates the IPv6 receive and process inheritance guards to
follow the current kernel's explicit delegate chains. Missing or duplicate calls,
changed forwarding arguments, missing destination owners and path handling in
inheritance wrappers are rejected. The original inline forms remain supported.
All five guards pass the current ARM generated C on each host profile. The
cached October 1 x86 C is older: it lacks an IPv6 definition and the required
scratch patterns, and all five checks correctly reject it. No new kernel builds,
guest boots or retention measurements are established by these host checks.
Logs are `/tmp/vinix-scratch-guards-*-final.log` and
`/tmp/vinix-scratch-production-final.log`. Between `42eac0bc` and `d99bfe83`,
counted Python declined by exactly 10,860 bytes, matching the new stage.

The next stage replaces the process-churn report checker and its Python bridge
with a native V command. All seven modes retain cohort coverage, six-second
grace, allocation tracking, timed-work evidence, filesystem identity and optional
flatness thresholds. Native field parsing covers Unicode words, whitespace and
decimal digits, replacement UTF-8 decoding, integer aliases and arbitrary-size
values. Reports preserve measurement order and emit no partial stdout on failure.

ARM, Rosetta x86 and ARM ASan/UBSan builds and native tests pass. Seven cold
launcher checks compare complete output, and a controlled tracking failure
checks status, error streams and temporary compiler cleanup. The generated-C
source guard still passes. Caller auditing permits removal of the old callback
query, bindings and three bridge aliases; the separate Python QEMU runner is
unchanged and still needs translation. No Python was run. These are guest-format
fixtures, not new guest boots or kernel retention measurements. Logs are
`/tmp/vinix-churn-report-*-final.log` and `/tmp/vinix-churn-cold-final.log`.

Between `d99bfe83` and `12d47222`, counted Python declined by exactly 5,355
bytes, matching this stage. Concurrent V source changes affect the language
shares independently.

The next stage retires the Python native-boundary differential runner. The
native V command directly uses the shared V module producer to compare pinned
original C headers with maintained V UART tracing, callback, stack-pointer and
SMC-counter implementations. The independent fixture and all production kernel
sources are unchanged. Both C and V fixture executables pass the ten UART traces,
256 callbacks, stack alignment and monotonic-counter checks, with identical
stdout and stderr under Clang ASan/UBSan and stack-use-after-return detection.

Ordinary ARM and ASan/UBSan host builds pass real-compilation tests for success,
compiler failure, allocator-import rejection, fixture failure and output mismatch.
Each case checks status, streams and removal of all temporary source/object
directories. The Rosetta x86 runner correctly refuses the unsupported host before
creating work; its assembly and architecture tests pass. The cold launcher also
passes from an unrelated working directory and cleans up after a missing compiler.
No Python was run, and no new kernel build or guest boot is established. Logs are
`/tmp/vinix-boundary-{arm,asan,x86}-final.log` and
`/tmp/vinix-boundary-cold-final.log`.

Between `12d47222` and `0caa1c87`, counted Python declined by exactly 4,283
bytes, matching this stage. Concurrent V and C changes affect the language
shares independently.

The following two stages remove two Python files / 9,957 bytes. The VMX command
now owns the CLI, source/object directory, ELF64 reader and subprocess text
handling in V. It removes the private phase protocol and embedded Python leaf
while retaining compiler recipes, allocator guards, instruction/CF/ZF checks,
operand order and clobber checks. All 7,680 C ABI cases and the ARM no-op fixture
pass under Clang ASan/UBSan. Optimized x86 controls pass inspection, and every
entry byte matches the pre-port C at `bf2fdd33^:kernel/c/vmx.c`. A changed entry
is rejected after the earlier instruction report. Production VMX sources,
assembly and the independent C fixture are unchanged.

ARM, Rosetta x86 and ARM ASan/UBSan builds pass all four native test files,
covering malformed/truncated ELF ranges, full-width addresses, Unicode names,
instruction regressions, compiler search, all 27 standard-descriptor states,
100 repeated captures, decoding-error precedence, descriptor retirement,
CLI status/streams and temporary cleanup. Captured tool text now uses native
strict UTF-8 with universal newlines and native errors; arbitrary Python locale
codecs and exception classes are retired. The cold launcher checks exact real
fixture reports from an unrelated working directory and cleanup after a missing
compiler. Logs are `/tmp/vinix-vmx-{arm,x86,asan}-final.log` and
`/tmp/vinix-vmx-cold-final.log`. These host checks establish no privileged VMX,
nested VT-x, new kernel build or QEMU boot.

The Limine test preserves all three original independent patch scenarios:
fresh patching before build/install, an idempotent rerun with identical source
bytes, and incompatible-source rejection before build without modifying it.
The maintained builder and patch are unchanged in isolated copies. Configure,
make and tool-discovery substitutes are native V, and the actual Git patch
logic runs. ARM, Rosetta x86 and ARM ASan/UBSan builds pass these scenarios,
forced configure/make failures, help/status checks and private scratch cleanup.
The cold launcher also compiles fresh native fixtures from an unrelated working
directory and cleans up after success or a forced make failure. No source is
downloaded and no real UEFI loader is compiled or deployed. Logs are
`/tmp/vinix-limine-{arm,x86,asan}-final.log` and
`/tmp/vinix-limine-cold-final.log`. No Python was run for either stage.

Between `0caa1c87` and `951bf973`, counted Python declined by exactly 9,957
bytes, matching these two stages. Concurrent V source changes affect the
language shares independently.

The ANS reference verifier and its independent tests remove two Python files /
10,400 bytes. Both command entrypoints now compile and invoke V directly, and
all three documented callers use them. The native implementation keeps a single
read-only, close-on-exec source descriptor, checks its actual file type, streams
SHA-256 in the original chunk/pass/range order, and retains mismatch and EOF
rejection. New manifests use exclusive, no-follow creation with mode 0600,
complete writes and fsync; existing images, devices and symlinks cannot be
overwritten. Manifest reads remain bounded to 1 MiB. Numeric JSON tokens remain
exact above 2^53 and outside machine widths, while Boolean, float and quoted
range values are rejected. UTF-8/16/32 input detection and Unicode labels and
integer syntax are covered. Informational system strings now use uname; usage
text and OS/JSON error wording are native.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan builds pass all nine native test groups,
including the seven original scenarios, independent shasum comparisons, full
megabyte streaming, signed offset bounds, overlap/order/adjacency, exclusive
publication and dangling links, malformed and oversized manifests, CLI status
and 100 repeated success/error cycles with no descriptor growth. Native suite
compiler-selection failures also retire their private directories. Cold
launchers pass a fresh suite build and record/check from an unrelated directory,
preserving source bytes and clearing temporary files after success and an
exclusive-create failure. Logs are `/tmp/vinix-ans-reads-{arm,x86,asan}-final.log`
and `/tmp/vinix-ans-reads-cold-final.log`. No Python was run. Only synthetic
regular files and device/type rejection were tested; this establishes no ANS
hardware identity, guest execution or power-loss persistence.

Between `951bf973` and `a99c83e8`, counted Python declined by exactly 10,400
bytes, matching this stage. Concurrent V changes affect the language shares
independently.

The next two larger batches remove 21 Python files / 58,413 bytes. AGX tools
now contain no Python files: the three extraction commands, complete G17 ABI
and T6050 power recovery commands, trace generator and trace comparison invoke
V directly. Their four import adapters and fixture encoding shim are retired.
DeviceTree discovery retains its fixed Preboot depth, deterministic ambiguity
diagnostics and regular-file requirement, including followed symlinks and FIFO
exclusion. Both recovery commands preserve ordered image reads, UUID/proof
validation and report schemas; T6050 creates no output until every proof passes.
Native values own their DeviceTree and returned metadata buffers. CLI paths,
option prefixes, help, failure status and failed-publication behavior are checked.

All 28 affected AGX native test files passed on ARM64, Rosetta x86-64 and
ASan/UBSan. Both complete real-image reports matched the saved independent
qualification reports in each profile; T6050 file bytes equal stdout and source
inputs remain unchanged. The trace workflow passed its four complete frozen-C
JSON comparisons, explicit allocation/release counts, rollback and Mach/dyld
sanitizer probe. Fresh recovery help commands, trace generation, native module
generation and trace-runner help also passed. No Python was run and no Apple
image was committed. Logs are `/tmp/vinix-recovery-{arm,x86,asan}-tests.log`,
`/tmp/vinix-agx-recovery-real-final.log` and
`/tmp/vinix-agx-trace-native-test.log`.

The eight QEMU signal/touch/restart/nanosleep/blocked/poll/epoll/C-int comparison
commands and normal fixture generator now compile and invoke V directly.
They retain host, prepare and native modes, architecture defaults, paired
helper selection, guest defines, mutually exclusive actions and Path handling.
Existing native policies retain provenance-checked C oracle ranges, independent
fixture assertions, compiler flags, allocator guards and complete receipts.
Normal generation stages only maintained V fixtures; recovered C remains
outside the checkout. Both `run.sh` generation branches use the native command.

All five QEMU command/controller test files passed on ARM64, Rosetta x86-64 and
ASan/UBSan. All eight original-C/V host comparisons passed with sanitizer and
allocator guards on both architectures, and all sixteen paired guest binaries
cross-built for AArch64/x86-64. The nine fresh shell entrypoints passed help and
temporary cleanup, followed by a standalone host comparison and normal generator
run from an unrelated directory. No Python was run. Logs are
`/tmp/vinix-qemu-fixture-{arm,x86,asan}-tests.log`,
`/tmp/vinix-qemu-fixture-qualified-{arm,x86}.log` and
`/tmp/vinix-qemu-fixture-cold.log`. These are host and target-build checks;
they add no physical GPU, kernel or guest-boot result.

Between `a99c83e8` and `ad94fe98`, counted Python declined by exactly 58,413
bytes and 21 files, matching these two batches. Concurrent V changes affect
the language shares independently.

The next batch replaces the pending base/memory generator and host comparison,
the futex host/guest comparison and the final shared fixture import bridge.
Five Python files / 25,447 bytes are retired. Native commands preserve compiler
profiles, original line ranges, exact assertion text, function-only ABI call
remapping, target-SDK syscall numbers, allocator guards, evidence hashes and
seven paired futex diagnostics. Base generation retains module-only output and
full immutable-C reconstruction. The original full source and all generated
comparison artifacts remain outside the checkout. The base host receipt now
uses native `uname -srm` identification; native failures use native diagnostics.

All six QEMU command/controller test files passed on ARM64, Rosetta x86-64 and
ASan/UBSan, including the new range, CHECK-count, target-number and diagnostic
pair checks. Fresh base/memory and futex sanitizer comparisons passed on both
actual host ABIs and in a sanitized command process. Reconstructed originals,
API headers and host logs matched saved independent controls; the full base
reconstruction accounts only for the header-placement fix already present in
the committed Python source. Source-hash receipts were verified against every
generated input. Both futex guest targets linked with their allocator guards.
All three cold shell entries passed help, protected-output and temporary cleanup
checks, and both complete standalone host commands passed. No Python was run.
Logs are `/tmp/vinix-qemu-pending-{arm,x86,asan}-tests.log`,
`/tmp/vinix-qemu-pending-final-{arm,x86,asan}-tests.log`,
`/tmp/vinix-qemu-pending-qualified-{arm,x86,asan}.log` and
`/tmp/vinix-qemu-pending-cold.log`. The fixture bodies still await normal guest
runner integration and receive zero completed C-implementation migration credit.
These host-tool ports establish no new kernel or guest-boot result.

Between `ad94fe98` and `e89a298a`, counted Python declined by exactly 25,447
bytes and five files. The three larger batches together retire 26 Python files
and 83,860 bytes. Concurrent source changes affect the relative graph separately.

The next three complete batches retire **11 Python files / 62,920 bytes**.
The archive commands retain member order and USTAR metadata, size limits,
streamed root-seed gzip, exact source identities, locks, cache hits and publication
order. Native checked closes expose pending write failures before publication;
old outputs survive failed rebuilds. System tar and real xorriso independently
verify payloads. Tests also cover malformed archives, unsafe names, shrink cleanup,
symlink targets, one-nanosecond cache invalidation, lock contention and repeated
descriptor retirement. All three production binaries and their native suites pass
on ARM, Rosetta x86 and ARM ASan/UBSan. Cold launchers pass from `/tmp`.
See [the archive qualification](../tests/archive-tools/README.md) for commands,
logs and platform limits. Frozen benchmark drivers that name historical commands
remain counted and await their own complete workflow translation.

The pruning command preserves shallow selection, allocated-block accounting,
age/ctime retention, repeated keeps, markers and environment overrides. Native
process/open-file inspection protects active inputs; inspection failures prevent
deletion, and automatic opt-out remains effective. The cutoff is computed after
the lock, with nanosecond file-state checks before removal. Native tests verify
real ps/lsof protection, redacted failures, concurrent replacement, lock contention
and descriptor retirement. Unique fixture archive names prevent concurrent suites'
root-relative input protection from interfering with each other. Make, build and
desktop callers now invoke V directly. ARM, Rosetta x86 and ARM ASan/UBSan tests
pass for the command and separately compiled frontends, together with cold entry
and the full cache suite. See [the pruning qualification](../tools/prunehost/README.md).

All three desktop bootstrap suites now use V, including their fake commands.
The launcher preserves help, dependency ordering, warm reuse, no-build behavior
and compiler selection. Image preparation retains all eight original scenarios.
Recovery tests exercise current production function bodies, failure cleanup,
publication lifetimes and preserved existing payloads. Every host profile builds
and inspects a real AArch64 recovery ELF, then compares its exact archived bytes.
The recovery launcher uses the existing native init producer through `compile-init`;
the older init-policy Python runners and their generator remain counted. The
desktop cache fingerprints the native producer. All native suites and the complete
cold launcher pass. See [the bootstrap checks](../tests/desktop-bootstrap/README.md).
No Python was run in these three batches, and no new guest boot is claimed.

Between `e89a298a` and `1eb8dcc8`, counted Python declines by exactly 62,920 bytes
and 11 files, matching these stages. Concurrent source changes affect the relative
language shares separately.

The next three batches retire **10 Python files / 20,366 bytes**. Native Wi-Fi
packaging preserves all 128 manifest bytes, payload bytes, ordered provenance,
size and identity validation, and exclusive output creation. Its tests cover
failure cleanup and independent SHA-256 checks. Both native C producers retain
compiler arguments, staging metadata and exact source transformations. Six real
generator profiles compile into ARM/x86 target objects, and both control profiles
link statically. An independently linked AArch64 ELF exercises the verifier and
all eleven malformed-copy regressions. ARM, Rosetta x86 and ARM ASan/UBSan host
products and suites pass, together with cold native launchers.
See [the Wi-Fi host tools](../tools/m1-wifi/wifihost/README.md).

The Wi-Fi verifier retains the original nineteen-symbol policy. Available cached
kernels fail that policy: the current V providers use module-prefixed symbols and
inline entrypoints, while the older production artifact lacks five required
symbols. The verifier correctly rejects both; a fresh full kernel build, guest
boot and hardware validation are not claimed. The remaining driver build callers
need a separate update for the current providers.

The QEMU firmware suite retires its Python launcher and runs all twelve existing
real-Git cases directly from V, including single-case selection and the
Git-unavailable skip. All three host profiles and the cold launcher pass.
See [the firmware fixtures](../tests/qemu-ovmf/ovmffixture/README.md).

Scheduler preemption, QoS and TLB commands now create, compile and run their own
private fixtures. Their generator overrides remain supported. The CPU command
uses native process capture and retains all 12,288 C ABI/hardware-adapter cases.
All four commands pass on the three host profiles; sanitizer runs also instrument
the generated fixtures. Native checks cover twelve compiler-failure owners,
three generator failures, successful overrides and private-work cleanup. A V
constructor records absent and empty caller `VEXE` before V's startup supplies a
default, preserving compiler precedence without the retired Python bridge.
See [the policy host commands](../tests/host-policy/README.md).

Follow-up `2a663317` fingerprints the complete Wi-Fi V core and shared producer
helpers in the desktop cache. All three cache test files pass, including
independent producer-dependency invalidation checks. This repair receives no
Python translation credit. No Python was run in these three batches.
Between `1eb8dcc8` and `2a663317`, counted Python declines by exactly 20,366 bytes
and ten files, matching the retired commands. Concurrent V changes affect the
relative language shares separately.

The next complete batch retires **six Python files / 9,359 bytes**. Syscall,
execute-only and mounted-block generated-code checks and CPU assembly adapters
invoke their V policies directly. The old file/process/exception callback bridge
is removed. V retains strict UTF-8 and universal newlines, checked writes,
caller architecture, compiler arguments, inherited streams and private fixture
cleanup after compiler or fixture failure. LLVM symbol addresses use native
arbitrary-width conversion. Existing C fixture constants and assertions remain
unchanged; nine previously qualified complete ARM/x86 fixture contents retain
their exact hashes and lengths.

The current ARM execute-only function also needs its emitted file-state bit
definitions. The extractor now includes those definitions, and the unchanged
128-case protection/gate/attribute fixture passes. Both architecture variants
of all three generated-code policies pass on ARM, Rosetta x86 and ARM ASan/UBSan
hosts. The actual assembly adapters pass all 1,024 CPU/flag cases, fifteen thunk
registers and the scheduler resume checks on each host profile. Native tests
verify twenty-one compiler/fixture failure retirements and argument/encoding
errors. All five cold entrypoints pass outside the checkout.

The linked-ELF checker preserves Unicode boundaries and whitespace, greedy
matches, the first twenty raw-branch failures, unresolved thunk checks, the
required scheduler symbol and the minimum one hundred thunk branches. Its
independent rejection tests pass on all three host profiles. A cached production
x86 kernel passes with 1,549 thunk branches; the older checkout artifact is
correctly rejected for raw indirect branches. No new kernel build, guest boot
or hardware validation is claimed. See
[the generated policy qualification](../tests/generated-policy-host/README.md)
for input hashes and native commands. No Python was run. Between `2a663317` and
`defd59e4`, counted Python declines by exactly 9,359 bytes and six files.

The next batch retires **seven Python files / 21,098 bytes**. Init, allocation
tracking, console output, stack diagnostics, CPU arithmetic and the network
producer/controller now use native V commands. Production policies, independent
fixture assertions, compiler flags and allocator guards remain. Both CPU V
templates retain the original literal bytes. An independent replay of the
retired network producer's compiler recipe emits byte-identical C.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan hosts pass the tracker, both console
profiles, both serial diagnostic adapters, CPU arithmetic and the init host/ARM
link suite. The original C init recorder and three original C policies also
pass both echo variants through the native reference adapter. Native guard tests
verify Unicode allocation boundaries and fixture timeout kill/reap behavior;
twenty-one forced compiler failures retire all private owners. All seven cold
shell entrypoints pass their expected outcomes outside the checkout. The console
adapter supplies the current panic-terminal recorder and adapts ELF section and
symbol directives for Darwin x86 without changing assembly instructions.

The four network fixtures still fail at the existing undeclared `memdup` calls
introduced by the selected compiler for stack records. Source generation and
all failure/cleanup paths pass; successful network fixture execution is not
claimed. No kernel build, guest boot or physical hardware evidence is added.
See [the native policy qualification](../tests/native-policy-tools/README.md).
No Python was run. Between `defd59e4` and `e7e2b615`, counted Python declines by
exactly 21,098 bytes and seven files; concurrent changes affect other languages.

The following batch retires **seven Python files / 20,584 bytes**. The generic,
hypervisor, console, resource, poll, exception and page-table commands now build
and supervise guests directly in V. The independent runner test suite is also
V. Compiler profiles, original C controls, allocator guards, source/executable
hashes, expected/forbidden markers and raw serial evidence remain. ARM uses the
pinned ISO builder and direct QEMU launch, completing the fixture path without
the desktop script's Python package server.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan hosts pass all seven controller builds
and the original twelve verdict methods. Additional checks cover QMP, SIGINT,
failed exec, UTF-8 replacement and one hundred repeated FD/child retirements.
Original C and V poll, exception and both-architecture page-table fixtures pass
24 static builds across those hosts, with ELF machine IDs and manifest hashes
verified. Nine further init compiler profiles, including linked sandbox/audit
cores, also pass. All eight cold entrypoints pass outside the checkout.

Actual hypervisor fixtures boot successfully on prepared ARM and x86 kernels
under TCG and report hypervisor unavailable; VMX execution is not established.
The V poll fixture and original C control both fail the line-48 predicate with
errno 22 on the cached x86 kernel. Their ISOs contain identical kernel bytes.
That guest verdict remains a failure. No new production kernel build or physical
hardware run is claimed. See
[the native guest qualification](../tests/native-guest-tools/README.md).
No Python was run. Between `e7e2b615` and `6d2661b6`, counted Python declines by
exactly 20,584 bytes and seven files; concurrent changes affect other languages.

The next batch retires **nine Python files / 23,919 bytes**. Independent tracker,
console, serial-diagnostic and random-hook guests, the live tracker launcher,
three compiler APIs and the public hypervisor ABI launcher now use V directly.
Existing shell callers also invoke the native compiler. Compiler flags, original
C controls, variadic assembly, receipt hashes, production console selection and
guest verdicts remain. The live tracker retains support for an existing state
directory. Independent builds retain their fresh-directory rule, and the added
build-only modes allow qualification without a boot.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan hosts pass all seven command builds,
CLI checks, the public ABI oracle and native hook compilation. Sixteen static
guest builds cover both architectures, both console modes, live/independent
tracker fixtures and V/original C diagnostic/hook controls. ELF machine IDs and
all captured input/receipt hashes are verified. The three existing random,
SHA-256 and erasure host test files pass through the native compiler. Seven
cold fronts, invalid arguments, prior-state preservation, nine dotted-directory
object-name checks and both-architecture diagnostic success/failure owner
retirements also pass.

All fourteen real guest cases pass on prepared ARM and x86 kernels: independent
tracker, debug/production console, and V/original C diagnostic/hook fixtures.
The live tracker is cross-built; its in-kernel coverage still requires an
`ALLOC_TRACK=1` kernel. No new kernel build, retention measurement, physical
hardware run or VMX execution is claimed. See
[the independent policy qualification](../tests/native-guest-tools/policy-guests.md).
No Python was run. Between `6d2661b6` and `543480fb`, counted Python declines by
exactly 23,919 bytes and nine files. The three batches in this continuation
retire **23 Python files / 65,601 bytes**.

The next batch retires **fifteen Python files / 66,059 bytes**. ABI scratch,
capability exec, stack and syscall policy, dumpability, shared streams, timers,
socket I/O, procfs allocations, network options, terminal jobs, securelevel,
execute-only, procfs mounts and clock control now have native V commands.
The original compiler/ASM inputs, C controls, rootfs fixtures, baselines,
readable/reuse options, marker counts and architecture-specific exit rules
remain. ARM retains its private 64 MiB ext2 home and kernel command line.
All boots snapshot an existing matching kernel; none rebuilds shared state.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan host profiles pass controller and
real-PTY qualification, strict CLI and prior-state preservation, raw invalid
UTF-8/NUL output, interrupts and one hundred FD/PID retirements each. Forty-five
forced compiler failures retire their private workspaces, and all fifteen
cold fronts pass. Each host attempts 37 cross-build profiles: 29 succeed, while
eight preserve undeclared-`memdup` errors in existing shared-streams, socket-I/O
and terminal-job generated C. Original strict compiler recipes reproduce those
errors. All twelve original C fixture recipes produce byte-identical ELFs.
Final source, controller-executable and linked-ELF receipt hashes are verified.

Actual ARM guests pass the permission, timer, network, clock and procfs-reuse
checks, including execute-only with PAN disabled. Original securelevel and full
procfs-mount C controls also pass. Securelevel retains its real ext2 write/fsync;
the image passes read-only e2fsck and contains the expected byte. The unchanged
ARM stat/poll C fixture exceeds its original retention bound, and procfs
allocation checks require tracking files missing from this prepared kernel.
Several suites also fail on the prepared x86 kernel; securelevel and procfs
mount C controls reproduce the failures on the exact same kernel bytes.
These verdicts remain failures. No fresh kernel or hardware qualification is
claimed. See [the native ABI qualification](../tests/native-guest-tools/abi-guests.md).
No Python was run. Between `543480fb` and `da792787`, counted Python declines
by exactly 66,059 bytes and fifteen files; concurrent changes affect other
languages.

Eight more complete command ports retire **38,461 Python bytes / 684 lines**.
Steam preload generation and both host/guest checks, Office DLL generation and
both host/guest checks, the randomness runner and N64 bridge now run through
native V. Their original C controls, ABI/layout assertions, compiler recipes,
marker predicates and public options remain. Native workspaces are fresh and
default temporary owners retire on success/failure. Steam/Office runtime staging
preserves execute permissions and timestamps, snapshots an existing ARM kernel
and owns QEMU directly. Desktop cache inputs and N64 corresponding-source
staging include the transitive native and embedded-fixture dependencies.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan hosts pass both Steam differentials
and actual i386/x86_64 links, Office sanitizer goldens and all 33 Windows64 DLL
exports, and the randomness original-C/V sanitizer comparison. Real ARM guests
pass all four Steam original/V executables and both Office Windows64 fixtures
through staged Wine. ARM and x86 randomness guests pass. The N64 bridge passes
on ARM and the sanitizer controller with the existing ARM archive and a local
homebrew ROM, including replacement, frames, save, reset and cleanup.
All eight cold fronts pass outside the checkout, as does the N64 front from
a copied corresponding-source tree. Declaration/ABI parsing, runtime byte/stat
copying, CLI errors, prior-state preservation and twelve failed-build owner
retirements pass separately on each of the three profiles. The three cache-key
test files pass, and the updated N64 source policy compiles. macOS uses
`detect_leaks=0` because Apple's runtime rejects LeakSanitizer; supported hosts
retain leak detection. ASan/UBSan and the allocator-import guard remain. No
new x86 N64 archive, production kernel, physical hardware or macOS leak-check
result is claimed. No Python was run. Between `da792787` and `2fed61f8`, counted
Python declines by exactly eight files and 38,461 bytes. See the
[native compatibility qualification](../build-support/native-compat-tools/README.md).

The next batch retires **seven Python files / 29,757 bytes**, plus embedded
Python in three security host runners. Security and volume staging, volume
host/guest checks, X11 host/guest checks and the Wine guest now invoke V.
Compiler precedence, strict static builds, ABI checks, atomic publication,
original C controls, volume assertions and six frozen X11 traces remain.
The maintained volume host templates are actual V files, with the current
production health dependency and independent access/fault tests. X11's termios
adapter explicitly borrows its stack record, avoiding an implicit allocation.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan hosts pass security original-C/V
stream comparisons and input hashes, volume host tests, X11 goldens, atomic
publication/disk checks, twelve CLI checks and failed-stage owner retirements.
The power-cut supervisor passes malformed/partial verdicts, raw binary and
large PTY output, deadlines, SIGINT and one hundred FD/PID retirements per
profile. All twelve cold fronts and three cache-key test files pass. Both
musl targets build all staging utilities from committed production sources
at `5e431bdc`; another session's unfinished volume source fails strict C
warnings and remains outside this port. Real ARM and x86 guests pass Wine
and X11. The ARM volume guest passes all retention classes and verifies disk
sentinels after SIGKILL. The prepared x86 kernel rejects the unchanged status
ioctl with ENOTTY; both guest binaries match the original compiler recipes
byte for byte. Assertions remain intact. No new kernel, hardware or macOS
LeakSanitizer result is claimed. See the
[native compatibility qualification](../build-support/native-compat-tools/README.md).
No Python was run. The three batches in this continuation retire
**30 Python files / 134,277 original bytes**. Between `2fed61f8` and `76466b67`,
counted Python declines by exactly seven files and 29,757 bytes; concurrent
source changes affect the other language totals separately.

The remaining work includes Python callers and import bridges around earlier
V policy ports, host/guest supervisors, independent tests, fixture and package
generators, and frozen benchmark scripts. A V implementation behind a Python
entrypoint still contributes Python and does not complete this target. Historical
source must retain its captured bytes and provenance; no snapshots were moved
or hidden in these 88 stages.

The next fifty stages remove 365 Python files / 1,764,934 original bytes.
The nine process commands retain seventeen target build profiles, independent
C controls, exact retention/progress assertions, real musl signal return and
private PTY/QMP ownership. ARM, Rosetta x86 and host ASan/UBSan qualification
passes; actual guest passes and prepared-kernel failures are recorded in
[process-guests.md](../build-support/native-compat-tools/process-guests.md).
The follow-on regression, protection and loader workflows are qualified in
[regression-tools.md](../build-support/native-compat-tools/regression-tools.md).
The next opt-in and policy stages retain exact counts, topology, worktree
guards, genuine instruction probes, physical volumes and original C controls;
see [optin-tools.md](../build-support/native-compat-tools/optin-tools.md) and
[policy-guests.md](../build-support/native-compat-tools/policy-guests.md).
No Python was run. Together with the previous three batches, this continuation
translates **395 Python files / 1,899,211 original bytes**. Earlier qualification
caches were cleared during shared-machine disk cleanup, and later RAM volumes
detached. Those older local receipts are no longer available. Fresh Minecraft
and saved-campaign analysis checks and inputs are retained on disk under
`/Users/alex/.cache/vinix-minecraft-native-20261011` and
`/Users/alex/.cache/vinix-benchmark-native-20261011`; each stage's qualification
document records its results and retention limits.

## Earlier completed stages

Counts below describe each stage's own original Python implementations and
tests, including comments and blank lines. The 182 stages recorded at the
previous `d9933b67` inventory have a gross scope of **3,361,548 bytes**. At that
snapshot, counted import bridges, forwarders, fixed public data, caller edits
and concurrent committed Python changes accounted for **495,712 bytes**
between gross scope and its measured net reduction of 2,865,836 bytes. Adapter
additions receive no extra migration credit. These historical figures are
separate from the zero-target stages and current committed totals above.

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
| Scalar read/store host controllers | `tests/linuxkpi/scalar_uaccess.v`, `scalar_store.v` | 39,169 / 841 | `98a1d2b40c86217f2589065026cb9c542162d569` |
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
| Complete OpenGothic host and guest workflow | `tests/opengothic/gothicguest` | 15,066 / 300 | `0d42996de1f108fd63bca277bae8d6cecc1627e7` |
| Pinned PS2 Iris builder and cache workflow | `build-support/ps2/ps2build` | 9,982 / 195 | `36b17ec8d307527e131d340fe6aae9b269f82fb9` |
| Complete paired Dota environment guest workflow | `tests/dota2/guestcore` | 8,157 / 135 | `ce1c4c36f542b6731ebf5c5016ab99443cf747b2` |
| Debian package resolution and staging | `build-support/debiancore` | 7,901 / 175 | `70bc9af82be47323a9a692af3c39a662b6693e6f` |
| Dhewm Debian comparison preparation | `build-support/dhewm3/debianprep` | 2,096 / 39 | `4cb82afdfd448506810d6ff1acbfc77595a5bbae` |
| Complete Dhewm build and staging workflow | `build-support/dhewm3/dhewmcore` | 6,798 / 122 | `2c0f062207ed7e9f884d9415e18753808b3473ba` |
| Dhewm runner staging and image workflow | `build-support/dhewm3/runnercore` | 4,457 / 81 | `a3cf88a86231339b5f9b8e40ae69132f0d70f1bf` |
| Dhewm transcript and benchmark result policy | `build-support/dhewm3/runnercore/result.v` | 2,195 / 36 | `adb3820f5bdd83c8675f755a5481e49457d11a84` |
| Verified boot bundle verification and publication | `tools/verified-boot/bootbuild` | 7,969 / 136 | `1fdae7f9dd85c2396bde5118d0de2269036d7344` |
| Complete Mesa Lavapipe builder workflow | `build-support/dota2/mesabuild` | 10,101 / 193 | `32f3edc8b11b7f5dd55c679082e09278ca9dffab` |
| Complete Mesa Venus builder workflow | `build-support/dota2/venusbuild` | 6,505 / 119 | `8bb300418a0f6cec9cddd3a8a1116ef99987c1af` |
| Dhewm PTY and process retirement policy | `build-support/dhewm3/runnercore` | 3,998 / 85 | `f92898385c09449c6dc9081800cbccf23d3f49c2` |
| Steam loader guest provenance and PTY workflow | `tests/dota2/guestcore` | 9,223 / 173 | `1b7808f1e2141fd2c9691f4db2eb01beed8a860d` |
| Roblox Windows host and guest runner policy | `tests/roblox-windows/robloxhost, robloxguest` | 13,239 / 283 | `7a6842f036c7dbed9b7e2da8f8774102c673a2dc` |
| Musl digest, atomic install and symlink helpers | `build-support/musl/muslstage/core.v` | 1,054 / 24 | `2ca672c26143b57bd92627f1b9affd9f729c0a50` |
| Musl compiler, patch manifest and cache plan | `build-support/musl/muslstage/plan.v` | 2,713 / 43 | `158c8b8aa8142c2e497fbdfbefe213d30ec5636e` |
| Verified-root command and image mutation helpers | `tests/verified-root/runtimeroot` | 1,232 / 28 | `3e25cfc15b3dbdfc5e7ac6dc8796a0358d8fa6ac` |
| Android runtime guest preparation and execution | `build-support/android/runtimevm` | 7,861 / 119 | `4f0e8797671aa73ff22e7f3a96a5241528725e6e` |
| Musl locked build, export checks and publication | `build-support/musl/muslstage/publication.v` | 5,597 / 86 | `7035c592ec5ae7a1eaddc88a5fedba638918c524` |
| Dota native wake-operation guest workflow | `tests/dota2/wakehost`, `wakeguest` | 7,916 / 165 | `5550eaee3aa924ee938d805220f036120d0d5363` |
| Verified-root full fixture workflow | `tests/verified-root/runtimeroot/main.v` | 7,365 / 113 | `bf5cb1a510f9f1cb668cb0bd3964e011ef54bb29` |
| Browser guest supervision policy | `tests/browsers/browsercore` | 5,281 / 149 | `0d5a58de60effd7d5fea4a2824ced5573530b8cf` |
| Android ATL native-provider fixture workflow | `build-support/android/atlcontroller` | 7,037 / 102 | `440715658b2db8b7070a9160976da25f0b45ba8b` |
| QMP input command and event policies | `desktop/tools/qmpinput` | 2,923 / 70 | `cf955d2ffbfeeb8813df125de1cafe103f92a81b` |
| ARM PCI guest serial supervision | `tests/pci-config/pcivm/core.v` | 3,661 / 59 | `ec8726238cb898c2e711c5cb7f22dea86a151152` |
| Allocation benchmark validation workflow | `tests/alloc-bench/benchtest` | 8,726 / 124 | `85cfcac7059569d249c136556263a399c54393da` |
| Package-store object table and callback lifetime | `build-support/cpythonhost/package_d_cpython_package.c.v` | 10,104 / 219 | `a0ae707a325580955f427a8b3cec91b1313bcd0d` |
| Kernel-gap ordinary object bridge | `build-support/cpythonhost/gap_d_cpython_gap.c.v` | 4,299 / 84 | `37db2e12a9e600efed40c7f12b753ae60d5face6` |
| Sampler fixture build and execution workflow | `tests/alloc-bench/samplertest` | 5,603 / 76 | `08bd66f565841125505d202dc19c7e50207ceb4a` |
| Android Boot object lifecycle and ordinary bindings | `build-support/cpythonhost/boot_d_cpython_boot.c.v` | 2,767 / 47 | `3db65ebbedf6543e279047a1407970bb6b6dd293` |
| PCI ARM guest preparation | `tests/pci-config/pcivm/preparation.v` | 6,574 / 105 | `92cbbddd42234c8d4986ec34788146e4f01e78ad` |
| iBoot alignment, ADT and boot-argument helpers | `build-support/cpythonhost/iboot_d_cpython_iboot.c.v` | 3,404 / 76 | `5fd1129ac75dbf7b992cc8d729c7fa8d12d714b8` |
| iBoot PNG assembly | `build-support/cpythonhost/iboot_d_cpython_iboot.c.v` | 856 / 17 | `944e6aa60effcc1a60bccbd139f8d898d75b2dd9` |
| iBoot actual QMP transport | `build-support/cpythonhost/iboot_d_cpython_iboot.c.v` | 1,170 / 32 | `791bfec2729bcce45189404afb6e3e1a524da359` |
| iBoot guest preparation | `build-support/cpythonhost/iboot_prepare_d_cpython_iboot.c.v` | 2,569 / 48 | `9cdce31dc14ccf393592337f780230e5dc527348` |
| Desktop measurement independent fixture controller | `build-support/cpythonhost/perftest_d_cpython_perftest.c.v` | 7,072 / 117 | `2db694f628177631e71e77e96e95339cc451e02a` |
| iBoot monitor and report controller | `build-support/cpythonhost/iboot_monitor_d_cpython_iboot.c.v` | 3,052 / 59 | `f58d814101dac2aef225b317a595c92652699464` |
| TLB independent host-policy generator | `tests/tlb/policy.v` | 2,290 / 48 | `ae2770a3741c1b2870b4c1a35a426cf67779da08` |
| Android Run ordinary object bridge | `build-support/cpythonhost/run_d_cpython_android_run.c.v` | 5,540 / 126 | `8244f8fa9300ee5fca4a264fb3630dc469bceece` |
| Dota Vulkan ordinary object and preparation policies | `build-support/cpythonhost/vulkan_d_cpython_vulkan.c.v` | 5,646 / 124 | `47ff6efd23a8127efa82a9b15e236e5241a83fd9` |
| Mounted-disk independent host generator | `tests/mounted-disk-policy/host_generator.v` | 599 / 8 | `3ef3701d36fe2cc72f51cbe4a1555f094e508b10` |
| Scheduler QoS independent host generator | `tests/scheduler-qos/policy.v` | 1,513 / 38 | `7361951566ba8b5a8df505ffec2a4badbacd4d94` |
| Scheduler preemption independent host generator | `tests/scheduler-preemption/policy.v` | 540 / 15 | `451cad711d8e9b9f064b848c08b40d5ad78e6a6e` |
| VirGL VM host controller | `tests/virtio-gpu-virgl/virglcore/core.v` | 8,674 / 207 | `acb31a0838354e1334906eefabfc3a6be9566e27` |
| Verified-boot independent policy controller | `tests/verified-boot/boottest/policy.v` | 5,750 / 94 | `ad563b364a603076f50b0c730d5f0a944d7526b0` |
| Apple SPI independent fixture controller | `tests/apple-spi-keyboard/run.v` | 8,462 / 107 | `9c9117b2be2951f1e2481783a5ab559033f32d55` |
| J313 speaker independent fixture controller | `tests/apple-speakers/run.v` | 8,372 / 100 | `670f3d15b17cedc8fdcd1469677cbf17c5ddcc67` |
| M1 Wi-Fi control independent fixture controller | `tests/m1-wifi/run-control.v` | 7,841 / 94 | `a6ebc78dc87d7abc651f4e405c362a1c5b82cfc0` |
| Dota Vulkan supplied-object fixture bindings | `build-support/cpythonhost/vulkan_fixture_d_cpython_vulkan.c.v` | 1,360 / 21 | `f9bc4f4a2cfaa347be9729cb0b77884dd51ad9da` |
| OpenBSD security VM host controller | `tests/openbsd-security/securitycore/core.v` | 6,494 / 154 | `7b8a9d493d4598fbb2939744fab60d368e4d358a` |
| CPU mitigation independent fixture controller | `tests/cpu-mitigations/check-policy.v` | 1,945 / 27 | `d7133c117e2a8c3bfd183f962c2010fcd9da0974` |
| Disk no-sync VM controller | `tests/disk-no-sync/run_native.v` | 4,447 / 102 | `1030dde029ab17fe5ec62997acb8089d851ef87b` |
| Reboot persistence VM controller | `tests/reboot-persistence/rebootcore/core.v` | 6,314 / 136 | `08672646790fa82976fabd2fce24f85132b4192a` |
| M1 Wi-Fi protocol independent fixture controller | `tests/m1-wifi/run-protocol.v` | 6,377 / 77 | `0364411c90ce7c26c3d824992597aa2c7e02ffc8` |
| M1 Wi-Fi helper independent fixture controller | `tests/m1-wifi/run-helpers.v` | 5,078 / 67 | `4befc6dbf6d97184720586757ea757c8a3fc8ba8` |
| Apple ANS media independent fixture controller | `tests/apple-ans/run.v` | 7,193 / 81 | `4bc9c76338875b21410f2fe996fa29768d5f0952` |
| M1 platform independent fixture controller | `tests/m1-wifi/run-platform.v` | 6,827 / 72 | `8d4b4dc7a724edaa18374bf74664235d10c06dd4` |
| Android Boot ordinary stdlib primitive dispatch | `build-support/cpythonhost/boot_stdlib_d_cpython_boot.c.v` | 2,093 / 49 | `4355c909465114002843f74ad40cfc875e41e5e1` |
| NUMA VM host controller | `tests/numa/numacore/core.v` | 3,776 / 104 | `cc2a12bd9e798ffc8a6187de9617fc911d82cf44` |
| Sound VM supervisor | `tests/sound/soundcore/core.v` | 2,074 / 46 | `033f6a3ed72e95bba79410c3f70c2364d3f68774` |
| VMX host build and validation controller | `tests/hypervisor/check-vmx.v` | 4,757 / 78 | `f4c41516d642390ab1ecec15299cb5fdb1e33434` |
| Roblox staging policy | `build-support/roblox/robloxstage/policy.v` | 3,975 / 69 | `e9f18c70d5b45f0cc1999030e6e5e211a7e5486f` |
| Vinix allocation benchmark host runner | `tests/alloc-bench/vinixcore/core.v` | 5,491 / 93 | `f477d5efbe7c79976ff993ac52a1990d28f9aa45` |
| N64/PS1/PS2 desktop preparation | `tests/emulator-desktop/desktopprep/policy.v` | 4,856 / 57 | `d9933b67dc233a1e7239939f999bc36879f9bb8c` |

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

The next eleven ports add 81,227 original implementation bytes of gross scope,
while the committed Python total falls by 50,334 bytes. All interpreter bridges,
public constants, parser bodies and concurrent source changes remain counted.
The root-argument binding, PS2 rich-inequality correction, explicit-call flag,
GAP temporary-owner primitives and bounded Mesa digest correction receive zero
new algorithm credit. The latter two add 635 and 708 counted Python bytes.

The next eight stages add 44,917 original implementation bytes of gross scope;
the committed Python total falls by 18,262 bytes at the preceding snapshot.
Counted adapters, retained parser/public data and simultaneous source changes
remain included. Nine support corrections receive zero repeated port credit:
`9e0c3ba9`, `e9435c24`, `fc57193d`, `eb815876`, `1337c4a6`, `4dc132a6`,
`23354d2f`, `b4d048b5` and `fdfc128e`. Their counted Python additions total
2,094 bytes. Factory lookup precedes argument callbacks, pending-expression
retirement preserves the incoming exception context, and actual library
traceback frames retain their original aliases. Private invocation adapter
locals retire on failure; exact private traceback-frame layouts are not claimed.

The next four ports add 27,599 original implementation bytes of gross scope;
the committed Python total falls by another 12,978 bytes at this snapshot.
Their own net retirement is 14,342 bytes: Wake removes 3,017, verified-root main
7,325 and ATL 5,033, while the browser adapter adds 1,033 counted Python bytes.
Browser fixed profiles, parser and lazy generator syntax stay counted; the
60-byte original generator expression earns zero extra algorithm credit.
ATL's original lazy generator likewise remains counted. Three owner/replay
corrections (`2cb9a92f`, `3b77e847`, `8402b5b6`) add 402 counted Python bytes
and receive zero repeated algorithm credit. Remaining simultaneous Python
changes stay included in the measured total. The stack-storage correction
`5333d31d` receives zero new migration credit.

The following four ports add 25,414 original implementation bytes of gross
scope. Their own counted Python reduction is 17,641 bytes: QMP removes 1,231,
PCI supervision 2,469, benchmark validation 6,934 and the package adapter 7,007.
The package count excludes eleven lines of retained Python unpacking, duplicate
keyword and raising syntax. The benchmark count excludes its 495-byte existing
V source literal. The optional CPython library foundation and separate replay,
temporary-manager, boot-exit and stack corrections receive zero repeated
algorithm credit. All remaining Python bindings and concurrent committed source
changes stay in the measured total; no historical benchmark snapshot earns
translation credit.

The next two ports add 9,902 original implementation bytes of gross scope.
Their own counted Python reduction is 4,993 bytes: the ordinary gap bridge
removes 745 and the sampler controller 4,248. The sampler count excludes its
282-byte existing V source literal token; the parser, imports and small syntax
bindings remain counted Python. Concurrent committed Python changes add 214
bytes between these two snapshots. The package-session error-slot retirement
(`154ed797`) receives zero new algorithm credit: active binding IDs remain
stable, finish consumes the exported per-call slots, and separately retained
actual exception/traceback aliases retain their ownership. Historical benchmark
snapshots remain unchanged and receive zero port credit.

The next eleven stages add 40,940 bytes of active original Python algorithm
scope. The Boot object bridge's initial 4,630-byte scope is adjusted to
2,767 bytes/47 lines after `5ec83227` restores 1,863 bytes/42 lines of recursive
snapshot and selection helpers to their original Python frames. Direct/contextual
recursion thresholds and result selection remain exact. Arbitrary callbacks'
private bridge frame and global recursion-budget contribution remain explicitly
outside the native-boundary contract. Its combined frontend grows from 20,883
to 21,383 bytes, a net increase of 500 bytes; that growth stays counted.

The TLB generator ports 2,290 original algorithm bytes/48 lines and separately
transfers 8,889 bytes of existing V fixture text into byte-identical V templates,
with zero algorithm credit for that text. The full counted Python reduction is
10,702 bytes. The desktop fixture controller's 7,072-byte scope excludes the
retained lazy 30-byte `path.name` generator; its 117 original body-span lines
include that partial line. Its counted adapter shrinks by 3,639 bytes. Android
Run removes 1,330 counted bytes while recursive snapshots and result selection
remain in their original Python frames.

The fixed-name GAP correction (`77018122`), Boot allocation/exception guard
(`f5634250`) and iBoot global-lookup/order correction (`01e83e4f`) receive zero
new algorithm credit. They preserve finite literal identity, genuine pending
lookup errors, checked allocation retirement and original lookup/reference
order. Earlier actual negative controls remain recorded. All frontend bindings,
retained syntax and concurrent committed source changes remain counted; these
small per-stage reductions are separate from the committed graph totals.

The next 24 bounded stages count selected original behavior, excluding retained
Python syntax, loader/forwarding code and fixed compiler or guest recipe data.
The mounted-disk, QoS, preemption and CPU controllers also transfer byte-identical
V fixture literals with zero algorithm credit. Historical result snapshots and
independent guest fixtures remain untouched. Gross stage credit and counted
Python reductions remain separate: the Sound supervisor adds 370 Python bytes
through its ownership bridge, despite translating 2,074 original behavior bytes.

Roblox translates 3,975 bytes/69 lines and removes 1,468 counted Python bytes;
its returned provenance literals receive zero credit. Emulator preparation
translates 4,856 bytes/57 lines and removes 2,371 counted Python bytes across
three harnesses and the shared bridge. The allocation benchmark runner translates
5,491 bytes/93 lines and removes 2,622 counted Python bytes. Its independent
allocator/sampler, shell expressions, lazy generator syntax and original
TemporaryDirectory/finally owners remain intact.

Finite literal/keyword allocation (`589a4629`), raw Unix paths (`deeac98c`),
dual-stream capture/reaping (`ec1a25af`), original global lookup (`6e95bbcb`,
`03a1eed7`), the Sound import repair (`dc8097f7`) and invoking-Python text codecs
(`4d2b7285`) receive zero new algorithm credit. Their binding additions remain
counted. Unrelated committed kernel and iOS changes affect the denominator;
the language graph is measured from the explicit source revision, rather than
attributed entirely to these Python ports. The current 0% target has not been reached.

## Validation

Each stage retained frozen Python originals until the candidate passed its
comparison gates. Originals remain recoverable from the source commit's parent.
Tests executed actual Darwin ARM64 binaries and independently compiled x86_64
Mach-O binaries through Rosetta. Host qualification uses **V 0.5.2 6d549c2**;
the recent stages pin the preserved ARM/x86 compilers under
`desktop-perf-foundation-20261008/qualified-compiler` in the local evidence cache.
Host-only stages do not establish
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

- OpenGothic passes 34 host, 121 guest and 12 main comparisons per profile,
  nine no-compiler CLI cases, thirteen ownership controls and 100 exact-FD QMP
  retirements. Both prepared original and native ARM guests render the world,
  accept input and preserve the screenshot result with the same kernel, desktop
  and engine hashes. This is prepared-artifact evidence, with no fresh kernel,
  physical hardware or x86 guest claim.
- PS2 construction passes 41 source and 25 complete build comparisons per
  profile, actual HTTP downloads, five abrupt query exits, interruptions and
  100 exact-FD retirements. Fresh original and native ARM builds produce the
  same 60-object archive, member order and five licenses. A later zero-credit
  correction uses the original rich inequality operation and repeats 27 full
  plans per profile plus the actual cached archive.
- Paired Dota environment workflows pass 60 complete and 28 helper plans,
  twelve rich-callback/lazy controls and fifteen ownership/error cases per
  profile, with 200 retirements returning from five FDs to five. Prepared
  original and native guests preserve the failing old runtime and passing new
  runtime results against the same kernel and translator. These checks cover
  the environment workload and make no fresh game or rendering claim.
- Debian resolution passes 242 comparisons and 21 live curl/CLI/retirement
  controls per profile, plus Android and Alpine workflow regressions and cold
  compilation on both ABIs. Dhewm's Debian preparation passes 25 paired plans;
  its builder passes 40 complete plans, live curl, seven abrupt controller EOFs,
  group interrupts and 104 CLI/FD controls per profile. The runner staging port
  passes 40 plans and seven owner cases; result policy passes 125 direct and
  28 whole-guest plans. Each repeats exact FD, cold-compiler and retained-error
  controls on both ABIs. Host fixtures claim no fresh full game or kernel boot.
- Verified boot passes 31 original/native bundle and signing-order comparisons,
  32 actual exception/cause/context-manager controls, six caller-any/lazy and
  noncallable controls, and the unchanged independent whole-bundle/tamper tests
  per profile. Seven signatures, three constants and parser AST remain exact.
  Cold compilation, 100 exact-FD retirements, interruption and forced EOF checks
  pass. The genuine PE-signature fixture explicitly skips without the supplied
  signing tools and loader; no new signed-loader or firmware claim is made.
- Mesa passes 50 helper, 40 whole-build, 24 owner, 16 real archive/patch/sysroot
  and 17 import/lambda/caller-binding controls per profile. Venus passes 48
  complete/helper plans, 16 real archive/patch cases, 14 import/syntax/order
  and 18 retained-module/error controls. Original source fields remain intact;
  64 Mesa and 72 Venus native inputs plus three symlink identities invalidate
  and restore their keys. Each port passes all eighteen unchanged independent
  Vulkan staging fixtures on ARM, actual x86 and sanitizers, plus cold helpers,
  100 or 200 exact-FD retirements, group interrupts and forced EOFs. These are
  host build-plan and fixture results, with no fresh upstream Mesa compilation,
  kernel, guest rendering or device claim. The 501-entry library inventory has
  identical output and measured RPC overhead; no speedup is claimed.
- The optional guest binding preserves 69 explicit/default call controls per
  profile. Its temporary-owner primitives preserve fourteen distinct-entered,
  monotonic-ID, checkpoint and interrupt controls on both ABIs. Mesa's bounded
  digest correction passes ten mechanical bridge cases, fourteen actual weak
  chunk/generator retirement comparisons and its entire focused corpus on all
  three profiles. The real 512 MiB input retains the exact digest; extra host
  peak RSS falls from 548 MB to about 4 MB on ARM, 12 MB on x86 and 2 MB with
  sanitizers. The last block survives stream exit and final digest formatting.
  All 73 N64, 81 OpenGothic and 73 package-store shared-bridge regressions pass.

- The Dhewm PTY port passes 28 workflows, 38 advanced controls, six weak-owner
  cases, eleven retirement cases and five actual PTY cases per host profile,
  including group SIGINT, plus both cold installers. Atomic descriptor/PID
  consumption and bounded broken-query recovery preserve the normal deadlines.
  The counted bindings exceed the original scope by 735 Python bytes.
- Steam guest policy passes 74 workflows, four actual PTYs and 100 exchanges
  at the exact descriptor baseline per profile. A 32 MiB capture holds at most
  the current and replaced raw blocks; the last block survives stop and report.
  Both cold installers pass. A prepared load-only guest passes using the pinned
  existing kernel, client and translators; it establishes no game/rendering or
  new kernel claim. Two earlier server-ready timeouts remain recorded.
- Roblox Windows policy passes 62 host, 67 guest and 28 main controls per
  profile, with eleven HTTP/PTY/FIFO/descriptor cases, guarded post-fork cleanup,
  callable/error identity and digest lifetime probes. A 512 MiB digest retains
  about 2.2 MiB in the host parent. Cold installers pass on both ABIs. These are
  host qualification results, without a proprietary client or new guest claim.
- Musl helpers pass 52 original/native cases and 100 exchanges at the exact
  descriptor baseline on ARM, Rosetta x86 and under ASan/UBSan. The zero-credit
  lookup correction adds nine factory mutation/error/noncallable/alias controls.
  The plan stage passes 74 original/native cases, including actual installed
  cross-compilers and committed Alpine patch manifests for both architectures
  and both release versions. Session/stream owners, SIGINT, EOF/reap and
  no-compiler CLI cases pass; both cold installers use mode 0700.
- The final musl publication source passes 100 original/native comparisons per
  profile: 64 full combinations, twelve failure policies, four cached failures,
  thirteen owner boundaries and seven weak/expression cases. Real deterministic
  gzip/tar extraction and patch application preserve the original decisions;
  callback fixtures cover compiler/make/readelf failures and wide jobs. New
  pinned musl 1.2.5 builds for AArch64 and x86 retain all existing exports
  (1,645 and 1,648 rebuilt exports), exact staging checksums and Rosetta warm
  cache reuse. Shared upstream C and Alpine/Vinix patches remain unchanged.
  The 1.2.6 build branch has host fixtures and actual compiler/patch-plan checks,
  without an actual 1.2.6 libc build claim. No new kernel/QEMU claim is made.
- Verified-root helpers pass 57 comparisons, 29 weak/alias/error controls, five
  no-compiler CLI cases and 100 exchanges at the exact descriptor baseline per
  profile. Both cold installers pass. This stage leaves guest/main/parser bodies
  unchanged; the qualified shared exception-local correction is pinned separately.
- Android runtime VM policy passes 78 workflows, eighteen weak/identity/lifetime
  controls and 100 exchanges at the exact descriptor baseline per profile.
  Spawn/EOF, process-group SIGINT, no-compiler CLI and both cold installers pass.
  Public signatures and the original parser/preflight AST stay intact. Named
  import spec/module objects survive execution errors; ephemeral callable and
  receiver aliases retire at the original boundaries. Existing generators remain
  counted syntax bindings. No new kernel/runtime/Android guest claim is made.
- The zero-credit package invocation-local correction passes eighteen direct
  lifetime cases and fifty success exchanges per host ABI, plus 73 production
  V package-store comparisons on ARM, x86 and under sanitizers. Actual library
  frames retain constructor/callable arguments until caller traceback release;
  builtin pending-expression temporaries retire before manager exit. Both cold
  installers pass. The correction adds 139 counted Python bytes.

- Wake-operation policy passes 36 workflows, six raw/child, ten digest,
  thirteen JSON, ten archive/environment, five named-local, twenty pending-call,
  five wait-index and four ignored-return controls per profile, plus five CLI
  cases and 200 actual original/native PTYs at exact FD baselines. Both cold
  installers pass. Original/native prepared guests pass with the same existing
  kernel and translator hashes; no new kernel, game or physical-device claim.
- Verified-root main passes 62 workflows, including 39 injected error identities,
  alongside 57 helpers, 29 lifetime cases, five CLI cases and 100 actual tamper
  exchanges per profile. Four actual cross-architecture guest C/ext2/Merkle/archive
  plans and both complete cold installers pass. An earlier fixture accepted a
  positional-only mode while pathlib supplied a keyword, hiding lost branch
  coverage. Its logs and premature commit remain recorded; corrected full gates
  passed against the exact committed source before publication. No new kernel,
  guest or UEFI Secure Boot claim is made.
- Browser policy passes 115 original/native cases, twelve named/context lifetime,
  nine tuple/marker/errno and three detached-factory controls per profile. Twenty
  ignored EIO exceptions retire before the next wait without requiring GC.
  Fourteen actual PTYs, 100 descriptor exchanges, process-group SIGINT and lost
  replies after real owned forks pass. Both cold installers pass seven CLI cases
  and two actual helpers with mode 0700. READ uses the actual rich equality and
  WRITE the actual rich inequality; earlier order/comparison failures remain.
  Host supervision tests do not establish a new kernel or browser rendering guest.
- ATL controller passes 80 workflows, twenty digest/lifetime cases, 100 actual
  digest exchanges, four spawn/EOF cases, owned SIGINT and six CLI cases per
  profile, plus both cold installers. Real patched-provider ARM C/V links,
  strict ARM/x86 object builds, exact independent Linux C/V goldens, ELF closure,
  archive and SHA checks pass. The separate stack correction removes unintended
  address-escape allocation from the unchanged native probe; generated objects
  import no allocator. Provider allocation, frozen C oracle and every assertion
  remain unchanged. The captured guest plan is not a fresh Vinix QEMU result.
- Three zero-credit owner/replay corrections pass the existing package or GAP
  suites on all profiles and both cold installers. Private owner method/manager
  aliases retire after exit; replay locals retire after conditional traceback
  restoration. Forty ignored-error iterations across two paths retain no actual
  exception before the next call. Actual library frames remain intact.

- QMP input passes 269 original/native policy comparisons, six lifetime, nine
  numeric, eight loop and two factory controls per profile. Twelve actual Unix
  socket cases include 100 exchanges with flat descriptors; CLI covers four
  parser cases and five actual commands. Original/native owned-group SIGINT
  pairs reap all children. Both cold installers pass three helpers at mode 0700.
- ARM PCI supervision passes 39 policy, 22 lifetime and eighteen rich-object
  controls, two GC/context-timeout and five CLI cases per profile; 200 real
  Popen descriptor exchanges, TERM-to-KILL and SIGINT checks pass. Prepared
  AArch64 QEMU checks reuse kernel hash `4e260cf9a3e055073ed2cec0e93bc6c83153c9ab314a6adaf8f624b3f9cc45d6`.
  Host supervision does not establish a fresh kernel, SMP or physical PCI test.
- Allocation benchmark validation passes 186 complete workflow comparisons,
  thirteen weak-reference and sixty property/format/context-order checks per
  profile, plus intrinsic, actual child/descriptor, EOF, SIGINT and six CLI
  gates. Both complete cold installers pass at mode 0700. The unchanged 136
  Linux ARM C/V sanitizer comparisons include all 64 OOM rollback cases and
  LeakSanitizer with `detect_leaks=1`. Both macOS ABI providers build and link;
  the original macOS unsupported LeakSanitizer failure remains preserved.
  No fresh Vinix guest or benchmark-performance claim is made.
- The package adapter passes 73 full workflows, twenty ownership controls,
  twelve batches of twenty consumed errors with GC disabled, 58 actual rich
  objects, twelve result/ID boundaries, 36 Unicode/NUL/surrogate cases and
  eighteen independent Python-with comparisons per profile. Five hundred
  result calls retain their exact reference baseline; 100 constructors retire,
  twenty nested calls and 100 calls across four threads preserve handled
  exceptions, and actual SIGINT/errors propagate. Independent review passes
  forty rich result-key/temporary-manager lifetime comparisons per profile.
  QMP caller controls, actual sockets and owned-group interrupts also pass
  against the frozen library. Both cold libraries and queries build on the
  ordinary invoking CPython, preserve descriptors and retire temporary products.
  The failed macOS `.so` filename check led to the qualified `.dylib` correction;
  inherited ASan child-environment failures remain recorded, followed by passing
  explicit copied-interpreter checks with unchanged assertions.
- The optional CPython foundation passes 57 helpers, 29 lifetimes, nested/thread
  reference and signal cases, independent with statements, strict providers,
  invalid-library and default-query gates. It uses actual interpreter objects
  and public development headers; it does not claim the limited ABI. Its
  separate temporary-manager correction passes 22 independent manager cases:
  both special methods resolve before consumption and detached managers retire
  before entry. The separate native replay and boot-exit corrections preserve
  caller-owned traceback/context while releasing private replay references.
  Foundation and replay fixes add counted Python bindings and earn no new
  original implementation credit.

- The ordinary kernel-gap bridge passes 69 legacy helpers, 31 fork and 29
  guardian controls per profile, plus 100 actual PTY exchanges with flat
  descriptors. Focused actual-object, lifetime, strict-provider, registration,
  comparison, boot and close checks cover original factory lookup and release
  order. Five hundred alias calls, thirty nested calls, 100 calls across four
  threads and 100 GC-disabled error calls retain their baselines. Both cold
  library/query installers pass at mode 0700. Failed earlier comparison and
  receiver-retirement probes remain recorded; corrected final V source passes.
- The sampler controller passes 129 build/failure, 240 main-policy, 221 rich
  object and 251 callable-order original/native comparisons per profile.
  Four GC-disabled saved-error controls retain the detached comprehension
  iterator until the actual traceback is cleared. One hundred normal calls
  retire actual temporary directories with flat descriptors; spawn/EOF, two
  owned-group SIGINT, six no-compiler CLI, signature and Python-O controls pass.
  Both actual cold installers pass at mode 0700 and retire their private output
  directories. Original/native controllers each build and run both the
  immutable C and production V fixtures under ARM/x86 macOS ASan/UBSan, with
  original assertions intact. Byte-identical ARM artifacts also pass GCC 13
  ASan/UBSan/LeakSanitizer on Linux with `detect_leaks=1`. Host ENOSPC interrupted
  earlier final checks; isolated retries pass with unchanged source/binaries.
  These checks add no fresh kernel, QEMU, hardware or performance claim.
- The package error-slot retirement passes all prior package/QMP controls on
  ARM, x86 and ASan, sixteen active/finished alias cases per profile and the
  additional saved-error/path/writer lifetimes. Finishing retires the private
  exported list slots; scalar exception and traceback aliases remain actual
  objects. The consumed-list boundary is documented in `tools/package-sdk.md`.

- Boot ordinary-object bindings pass all 27 existing client groups on ARM,
  x86 and ASan/UBSan, with direct/contextual recursion and rich result-selection
  controls. The later bounded guard correction adds 28 actual exception pairs
  and six injected allocation failures per profile. Actual saved traceback and
  incoming handled state remain observable. Both fresh cold installers pass.
  The sampler controller also passes against the then-current 420-input Boot
  integration snapshot on all three profiles; that integration receipt remains
  separate from each original pinned stage.
- PCI preparation passes its twelve groups per profile, including 212 actual
  workflow and 344 rich writer/path comparisons, saved lifetimes, actual
  interruption and cold installation. Previously tested guest evidence uses
  its recorded older kernel and does not qualify a new kernel.
- iBoot helpers pass 91 original/native pairs, rich callbacks, identity and
  lifetime controls. PNG adds malformed/full-size bytes, CRC and saved-row
  cases; QMP adds actual Unix-socket exchanges, pending errors and flat FDs.
  Preparation passes 29 groups per profile with real ELF packing and ARM stub
  assembly, parser/CLI checks, detached targets and original cleanup. The
  subsequent global correction preserves rich key equality errors and all
  three PHYS_BASE lookup positions. Monitor/report adds 40 groups per profile
  and 60 paired real process/Unix-QMP workflows with exact FD baselines, saved
  qemu/qmp lifetimes, receiver timing and BUILD_SLICE retirement. Both actual
  cold installers pass at 0700. No fresh kernel or guest boot is claimed.
- The desktop fixture controller passes nine groups on ARM, x86 and ASan/UBSan,
  including all twelve original and twelve native unittest cases, real local
  dictionary corruption/size checks and temporary-VM SIGTERM cleanup. Rich
  formatter/comparison/target-order and saved-error controls retain the actual
  objects; 500-call, GC-disabled and threaded controls retain their baselines.
  Both cold installs, four CLI modes per architecture, original signatures and
  scenario constants pass. The ASan child-launch negatives are retained; the
  corrected copied-interpreter/runtime environment passes unchanged fixtures.
- The TLB generator creates the same six fixture files byte for byte on all
  profiles. Forty-one actual original-extractor comparisons, malformed UTF-8,
  universal newlines, custom umasks and partial filesystem effects pass. The
  unchanged original/native generated fixture assertions pass on ARM and x86,
  and under ASan/UBSan. Actual cold CLI routes, three compiler/generator failure
  paths and two process-group SIGINT paths per architecture retire mode-0700
  disposable owners and reap the actual compiler children.
- Dota Vulkan and preparation pass all eighteen original workflow cases on each
  profile, seventeen focused groups and five additional groups, with four real
  cold installer gates. Named local, supplied callback, finite literal, actual
  global-lookup error and process/FD controls pass. Original recursive codec,
  context-exit and conversion syntax remains counted Python to preserve the
  maintained recursion thresholds. Failed earlier drafts and interrupted old
  workflow logs remain preserved; the final complete matrices retain unchanged
  assertions. The stage removes 960 counted Python bytes. No fresh guest/GPU
  evidence is claimed.
- Android Run passes eighteen groups per profile, including 239 result,
  transport, installer, plan and actual PTY controls. Both actual cold installers
  preserve mode 0700 and FD baselines. Twelve focused allocation failures and
  8,400 measured table allocations/frees retain zero live tables. Actual saved
  locals and error aliases remain owned; documented private-frame/recursion
  and bounded OOM limits remain intact. Host checks add no fresh guest/GPU claim.

- Mounted-disk, QoS, preemption and CPU generators pass ARM, Rosetta x86 and
  ASan/UBSan controls for exact generated files, partial effects, raw paths,
  malformed input, original fixture extraction/assertions, subprocess errors,
  SIGINT and disposable-owner retirement. The CPU policy's unchanged original
  and native ABI checks pass 12,288 cases per profile. Fixed fixture text has
  zero translation credit.
- Apple SPI, speakers, ANS and M1 protocol/platform host recipes pass complete
  original/native command, raw-path, encoding, missing-import, CLI, FD and cold
  installer comparisons. The tested original and native actual compilation
  failures remain identical: existing V-to-C memdup casts block these fixture
  builds, and the ANS x86 attempt also encounters ARM assembly. These are not
  reported as successful fixture executions. Wi-Fi control and helper stages
  separately execute all eleven original/native fixture bodies successfully on
  both host architectures. None of these host results adds physical Apple or
  Wi-Fi operation evidence.
- OpenBSD, VirGL, NUMA, disk no-sync, reboot persistence and Sound controllers
  pass all three host profiles with real PTYs/children, EOF, signals, incoming
  handled errors, named/saved locals, exact FD/reference baselines and actual
  cold installers. NUMA's clock failure and Sound's named-local retirement
  negatives were retained and corrected before qualification. Reboot's actual
  retained generator uses the original shared loop cell. Disk's frontend Git
  executable mode was restored before its qualified commit. No fresh QEMU
  boot, desktop performance measurement or audio playback is claimed.
- The Android Boot stdlib dispatcher passes its original client groups on all
  three profiles, actual filesystem syntax leaves, supplied callbacks, rich
  global lookup, saved-error order, 500 repeated reference checks and both cold
  installers. An actual saved-Path destruction-order mismatch required one
  ordered dictionary matching the original named locals. Original archive,
  recursive conversion and Python context/exception syntax stays counted.
  The Dota fixture bridge adds original recursive/selection and rich-object
  ownership checks without claiming a new rendering or guest run.
- VMX passes controlled full build/validate workflows on all three profiles,
  raw/surrogate paths, actual CLI/closed-stdio/CLOEXEC/FD controls, owned child
  interruption and both five-controller cold installers. Actual original/native
  ABI fixtures pass 7,680 cases per profile. The complete checker's unchanged
  cross inttypes header failure is retained; no VMX entry or QEMU/kernel build
  success follows from those host controls.
- Roblox passes the ten unchanged filesystem fixtures and 158 supplied-object,
  failure and teardown pairs on each profile. An actual formatting callback
  that changes RuntimeError exposed factory-lookup ordering; the final source
  captures the original factory first. Each profile also passes 500 ordinary
  calls, 100 saved errors, exact reader references/finite literal identities,
  actual CLI/closed-stdio children and real SIGINT publication rollback. Both
  actual cold routes build and retire SDK, staging and Android controllers.
- The allocation benchmark runner passes full controlled workflows, actual
  USTAR payloads, supplied checksum/compiler/validation objects, detached
  writers, retained generators, actual child/CLI/SIGINT cases and GC-disabled
  500-call/100-saved-error/threaded ownership checks. Final qualification includes
  the source's restored original Git mode, with all execution bytes identical
  to its complete three-profile matrix; fresh CLI and both cold routes confirm
  that final mode. These controls do not constitute benchmark measurements.
- Emulator preparation passes six real filesystem/raw-path pairs, 408 supplied
  object/fault/prior-error pairs, 42 controlled complete harness workflows and
  eleven environment-field retirement cases per profile. The first source
  inserted fields too early and dropped temporary values in the wrong order
  on failure; its actual negative remains retained. The final V source evaluates
  the complete field stack before publication and retires it in reverse order.
  Each profile passes 500 calls, 100 saved errors, exact references/literal
  identities/FDs, 24 actual closed-stdio children and nine CLI pairs. Both actual
  cold routes create six mode-0700 SDK/query owners, perform 101 preparation
  calls per harness and retire every owner at interpreter exit. Original QMP,
  pixel/gameplay assertions, parser/context owners and deadlines are unchanged.
  The frozen archive has one unused older Roblox frontend; all actual consumed
  dependencies match the committed checkout, and that drift is recorded rather
  than claiming a complete current-HEAD snapshot. No fresh emulator/guest/GPU
  execution result is inferred from controlled host workflows.

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
| `opengothic-guest-20261009` | `qualification-final.json` | `9264b6f935fb784d03fbccb3dcef491ae8af84df187fcb414a6b1d817887e290` |
| `opengothic-guest-20261009` | `postcommit.json` | `d0f69c0e4175daed8b7ce1bc4689cf465568b6a1eb74fec7acf61d7d745db65d` |
| `ps2-builder-20261009` | `qualification-final.json` | `c14835e82f5c6bc9cc888eff23422a1c75e4d906972b8e1a2a6b15ae5dc29749` |
| `ps2-builder-20261009` | `postcommit.json` | `a91623f3a4c39d8e9b92254b78892ec433378496baead9048f31436ada4a60e9` |
| `dota-environment-guest-20261009` | `qualification.json` | `f1791b1ddfd7301488151b75bdb12450438a69527f41f7f000efdb5e7ca41026` |
| `dota-environment-guest-20261009` | `post-commit.json` | `21c7e88fd83cf40b5f7182fc8408a7e9169a58a478f7505e9c0f98658d0f6333` |
| `debian-root-20261009` | `qualification.json` | `980b53204c1b0f615bd4a94e6b2869b96a15daa4a01a0c1406241583db9fd322` |
| `debian-root-20261009` | `postcommit.json` | `2d29b7dbfaec41c06e510cec69c3f0333997eada317d42f861002d479cd9ba5d` |
| `dhewm-debian-prepare-20261009` | `qualification.json` | `5c9ca6d0d2fbe2b0c991b096add1904c23352f089cc24f5205246bba41c75b18` |
| `dhewm-debian-prepare-20261009` | `postcommit.json` | `bc1a330d23e3fcfda0675982c3da203d20bbd4bc1b894e9d116a8df0a398263b` |
| `dhewm-builder-20261009` | `qualification.json` | `47744e973701ce3184fb274de13b853054cf38da6e4c7494b48eb38ff219070c` |
| `dhewm-builder-20261009` | `postcommit.json` | `39a8335c153bb7863d842be61a0868f04423e7bd084d83000e9a59037d19509e` |
| `dhewm-runner-20261009` | `qualification.json` | `7dc7262a7b4b608055c25c9debc85f87e824e22c18d5ef8e3d7422a8753b4110` |
| `dhewm-runner-20261009` | `postcommit.json` | `bf5d5612971d8da4e987ce867d1479e72883772408ed933fdcf85397249bb49a` |
| `dhewm-runner-result-20261009` | `qualification.json` | `3c39e5c5db86aab2143f71e2705c468fc09f35bcdfbb67959e2348cf8d72870e` |
| `dhewm-runner-result-20261009` | `postcommit.json` | `0791c24dee0ee197c85d1da5569125a8d25b942edd7d044827d3b5eb66222ab1` |
| `verified-boot-bundle-20261009` | `qualification.json` | `1d690ea928a4251365ce5e0ecd0a58045cc8c26fe9bc61bc2bff587f0ca6f4b2` |
| `verified-boot-bundle-20261009` | `postcommit.json` | `b686c8c0bf8090065bc73b95bb14b7c1691aa1295873d24967ae188ae10a49f2` |
| `mesa-builder-20261009` | `qualification.json` | `860df51cb9c1033dc4d0b661a9d307f2206bd9f571e9f86de4911a47b121f044` |
| `mesa-builder-20261009` | `postcommit.json` | `c39179c504a5010aecd303fdb7f6e0de37d1c0deda97177d9b59088cf5faec44` |
| `venus-builder-20261009` | `qualification.json` | `c72d376a04bc46294dfe6249ca1be96a530b5c8a059cc6bb988d0527ff7dde12` |
| `venus-builder-20261009` | `postcommit.json` | `35af5676de2073e00e62c82bdba1beda6e7d932edd04be650e0e1e54eebe01b5` |
| `gap-root-owner-20261009` | `qualification.json` | `acc9038f8c2c0fc5c0ed8ee4d2c214da9fca29790a6b49c22ccda6f8dcc6d40e` |
| `gap-root-owner-20261009` | `postcommit.json` | `0ec463f64b84aa6b211585be35c04ec465fda545d4abc5e7ceae1c68d55b9967` |
| `ps2-builder-20261009` | `cache-ne-qualification.json` | `8687d523791d4e0b6bafa4380ba50fff2113876bbfdf9271a5797f2949873619` |
| `ps2-builder-20261009` | `cache-ne-postcommit.json` | `6bedcd35e4bb37789366aefa4a87459556ecfffc3b553419d3786f2c3a775b97` |
| `gap-call-binding-20261009` | `qualification-final.json` | `b9f0793dd7e346915a3f9f0e7d88dd5589756afdee590722e5a11074dfccc146` |
| `gap-call-binding-20261009` | `postcommit.json` | `cbb8f97c244a1d72faa9f249f047874355c42f1703abcc67901ed85c3ae5a623` |
| `guest-bounded-retention-20261009` | `boundary-qualification.json` | `7f1354c7b288f99459d25d7bed1e0505e91d36b144495d45f13ad29c9571bba3` |
| `guest-bounded-retention-20261009` | `boundary-post-commit.json` | `062d0400a52803c5a80e9fe7c2b5d39d208d111a9ba22d2d6582153e67fe165f` |
| `mesa-bounded-retention-20261009` | `qualification.json` | `5b494878664d5b121b59309fc43c0f44c6a083f9435df679183c11b36ac78798` |
| `mesa-bounded-retention-20261009` | `postcommit.json` | `20b637408c6150e193c0877128b278522d2e5a42fb4285071a99ec15548f3cad` |
| `dhewm-runner-pty-20261009` | `qualification.json` | `b9b881b72cb9c66fe89d44514b3977156e0264241febe6eadeedf6b6a074897f` |
| `dhewm-runner-pty-20261009` | `postcommit.json` | `dfcb02c909f61e7d3f7e46055a0e630ade38df47528678db2aafa045bf7a210c` |
| `dota-steam-guest-20261009` | `qualification.json` | `bc83484fda575decffe534873f84dc0a5e808c0200f4030648456c950b2f7f8f` |
| `dota-steam-guest-20261009` | `post-commit.json` | `bb4bdeedb81e3c6d92081dfc673c8b5edf7680fba1b10173ba1075427e926dbd` |
| `roblox-windows-20261009` | `qualification-final.json` | `4f34fad29383b058d8f84cbb69a9e87fd4e9b551418eb5ef11e1c9dfcc0417b3` |
| `roblox-windows-20261009` | `post-commit.json` | `6c1955b097107ba569393fd199184905f934ac26f5f396b6e61106f5e65af27d` |
| `musl-stager-20261009` | `qualification.json` | `ee0424642819fe61e77d26621e58a136bb48245de39bdfebab1a4fa80d6ad322` |
| `musl-stager-20261009` | `post-commit.json` | `a4260c87568d4c9d522eab8123f94dc24fd3dc2b31a940e2dbd6c9addab1102a` |
| `musl-plan-20261009` | `qualification.json` | `9f700c023f5719f0fccafd2f7f0fc138317b92edc79c27cc456e7d218534aea3` |
| `musl-plan-20261009` | `post-commit.json` | `1d50390f59cc6e2b53949aa8184209cfd7af90b1c001fba11a4c250df0fe4ef5` |
| `verified-root-runtime-20261009` | `qualification-final.json` | `95ac961e7278289629e268c2510ff2b411c492ed0e644a9bd0699c88de22f28f` |
| `verified-root-runtime-20261009` | `post-commit.json` | `ab1acedc28b09812018d8a06cb9927ea7f06ef7152095a33ebb51dc8c4c4ecab` |
| `android-runtime-vm-20261009` | `qualification.json` | `c1b881f3daa22c3868df337579e316af195f28446fa3079e08c957e330c423a3` |
| `android-runtime-vm-20261009` | `postcommit.json` | `9496a6c37d2c093b30e0cb681dc7b1cfd169b856f94b007af1d617824b5f77d6` |
| `musl-publication-20261009` | `qualification.json` | `23bbd650cf95903d446df402b873578bb300e2d07745a38600eafc5c2ffbea66` |
| `musl-publication-20261009` | `postcommit.json` | `ee583255281150c1662e1093dc95007c6b7683ffd71ee668a47cb7c8fc54e663` |
| `guest-bounded-retention-20261009` | `env-qualification.json` | `06a1776d45f7036d53b810e210f69fe913dc869f557e3f9de4c69bf05d65c422` |
| `guest-bounded-retention-20261009` | `env-post-commit.json` | `ce3393dba385cd2c8d852d56a81e43f853ea6329b997b19fb7aaf41f1a0a1890` |
| `gap-exec-binding-20261009` | `qualification.json` | `94d5b63d18dd5545b99bbdeda08a8a390367e88634eebbc2985c01c9b1f3f733` |
| `gap-exec-binding-20261009` | `postcommit.json` | `d6caa6e26e0a536d192e232e6eda40ad34cf1cbc0191dc0135b8ad23bebebce0` |
| `mesa-iterator-expression-20261009` | `qualification.json` | `aaf0785b4ec9756309a8663cd2983ee94a54d5b0b2f702e814008dae9199edcd` |
| `mesa-iterator-expression-20261009` | `postcommit.json` | `f375323dd185fe6304c7c2438ed4769c6ebb3df4930bb5bdf55bf713274d9b15` |
| `musl-digest-lookup-20261009` | `qualification.json` | `670183649e88bfdce74e8275dc75341d7762505733efbf7a91f6b3c2af135fcb` |
| `musl-digest-lookup-20261009` | `post-commit.json` | `9acd9e988e3dafbf6dcf77631c4d9ce188aa71a7f0dc36eceafb9ef01a2923e2` |
| `android-syntax-primitives-20261009` | `qualification.json` | `3a9923c7e5e92df4340c94b6df01ec2e020f00ae4a8f6dfc81d3d5ef1e6a1535` |
| `android-syntax-primitives-20261009` | `postcommit.json` | `c516d9e27b45bfbee38e406442fe7d1db8f34cc76c441d98a4f227a67c2d0d58` |
| `android-error-retirement-20261009` | `qualification.json` | `629867e5482fc370c6bd363e43dc31074cb8edbda3c21f066f19582e86009422` |
| `android-error-retirement-20261009` | `postcommit.json` | `ac082f4322628db628f3b611f6284259c4e479d2d0ce6eb8ca02fa77bb85114b` |
| `gap-root-method-20261009` | `qualification.json` | `f58991dd2da4284039e32821136ace757a8c23f395869ede504963e9e584d7f7` |
| `gap-root-method-20261009` | `postcommit.json` | `cf1cd5c0a8887b0d15a0e581096defc52408899fa224c407ef9be179cb9df4ca` |
| `gap-owned-retirement-20261009` | `qualification.json` | `f47f1ae106d655f21a8d96ef8c6a6b457ed10d9b5c71808be3c45c87e9efd4e7` |
| `gap-owned-retirement-20261009` | `postcommit.json` | `bef9d50da20d86954c4d49331ba5d6d25f5bb5898b6a392842fd9758d8a3bf77` |
| `package-expression-retirement-20261009` | `qualification.json` | `0da4188cbe50efb57bea68f89be44da93fba171a4d1e25320be445c931dcb313` |
| `package-expression-retirement-20261009` | `postcommit.json` | `dc4a32ac3efef40f73b81f92432816c48ba19a5dfa3f757b770495252091bd16` |
| `dota-wake-resume-20261009` | `qualification-v7.json` | `c04d08fd3304f9e7b8dc7a20df74bb1d8b85da5d4382925585d0996996bab752` |
| `dota-wake-resume-20261009` | `postcommit-v7.json` | `a3b7a365065d2b20b51e3d931f90450b3882e5febdba7952c4abd5bbcac051f2` |
| `verified-root-main-20261009` | `qualification-final-corrected2.json` | `07a8446f05b67cbd708c2d6f33dc7ad42ae1869c6804cf5ec53eda4e75ef6182` |
| `verified-root-main-20261009` | `post-commit-corrected2.json` | `d7654f440ce278ed30923d7ab03c0ccd97041924cd99b817d241c0a14566a361` |
| `browser-controller-20261009` | `qualification.json` | `4a7098bd22cabd6eb10d284fde22826938fee6c4bd8ac2d48fe20af65a52e122` |
| `browser-controller-20261009` | `postcommit.json` | `c38ab8d56a1a44b7e44b7820df8f8eb41514106a353fca1508c150d9c1e7bb01` |
| `android-atl-controller-20261009` | `qualification.json` | `e7e9bde8a18678f4f4cc2065a2c5eed903bff969b644e24f0f21b2d9af4903f5` |
| `android-atl-controller-20261009` | `postcommit.json` | `6fa940f6fff35a7f11a2a116f4be46b85cbe97b2ae1dbd272c230698377207ac` |
| `package-owner-retirement-20261009` | `qualification.json` | `84acd157dc373fd5280ae3b9bea87e583b631aa5d32c8b899768b9ffaf0b9a50` |
| `package-owner-retirement-20261009` | `post-commit.json` | `261e81eabfc8aec3ed46be663b1c4910602f4fcff3f12f2fd08901f3ae42946f` |
| `gap-owner-reference-20261009` | `qualification.json` | `28e41da1a58ab056a522e5ea37dbde321bb27f038ed8bd4fbaf9e60d017db621` |
| `gap-owner-reference-20261009` | `post-commit.json` | `7cb8a91805e0a8075f0430df06bcf80aa8ab60c1ae2a3ae37de1ea9336564d41` |
| `gap-replay-retirement-20261009` | `qualification.json` | `21bc501a7b1d27e259af97bd04a5d2e465acd939dccb37d73789e026474195f0` |
| `gap-replay-retirement-20261009` | `post-commit.json` | `78b8e40ece8b4f5bb032debd9f59d7d0aa6c102dc79e5eca766c487a4a09f79a` |
| `android-atl-stack-20261009` | `qualification.json` | `f9533e906ee919112a7d043f05b506d94b0f237b21e343625c2bd03585ba21e0` |
| `android-atl-stack-20261009` | `postcommit.json` | `b257eb74f230c9cedc27bd8a40ac16a84ba06a205762cb7b8e2dc02066514a8e` |
| `qmp-input-20261009` | `qualification.json` | `3853dae4e6a830f18328072ad236a488a49ac4ede0228358bf261201a9295106` |
| `qmp-input-20261009` | `postcommit.json` | `d96e2eab8645c215242eeb7f523f6cb782c6235f054535ce45e61bedaf5d0e39` |
| `pci-arm-controller-20261009` | `qualification-v2.json` | `ea31385cdde9adc772144fbf46f075fd6f28703fcdeef1e53859cc12e6c1c945` |
| `pci-arm-controller-20261009` | `post-commit-v2.json` | `092e19d6a631fa217973739c37432b81f65ef2de7119b58cc9851d2ec7f1efe1` |
| `benchmark-controller-20261009` | `qualification.json` | `11f045199f0748222ae5dbff03c817a96641709d97d555ce0d6ef8ce37b5fb32` |
| `benchmark-controller-20261009` | `postcommit.json` | `7c39e50345950e37c786d6c4ce9351058aa55a27231618d82985f5c432bf9e4b` |
| `package-cpython-sdk-20261009` | `qualification-final-v3.json` | `7aac6785750b83442d56b69d04e04d6885a424c09b66b2f46c5aadd9749f53bc` |
| `package-cpython-sdk-20261009` | `post-commit-final-v3.json` | `f965e908d68e0d87b3582010f52969f060abf1e08795ae025147011108649c73` |
| `native-replay-context-20261009` | `qualification.json` | `1344e2d7cc4b904a5d59428e98ee65a2d62e4d3bac30166c734a7f24e1fe7098` |
| `native-replay-context-20261009` | `post-commit.json` | `fc202d896c06a6ab44e9621c0c03da3a0eac9c6f1c8c04fcf5b8ff6d0efb0397` |
| `package-consumed-errors-20261009/final-v2` | `qualification.json` | `4f38ff6a1a1c870452a26a7b56f0cc150e2e5bf45c48bfed82855aa09a52e0a9` |
| `package-consumed-errors-20261009/final-v2` | `post-commit.json` | `36b870f7a78b28c704fa7d7aa0010f00c1dfabc7f88ee7c7719831967fc53f0d` |
| `cpython-helper-backend-20261009` | `qualification-final-v5.json` | `0ce34c44ad6805dbaef4d94b4f469ab47cc3ded90b64a0b59fd3d5b4bbe220f7` |
| `cpython-helper-backend-20261009` | `post-commit-final-v5.json` | `09c78751a66d50f743818627520c17538a04c1c88c75b59a1f5e5ef8fe6863e5` |
| `cpython-temporary-manager-20261010` | `qualification-final-corrected-v2.json` | `721061a67bf019dc4de51f5b7ac24284c93a655f9570647e5c1ba2667c0db652` |
| `cpython-temporary-manager-20261010` | `post-commit-final-corrected-v2.json` | `8b6f71ebd8398b4c186def6010e6d2499196ba0d9f88ad191ffbb09f6bc1cc20` |
| `android-exit-retirement-20261010` | `qualification.json` | `7925a5ede73336a55e5235fe60936fcedec7bc13df9eeeb1c7da3b6ec33cf1e8` |
| `android-exit-retirement-20261010` | `postcommit.json` | `8e51659451ad86f7c44ca2adf6c3c273dd42010be5592f5fa4ec5a22b7eefb99` |
| `benchmark-stack-20261009` | `qualification.json` | `a9625cc462fdc1881588d3d02288548b0b4c8c9f578939179934e99a0537f66c` |
| `benchmark-stack-20261009` | `postcommit.json` | `24e0b2797ee4ff76cbebccd959125356234f4829572a77e3158893dd42ff5418` |
| `benchmark-stack-20261009` | `linux-qualification.json` | `c2976879c835792ddf43e2c4fe3290b5cfe46e56774683261cfcf16a11c9dfb3` |
| `benchmark-stack-20261009` | `post-linux.json` | `2a66be8077b2e199e4cfaf34a082dfe609419c8a6b8c381f0abfca3a8814f296` |
| `gap-library-core-20261010` | `qualification-final-v5.json` | `47a0a6bec8414828341b43750f99c8f8c316155641ae467dff2d91a4c0536fe4` |
| `gap-library-core-20261010` | `post-commit-final-v5.json` | `16f7a16e8e2714ace3cd0085114d7e21d5a0d1b8b4a4e4c21234c3bb1450b9b4` |
| `sampler-controller-20261010` | `qualification-final-v7b.json` | `b35836d62af0b3c8a28404f2c1a09880371dd3d008e4232f1ccd9c6d4ab5e37e` |
| `sampler-controller-20261010` | `post-commit-final-v7.json` | `76483f4c7bd1cd22a2d00139eebe93264c954a53ce9969f38716699cd271db39` |
| `package-errors-finish-20261010` | `qualification-v1.json` | `9932e1ff4bf6051205d50f26fb1bce5edc5ed4b77a2217e23e448fb4cedc4cfa` |
| `package-errors-finish-20261010` | `postcommit-v1.json` | `fac245ca2742318ce240fa08c6d07199f1cdf6668776f36fc82df3ed156ea3d0` |
| `android-boot-object-adapter-20261010` | `qualification5.json` | `553ca4242aa9724b9eda606966548b34d75ce7647817eb8101871d53d491e1a3` |
| `android-boot-object-adapter-20261010` | `post-commit5.json` | `1e74bd606a6c6fcb82542a34fc1776cb8c0b46a1d48b99896c0744ede1ba6050` |
| `android-boot-object-adapter-20261010` | `agx-peer-source5.json` | `aa246e7601a16534a15da7ad8f82a65d7496e77a68b691396a1860e244e09166` |
| `android-boot-object-adapter-20261010/sampler-integration` | `qualification.json` | `a9c4974e52db3fe9835c2b76475849124f2720d5e3dac6eeaf8f16ad3b992600` |
| `android-boot-object-adapter-20261010/sampler-integration` | `post-integration.json` | `a127ccf8599ebc7cf0eba802d5d4791f9a5f0556823186a172aa6f55317c7fe1` |
| `android-boot-snapshot-retirement-20261010` | `qualification5.json` | `7077f76a7b67965255b34802d7cad72357d847a0c9b940602c07d9178dec1451` |
| `android-boot-snapshot-retirement-20261010` | `post-commit5.json` | `564716985172a4a743ecca369ec32c70aa198cd2cfc4924f441f736084d0bf9e` |
| `android-boot-snapshot-retirement-20261010` | `agx-peer-source5.json` | `14187ea7465b2d680d1c12faee8e795d087177a7f612ce66d9880dd6e833a81b` |
| `android-boot-allocation-guards-20261010` | `qualification6.json` | `dd467e0709b4ef8f1502cee2715ab4aa8af9f89d8f2734f4b97b9c008cb33b07` |
| `android-boot-allocation-guards-20261010` | `post-commit6.json` | `413e86e37e0e9710dcdc2bda9c596d7710d4a3cf8619af2a7799923a930ba887` |
| `android-boot-allocation-guards-20261010` | `agx-peer-source6.json` | `54cc52ac3fa2805a8880bd5bc40d4a26bcc392dbd8fd131c063f1d4bbc70dd9c` |
| `pci-arm-controller-20261009` | `qualification-preparation-final-v5.json` | `a1994c183e56776a216badc253c4b019a1bc0486f504e39497d4982bf388265e` |
| `pci-arm-controller-20261009` | `postcommit-preparation-final-v5.json` | `5b13caeb94b0fc55322df31ffd1ce9b20f0780f3f07876100d7088b6f9d8d832` |
| `gap-fixed-name-20261010` | `qualification-final-v2.json` | `f5240c505ef077b40faa31dee931304d468b95e2de796dce7e1039bd266052f9` |
| `gap-fixed-name-20261010` | `post-commit-final-v2.json` | `82ef93dcf98ee42fd0f7802aade82645f17837f02943e247e3e143ca963ef9fe` |
| `gap-fixed-name-20261010` | `agx-peer-v2.json` | `cf98bf8f433bdf88ca213058cedd593d2a162e3759bed56894a79b0096ad14e9` |
| `iboot-helpers-20261010` | `qualification-final-v4.json` | `50bfebded4a8874ed6f6909b18387a05dd4e1a7fd3ee7221061dd0bf46cdecc8` |
| `iboot-helpers-20261010` | `post-commit-final-v4.json` | `3c93e824f4fe3d9d7d2778ffff7ee3d7ceeeef1b39bd0385dbd7fd135e2385da` |
| `iboot-helpers-20261010` | `root-peer-v4.json` | `105c4a909318b824692263ddc0e7026ae9e3533d9723fe4cebef0c31ab2dee34` |
| `iboot-png-20261010` | `qualification-final-v3.json` | `a04f0bfed1cb0f681afa0df4730efcb23613c8c42a9262c5fd79aa0c78c91109` |
| `iboot-png-20261010` | `post-commit-final-v3.json` | `bb2905995ed58b8d1b2bacf7c8554541f5e938cc66decf16ce86576929504521` |
| `iboot-png-20261010` | `root-peer-final-v3.json` | `49ef94fc8a72c88e0eb6690217b3277ee2f72c361a324a36b6110349ca31ae28` |
| `iboot-qmp-20261010` | `qualification-final-v2.json` | `a0e66cca7f02b5e28104e70a5c11ae003769355e929dd810f8821d69c9e613a6` |
| `iboot-qmp-20261010` | `post-commit-final-v2.json` | `6daedf48461df2f2b97fd28622c4b7508cdc0ca4f66e4bf108e6486173f0aabf` |
| `iboot-qmp-20261010` | `root-peer-final-v2.json` | `b6bf9f949290a3001461a92e82062f2aba206faf16e9295bd4982ccd760462e0` |
| `iboot-main-prepare-20261010` | `qualification-final-v1.json` | `e20938e3971fbf591ce37efbfccead2ecf0cb5ad37b60c373833499324aafa18` |
| `iboot-main-prepare-20261010` | `post-commit-final-v1.json` | `2be0031268bb866ab94f74b7f11d672be1d0154ee3a5da0720230ec5b51b9e06` |
| `iboot-main-prepare-20261010` | `root-peer-final-v1.json` | `0624417d03392e7459a3a9e3ca42df100c9ffec54da9b2ff8d93110b35938ff9` |
| `iboot-global-lookup-20261010` | `qualification-final-v3.json` | `0b4449ccb3f7277fcaf7abcd8d1377ea103655b0af1062e9a492fa6ebfe36f78` |
| `iboot-global-lookup-20261010` | `post-commit-v3.json` | `29b56cf1f86d64bdb7e8c8df2d67f0fd03fbc520882df7a0c2950e1770318697` |
| `iboot-global-lookup-20261010` | `root-peer-v3.json` | `2781aa767782e53de25f5836c3b189f96902c352c2d1ddac69b9812ed48fe17d` |
| `iboot-main-monitor-20261010` | `qualification-final-v1.json` | `f437b226131c83a56c1836a574f7e12f41331bdb79e1e769ad90bbfee2a1a8d5` |
| `iboot-main-monitor-20261010` | `post-commit-final-v1.json` | `0e3a058ef40fffda072d80f4bb96e09c9f996f97c0e51b6314a4429266758e55` |
| `iboot-main-monitor-20261010` | `root-peer-final-v1.json` | `21f4a2a3cb13ac9c7de7932f0a377ddd1ff0eb3d027f228b22ae4dfef72ba0e5` |
| `desktop-perf-fixtures-20261010` | `qualification-final-v3.json` | `62b8adcd5c03a310881fbffdbf83603a7ff9164d5b83c8825831d67cd7d61c67` |
| `desktop-perf-fixtures-20261010` | `post-commit-final-v3.json` | `b9a9e22756f49b09b5d81d3fef729cce1637975e62dfe51d550bbc23d2e008b8` |
| `desktop-perf-fixtures-20261010` | `agx-peer-final-v3.json` | `87d3ef77bfb2bab7450922b4e5aa0d35e1fc94c0b6c91d7cccaf03bf821f0769` |
| `android-run-object-adapter-20261010` | `qualification3.json` | `4a676c99c8c562d428833e5175f759ff152e98916485575a9e1d27c1260f89b9` |
| `android-run-object-adapter-20261010` | `post-commit3.json` | `7976aafd127a99780d2cf53f76d547b684d06f94678e7c2b32eb2107035ad326` |
| `vulkan-object-adapter-20261010` | `qualification-v10.json` | `295cbb8feb79014fa8e6bdaf61e21e5d714ccf3eafbd9de87673c55b328dda32` |
| `vulkan-object-adapter-20261010` | `post-commit-v10.json` | `fe85696045c5f5725d422883da7dbce18cc0478818f91e7b329f2031360068c8` |
| `tlb-policy-generator-20261010` | `qualification-final-v1.json` | `8e34e78b90e850f890a7b16b6f9d02eb2d93e0a966ff1d09ce79358dce847066` |
| `tlb-policy-generator-20261010` | `post-commit-final-v1.json` | `5fd1dfe62fe0776a2a4ae4fb9776ed71f260fc8e4a030a9801bcb39675c3327d` |
| `tlb-policy-generator-20261010` | `android-peer-final-v1.json` | `b95c72b452bd4b9da33de82e5fd4c88c93d7b38916f5983fc5ca89bd2dd353fa` |
| `mounted-disk-host-generator-20261010` | `qualification-final-v1.json` | `2f16ad38b03b07c928636f226e07614c24a212f731e8d6fc029d6c534bbc9b3f` |
| `mounted-disk-host-generator-20261010` | `post-commit-final-v1.json` | `fa9f7bbc7467e63715339faed2dd03b0b653f1993559e278b99dcb5c4e2b337b` |
| `mounted-disk-host-generator-20261010` | `android-peer-final-v1.json` | `2970df5238d0a3a6aa5d102192ee37588fad1c733e08d3e899c10ebbd5a49231` |
| `scheduler-qos-host-generator-20261010` | `qualification-final-v2.json` | `64028d7716499bb3fc2cbd52bd09c5aaab2339f487e4829452502d69d8cdac9e` |
| `scheduler-qos-host-generator-20261010` | `post-commit-final-v2.json` | `74d9c02a2323d77b46834528824caeac243caecd8f570df7cde4fb0b5f2ea7b0` |
| `scheduler-qos-host-generator-20261010` | `agx-qos-peer-final-v2.json` | `bda9704322f89e72e91222a43f307faf6d5060ba80ac0c092544650d14151309` |
| `scheduler-preemption-host-generator-20261010` | `qualification-final-v2.json` | `315c3afebf828b7c1039d9d915c2490014c8a6db3fe8306783092d160c5e9156` |
| `scheduler-preemption-host-generator-20261010` | `post-commit-final-v2.json` | `07299c9ee36fb0883f42d41c14e6e3c1224780d67f5358bd1771347828967e5a` |
| `scheduler-preemption-host-generator-20261010` | `agx-peer-final-v2.json` | `ed9972f800f2a6c980f131804bb7ccabe710bc90b9de7528bf5c99681ffca610` |
| `virgl-vm-controller-20261010` | `qualification5.json` | `b47f8beac7dc66bcaa4a9da8459f10b1e7aea0e3ca50f1aa428b8ce70402951e` |
| `virgl-vm-controller-20261010` | `post-commit5.json` | `d9485075b3a9cc6bbecce4c10726e08d346e5d661fddeb97e3210e3c85b1c5d1` |
| `virgl-vm-controller-20261010` | `agx-peer-final-v5.json` | `059bd587b50fcd91a4d98d3a8d14878edb74690ca31b6f700e615c3511c811f7` |
| `boot-policy-fixture-20261010` | `qualification-final-v5.json` | `4afc0166b0cce5a6c37060bc770d842ae3a6b886f7966210abf841ddd39f5538` |
| `boot-policy-fixture-20261010` | `post-commit-final-v5.json` | `1e0dc09603e43671b28cc8bba181f798ea9a53d53ba4c3d297f7a7cc0779c63f` |
| `boot-policy-fixture-20261010` | `agx-peer-final-v5.json` | `6e95d8d3758749288934b57bcb6da936d9227ac3cfe101374eb2ebdb2aad7210` |
| `spi-host-controller-20261010` | `qualification-final-v3.json` | `0f9ac5d6c88d643f21ff90a2b83c1660d3a81d2625023afedc87fc279785a761` |
| `spi-host-controller-20261010` | `post-commit-final-v3.json` | `6cecf218de8f3d8e0d896d4f1c3aeb35d36ec20c0d9d370725eacbbaa9e578db` |
| `spi-host-controller-20261010` | `root-peer-final-v3.json` | `2604a7f67f5a79f08a4222b72a20d9c1b9a239e080c094e951fa8572ea8c2acc` |
| `speaker-host-controller-20261010` | `qualification-final-v2.json` | `c45af29bacbb428ccc182752f67c3f3d532104a775cf90a92c4a9daaf858027a` |
| `speaker-host-controller-20261010` | `post-commit-final-v2.json` | `3d6c96140ff9b1b3c7819ba41b7057c806ba8e6dc508f045034ae57d944b855e` |
| `speaker-host-controller-20261010` | `root-peer-final-v2.json` | `98322f2af6623c88210dd8035c8b5d650010074798e90138613e8d76a8925427` |
| `wifi-control-host-controller-20261010` | `qualification-final-v2.json` | `9609f6ac9b4fd204c853f0317af761795fec437ad4cd62e80ed399cacb6ef386` |
| `wifi-control-host-controller-20261010` | `post-commit-final-v2.json` | `d5e3af4c17330b75aa6e187b97ecc69507f8b8a2954f7d1d28940bf000e1bbe8` |
| `wifi-control-host-controller-20261010` | `agx-peer-final-v2.json` | `e21c1e10e87034872ec37542d9733534a6973b02a2905eabd0c684ea013ff399` |
| `vulkan-fixture-object-adapter-20261010` | `qualification-v3.json` | `f4b83777bb774697c76668103008e18426f9ea30809daeba5ff7f890b1590c2a` |
| `vulkan-fixture-object-adapter-20261010` | `post-commit-v3.json` | `1207dd54a5705eddb88e50a7dd459d55eb0d19ab913d8449b133a65ed14cc1e2` |
| `vulkan-fixture-object-adapter-20261010` | `linux-host-peer-final-v3.json` | `5cc198e2b25137e3d106931c71c7f8ae635e4b4479ef3463d16e6ad7658f35c9` |
| `openbsd-security-controller-20261010` | `qualification-final-v2.json` | `acf899db3c06af1e72816bc99e0f218ce371057a2666b3a662deef0f3347b1a8` |
| `openbsd-security-controller-20261010` | `postcommit-final-v2.json` | `16154c5be44ff8dcbadc4cd6dc5f84b5ba44537a75a0e2786860f2143430b0f1` |
| `openbsd-security-controller-20261010` | `agx-peer-final-v2.json` | `6fb5409c55e33713ce9a6cf97f668aee4d19e7689aa08607ebe40d22874d03e0` |
| `cpu-policy-host-controller-20261010` | `qualification-final-v2.json` | `f1ae65a5f35a88f8eeb30a70e687b053a5bfa2eae3fbd0fa96be55a3d7f7b385` |
| `cpu-policy-host-controller-20261010` | `post-commit-final-v2.json` | `7add134100d283f1621480ca1d115d7a568f800f5e5cae4d1445df68db9c9fcb` |
| `cpu-policy-host-controller-20261010` | `android-peer-final-v2.json` | `55e553ea3c4adcf79d5cb54047aefb80457fd54d4f20d5fbecff825e60d85b96` |
| `disk-no-sync-host-controller-20261010` | `qualification-final-v2.json` | `fcfa3931ba28294f510a66c8ac1f1309f103b3bb7550f5963ed10c3cf2b7cbf8` |
| `disk-no-sync-host-controller-20261010` | `post-commit-final-v2.json` | `319ed189597453f2be4c3d3bb0748c079f024adff88ef56ef83bef7cd0645bee` |
| `disk-no-sync-host-controller-20261010` | `linux-host-peer-final-v2-mode.json` | `3b9cbfac7efc915240459555f1a68af456a0e868274a9f7df2b0bdcbef865260` |
| `reboot-persistence-controller-20261010` | `qualification-final-v2.json` | `6e29ef7c5ca5b49ac5504868e1211f1086c60697d8e01009d6122c83212d363c` |
| `reboot-persistence-controller-20261010` | `postcommit-final-v2.json` | `261e76af63f28e15c2c963455c2e5eed67061ba968733445bec478deb805d74f` |
| `reboot-persistence-controller-20261010` | `agx-peer-final-v2.json` | `33ec50f9f6299cba640d291717dff8df04c9dfc2c62b7d97241e280db0860b07` |
| `wifi-protocol-host-controller-20261010` | `qualification-final-v5.json` | `3ac7df7ee5eb1e454daea656fee05b887366d9704785bf9cca9770bf84707fd4` |
| `wifi-protocol-host-controller-20261010` | `post-commit-final-v5.json` | `ce146531afeac4d8a639a3fabcc3e9023e7a9be6132093cef0d5ecd623e98151` |
| `wifi-protocol-host-controller-20261010` | `agx-peer-final-v5.json` | `ba54ddd76677f4d85fb748298cf988308b418231f278325c3e80e465f8a2b129` |
| `wifi-helpers-host-controller-20261010` | `qualification-final-v3.json` | `7bcadca67d53b2379abddb884551ab8a4b0df83f58ff5a5f1ceb364a7124626e` |
| `wifi-helpers-host-controller-20261010` | `post-commit-final-v3.json` | `50e906d6a35efc7a665332f7506d12258ca6ab7309e6e341fac932c2c131b66b` |
| `wifi-helpers-host-controller-20261010` | `root-peer-final-v3.json` | `2a500c59440e8b3c8854a91afd2c9807f691b3fdb8c90bfabf279eb1bef80189` |
| `ans-host-controller-20261010` | `qualification-final-v9.json` | `aed9185d375692b908d9cb045f689f39be5331939b4d516ef36e59c89b8c0ca7` |
| `ans-host-controller-20261010` | `post-commit-final-v9.json` | `88a394d12eef9f8e5f2ff6a5f252e2abdc15e97cb277744aa86a2f3ecc73bdd3` |
| `ans-host-controller-20261010` | `root-peer-final-v9.json` | `12f6cde759c3705bc24e02179a2cb6b2b30295974b70bca08c2fd7367120af7f` |
| `wifi-platform-host-controller-20261010` | `qualification-final-v4.json` | `6d261f072a8bee82a8e1702bf6a233a407888405df1fa00b191ec49133373cda` |
| `wifi-platform-host-controller-20261010` | `post-commit-final-v4.json` | `000ed9a384a83ea2489401332bd5b57566a30dfed380290d612106059d98e283` |
| `wifi-platform-host-controller-20261010` | `root-peer-final-v4.json` | `cda5121249c055c339262be9aae7524525394b784a8e142c91b1ce31bef597bd` |
| `boot-stdlib-dispatch-20261010` | `qualification-final-v2.json` | `3151fb3f396cf1a12545281bdcba013201d136adfa587698c2395a08b5d80463` |
| `boot-stdlib-dispatch-20261010` | `post-commit-final-v2.json` | `ec3c60e5eb666e2d968c9163949303ab2e5a05d95c4ce43163f98e71db7bf469` |
| `boot-stdlib-dispatch-20261010` | `agx-peer-final-v2.json` | `cdd76e12e2e451df068933701559d41b39b6c0330e307877767f4f01077ab5aa` |
| `numa-vm-host-controller-20261010` | `qualification-final-v3.json` | `0e12495ab17e9fecab9dc4b8544d2fd8f33efdba595cb94a5035168b5b38dbb3` |
| `numa-vm-host-controller-20261010` | `post-commit-final-v3.json` | `fbeee7067211fdd33d998109b38fbb7caf6be25a6e7658e520c20c42b565ed12` |
| `numa-vm-host-controller-20261010` | `linux-host-peer-final-v3.json` | `b636116b21db9b0835197ead4d44307f2a5e2a6d0520e9afb29238b872713572` |
| `sound-controller-20261010` | `qualification-final-v2.json` | `ec6975cc6b453b90f24e9cd66a59b4d62df7c81115bca9c9c8722abbef5a5e64` |
| `sound-controller-20261010` | `postcommit-final-v2.json` | `8393d48c90f65631d787da3655e3dfe8697c3c737f5f48c15781e32627f83115` |
| `sound-controller-20261010` | `agx-peer-final-v2.json` | `ecc719b84da5636b57fd34ce568fd8173ddce845a3af821d924bdfb2b658b2f0` |
| `vmx-host-controller-20261010` | `qualification-final-v6.json` | `b57253c49a6defcff0282551e63bed73d37b2f12435a36c1b8ad9406b62a8b40` |
| `vmx-host-controller-20261010` | `post-commit-final-v6.json` | `b2027799e3ea5f461ddf7a30a17df3580fa245b962f20adf52e820e17a495fe4` |
| `vmx-host-controller-20261010` | `agx-peer-final-v6.json` | `278c8fe8a6394b8bf378e4af33131bf075c828cafdc93f504e72724f007c6bc3` |
| `roblox-stage-controller-20261010` | `qualification-final-v3.json` | `9ab7ebb121d0252868eb46b016f250ce0cd44aef9c9d916b9d57ec03c09958a1` |
| `roblox-stage-controller-20261010` | `post-commit-final-v3.json` | `7d34a8ec5a6e484ff49e930f5f481fe5e2c35104cd678a3a46dcd5099d1a0f98` |
| `roblox-stage-controller-20261010` | `android-peer-final-v3.json` | `268d5ba8923a937309500d91717c40aa377420dd3a423a8f4f732cfbf10957f7` |
| `alloc-bench-vinix-controller-20261010` | `qualification-final-v2.json` | `4e0408e65688576ee57fce9ce65dba1019aef5b7744a1aa1b13709ee16bfe372` |
| `alloc-bench-vinix-controller-20261010` | `post-commit-final-v2.json` | `815521a5e8bf93d924381a7ec50d8f291adeb42fc8bab892c2028ffc829c0d81` |
| `alloc-bench-vinix-controller-20261010` | `linux-host-peer-final-v2.json` | `02b69ef12f745ab84da84f1f2c3fce827bc9b04ec5f946ca3e0c48fd10db4609` |
| `emulator-desktop-preparation-20261010` | `qualification-final-v3.json` | `67575f868295bfffdf6fe6ce139ec7a7e2da8e149c6f0ec6b78a5e5294609c22` |
| `emulator-desktop-preparation-20261010` | `post-commit-final-v3.json` | `11d3788acf178050456bd9f0c625c91bd6711c6fd7cc1c9dc203516587b0e0cf` |
| `emulator-desktop-preparation-20261010` | `linux-host-peer-final-v3.json` | `8b8795928121ed0bdd12a41dbc6a743aab4e19138e964648189fb4dc183e67cf` |
| `package-load-global-20261010` | `qualification-sdk-v2.json` | `c61dc9c26cf4820fae1acd4e035b4bfabc762ea6526e6cf7123ce1979da932d2` |
| `package-load-global-20261010` | `post-commit-sdk-v2.json` | `923498acfc9f8be1919286af9f2c4c54958024c650544663c1ea77c02239cccb` |
| `package-load-global-20261010` | `agx-peer-sdk-v2.json` | `333b219b702cceebc4b10e0f1738fae1e822a4632ea6ffddbedbf924b5ebc916` |
| `virgl-load-global-20261010` | `qualification2.json` | `1d539762951fd44d1654920db03f43c0c13fd2af6cb4771998bf438caa482edd` |
| `virgl-load-global-20261010` | `post-commit2.json` | `8274ac0488a1f7426bab0a583b76156e74fb31c3f3ec0156f54c89a6774926a9` |
| `virgl-load-global-20261010` | `agx-peer-final-v2.json` | `ffd9acbef433e4b1488a27ff24d0b11d339fbe166e63810589c3a67b47075eeb` |
| `dual-stream-capture-20261010` | `qualification-final-v1.json` | `8623cf893a97f53e3155999ac4c870d2320aaca5c989979ecffacae07643f3ba` |
| `dual-stream-capture-20261010` | `post-commit-final-v1.json` | `97c5fac5c6a20b87ed9c356fb558558b3a60134362bbeb5f08f7b8e804686cf8` |
| `dual-stream-capture-20261010` | `agx-peer-harness-correction.json` | `2be1e1daef6b23c9275faa28d0e810a3a92d98b3eb3297b70e0c2e0d5660d34d` |
| `unix-generator-paths-20261010` | `qualification-final-v1.json` | `372eac1230766c128ea7296db47eb59a23711870308a78612607305b4213b945` |
| `unix-generator-paths-20261010` | `post-commit-final-v1.json` | `c0ba21a0289ac730c642eadd0706a11447b0e328fd40ebe7f16f1c1285dc881f` |
| `unix-generator-paths-20261010` | `agx-peer-harness-correction.json` | `456dd757cc7c4b758401850c8dd4fda93c548f4338119b3cbdc9569ced6f93c7` |
| `nm-parent-codec-host-controllers-20261010` | `qualification-final-v1.json` | `f92625a7ab99eea0c1b69749c37ae425f6b717524e6389df63fc6deb96cc6d20` |
| `nm-parent-codec-host-controllers-20261010` | `post-commit-final-v1.json` | `e4ec6deb6dd9a975127ef3ab96fbca401091dcc8b47143b616595da3e6f1bafa` |
| `nm-parent-codec-host-controllers-20261010` | `root-peer-final-v1.json` | `a4a4b4757bded0937890a86c7e2ddd605a47778a2fa3d5a50fc5b3d9d39931e5` |
| `sound-controller-20261010/loader-fix` | `qualification.json` | `f5e4e2c3055cd3c779f8d7937b18251bf28a80e0b26865ac06a47c0331511171` |
| `sound-controller-20261010/loader-fix` | `postcommit.json` | `0ccd107b7717e92a9406284f5c991f7c38eadb8abb0439b72797d912c09c0fb0` |
| `sound-controller-20261010/loader-fix` | `root-peer.json` | `960cec6a7007ae86ea8619fef955063c07632117e97d322aded506f23e53f1b2` |

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

The filesystem stage passes all eight target profiles on ARM, Rosetta x86 and
ASan/UBSan, preserves direct power cuts, and independently checks each completed
disk with debugfs and e2fsck. ARM read-ahead, accounting retention and all six
sparse epochs pass on the prepared kernel. Full accounting passes its guest
assertions but fails the final filesystem check; x86 retains existing retention,
read-ahead and sparse timeout failures, including frozen C controls. Detailed
evidence and limits are in [filesystem-tools.md](../build-support/native-compat-tools/filesystem-tools.md).

The host policy stage passes all five workflows on ARM, Rosetta x86 and the
ASan/UBSan controller, plus instrumented production parser/attribute models.
It retains exact frozen C/V host differentials and fixture bytes, adds current
non-journaled ext2 dependency stubs, and verifies timeout/EOF/SIGINT retirement,
60 FD/PID cycles per host, failed workspace cleanup and cold native fronts.
See [host-tests.md](../build-support/native-compat-tools/host-tests.md) for
commands, evidence and the explicit absence of kernel-build or VMX-entry claims.

The Apple/Wi-Fi command stage retires fourteen frontends and provider adapters.
Its native CLI, private work, SIGINT/direct-child cleanup, 24 fresh entry-point
builds and seven unit tests pass on ARM, Rosetta x86 and ASan/UBSan. Independent
control/helper host goldens and both guest ELF builds pass. Original C and V
control guests pass on the prepared ARM kernel; both hit the same x86 bundle
`fclose` failure and retain the original deadline. Strict undeclared `memdup`
fixture failures and ANS provider dependency/assembly errors remain visible.
No fixture assertion or compiler guard was relaxed and no kernel was rebuilt.
See [runner qualification](../tests/apple-protocols/runners.md) for evidence.

The SMC/display-hotplug stage retires three Python files and the obsolete
borrowed-object V bridge. Six native command builds, eight shared tests,
original API/CLI producer parity, failure and SIGINT owners and cold frontends
pass on ARM, Rosetta x86 and ASan/UBSan. Independent display-hotplug C/V host
results match on all three profiles; original C and V static model guests pass
on both prepared kernels. SMC retains its current strict fixture `memdup`
failure, with all 27 verdict checks intact. No kernel was rebuilt. See
[qualification](../tests/apple-protocols/mailbox-hotplug.md) for artifacts.

The serial-tool stage retires six Python files. ARM, Rosetta x86 and
ASan/UBSan command builds, 24 original init option combinations, SDK objects,
actual RSP cores, process-group cancellation and cold entrypoints pass. All
three ARM init policy guests pass for both V and original C programs; ARM
memlock passes every group. Prepared kernels retain their churn, x86 memlock
and real-time failures. Realtime receives no file-removal credit while its
import callers remain. No kernel was rebuilt. See
[qualification](../tests/native-guest-tools/serial-tools.md).

The emulator-input stage retires four Python files. All three host profiles
pass actual MIPS builds, complete N64/PS2 artifact comparisons, streamed
download and archive guards, 27 standard-descriptor layouts and LLVM/V/make/
curl cancellation. Fresh PCSX-ReARMed and native frontend builds and fresh
pinned Tetrade downloads pass. The independent original make recipe produces
the same complete PS1 archive with a shared SOURCE_DATE_EPOCH; license notices
match exactly. N64/PS2 core builders and guest/desktop controllers remain
pending. No Python was run or kernel rebuilt. See
[qualification](../build-support/native-emulator-tools/README.md).

The core-builder stage retires two Python commands and their obsolete borrowed-object
controllers. All three host profiles pass worker, receipt, ordered-log, standard
descriptor and cancellation checks. Independent original recipes reproduce all
220 upstream objects and both ordered archives; both native frontend integrations
pass. The N64 native host boundary and distributed source closure pass. A Linux
ARM/glibc 2.39 worker build and run pass; the local Linux V bootstrap crashes, so
this does not establish a native Linux compiler build. No Python was run, kernel
rebuilt or new guest gameplay established. Guest and desktop controllers remain
pending. See [qualification](../build-support/native-emulator-tools/core-builders.md).

The emulator controller stage retires seven Python files and the unused borrowed
preparation/QMP query. ARM, Rosetta x86 and ASan/UBSan host checks pass, including
complete controlled desktop workflows, all 27 standard descriptor layouts and
SIGINT during an unanswered socket command. All six cold fronts pass from /tmp.
The three ordinary ARM emulator guest regressions pass with the unchanged guest
workloads and frozen kernel. Historical C controls fail their status-label check;
the actual N64 desktop boot fails the retained fixed-coordinate start-game check.
Those failures remain recorded; actual desktop gameplay qualification is incomplete.
No Python was run or kernel rebuilt. See [qualification and limits](../tests/emulator-desktop/controllers.md).

The disk controller stage retires seven Python files and obsolete object bridges.
ARM, Rosetta x86 and ASan/UBSan host checks pass, including the 17-epoch journal
model, fragmented markers, owned writer retirement, read-only sparse 4 GiB export
and complete payload checks. All seven public fronts pass cold builds from /tmp.
Real reboot and mounted-policy guests pass on both architectures; production
journal restart/inspection and blank 4 GiB formatter scenarios also pass on both.
Mapped sync, syncfs and background pass on both, with private/pageout passing on
ARM. No-sync exit and mapped retention failures remain recorded. Frozen kernels
lack journalcut, so actual injected cuts were not requalified. No Python was run
or kernel rebuilt. See [qualification and limits](../tests/native-disk-tools/README.md).

The system controller stage retires twelve Python files and obsolete query bridges.
ARM, Rosetta x86 and ASan/UBSan host and complete CLI checks pass, including PTY
retirement, packet boundaries, echo shutdown, root installation and quoted QEMU
arguments. Ninety strict guest preparations and sixteen cold public fronts pass.
Frozen-kernel guests pass security, mount, normal/pressure paging and all eight
securelevel cases on both architectures, plus ARM NUMA, persistent securelevel, root reboot and
the full 768 MiB/8 GiB writeback workload. IPv6 networking and packet checks pass
on both architectures; the original guest retention assertion still fails and
remains a failure. Docker controller checks pass; full Docker smoke needs missing
daemon staging. No Python was run or kernel rebuilt. See
[qualification and limits](../tests/native-system-tools/README.md).

The device controller stage retires nine Python files. ARM, Rosetta x86 and
ASan/UBSan cold builds, independent host checks, complete CLI checks, strict guest
SDK payloads and extracted production driver fixtures pass on all three profiles.
Eight native fronts pass cold compilation and help or full fixture checks. Real
frozen ARM guests pass fsync isolation, read-only VirtIO/cache/alias/raw-write
checks, synthetic 130 MiB package ranges, sound and default PCI Linux ABI startup.
The original fsync failure prefix and MMIO device order are preserved; initial
port mismatches and shared-host disk failures remain recorded. The old exporter
adapter stays for its unported game caller and receives no removal credit. No
Python was run or kernel rebuilt. See [qualification and limits](../tests/native-system-tools/devices.md).

The Dota controller stage retires eight Python files. Eighteen cold builds and
independent host checks pass on ARM, Rosetta x86 and ASan/UBSan. Thirty complete
controlled success/failure runs pass and retire QEMU; interrupts return 130 and
retire their controlled guest on all three profiles. All five public fronts pass
compilation/help checks. Real frozen ARM guests pass the paired glibc and WAKE_OP
controls, translated V/C mapping variants and Valve library-load smoke. Lavapipe
fixed modes pass; strict control rejection on the newer kernel remains recorded
separately from qualification on its original frozen kernel. Game execution and
rendering are outside this stage. No Python was run or kernel rebuilt. See
[qualification and limits](../tests/dota2/native-controller.md).

The game capture stage retires seven Python files and inline screenshot Python.
Eighteen cold builds, host contracts and complete controlled game failure/capture
cases pass on ARM, Rosetta x86 and ASan/UBSan. All three profiles return 130 and
retire QEMU on interrupt. Actual NBD/QMP, image formats, eight network bridges,
real signed QEMU copies and idempotent preparer checks pass. A real ARM game
launch reads the export without errors and correctly reports game exit 139;
a repeat reaches capture-only status without a launch marker. Neither verifies
rendering. The original and updated broader emulator fixtures fail at the same
N64 screenshot step; QMP protocol/timing/interrupt controls pass. No Python was
run or kernel rebuilt. See [qualification and limits](../tests/dota2/native-game.md).

The verified-root and boot stage retires ten Python files. Thirty cold builds,
full host suites, genuine signature checks and native resource contracts pass
on ARM, Rosetta x86 and ASan/UBSan. Twelve complete controlled observer runs
and six interrupt checks retire their QEMU owners. All nine public launchers
compile and pass help checks. Actual ARM and x86 guests pass boot artifact
checks and all eleven production-kernel root cases; x86 additionally verifies
temporary firmware trust and rejection of unsigned/modified loaders under
Secure Boot. Native V edits private EDK II templates. ARM firmware enrollment
and optional Linux veritysetup compatibility remain outside this qualification.
No Python was run and no kernel rebuilt. See [qualification and limits](../tests/verified-boot/native-tools.md).

The Minecraft stage retires six Python files, including the extensionless
sign-in command, and packages static native fetcher/sign-in executables. ARM,
Rosetta x86 and ASan/UBSan host suites and actual curl workflows pass, including
six signal/descendant retirement checks. Both static guest builds and the
existing launcher/package-manager regressions pass. Real LWJGL 3.3.3 and 3.4.1
JARs pass independent decoded-payload and instruction checks. Actual ARM and
x86 QEMU guests run native curl and pass full/cache/index-only/checksum
preservation plus sign-in preflight with frozen production kernels. No Python
is run or kernel rebuilt; live account sign-in and game rendering are not
qualified. See [qualification and limits](../build-support/minecraft/native-tools.md).

The saved allocation-campaign analysis stage retires ten Python scripts in one
complete dependency closure, including all three preserved comparator copies,
recomputation and negative fixture suites, and the evidence materializer.
Every saved JSON observation/provenance value and Markdown report body matches;
all 170 original checks plus native CLI tampering pass per campaign. All 145
archived blobs verify and all 111 historical source records recover exactly.
ARM, Rosetta x86 and ASan/UBSan cold builds, CLI and public-bootstrap checks,
100-cycle descriptor measurements, SIGINT/SIGTERM and exited-leader/descendant
retirement checks pass. The saved captures, plans, manifests and reports remain
unchanged. No Python runs, new timing captures or kernel rebuilds are used.
See [native analysis qualification](../tests/alloc-bench/native-reports.md).

The GL-tooling stage retires four Python files. Native generation and standalone
staged rebuilding preserve module/source hashes and target flags; maintained
callers and cache inputs use V. All four tools build on ARM, Rosetta x86 and
ASan/UBSan, and all independent rendering fixtures pass. The x86 sanitizer found
an existing EGL extension pointer type mismatch, corrected with a const SDK type
alias. One hundred native PTY lifecycles per profile keep descriptors flat;
SIGINT/SIGTERM and exited-leader/descendant retirement checks pass. The native
ARM Mesa image preparation and image preflight checks pass. No Python or fresh
QEMU rendering is used; the shared package service is being ported next. See
[GL qualification](../gl-triangle/native-tools.md).

The source-tooling stage retires nine Python files. Native staging preserves
generated content and links, including Unicode boundaries and truncation before
transformation failure. Native package and clipboard suites, portable staging
closures and committed presenter builds pass on ARM, Rosetta x86 and ASan/UBSan.
Repeated uploads and command owners keep descriptors flat; real Unix QMP replies,
blocked interrupts and descendant retirement pass. Existing package-persistence
and live source-sync scripts pass with the native service. Interrupted uploads
retain the previous overlay and remove their private files. The ARM X11 clipboard
client and overlay prepare with the existing cross-toolchain. No Python, fresh
kernel build or fresh QEMU interaction is used. Shared CPython bridges still used
by other controllers remain counted. See [source-tool qualification](../tools/source-tools-native.md).

The desktop-performance stage retires eleven Python files, including four saved
allocation-benchmark runners and three v6 preparation drivers. Fifteen final cold
builds and full report/controller fixtures pass on ARM, Rosetta x86 and ASan/UBSan.
Native PTY owners keep descriptors flat; reserved-leader descendant retirement
and blocked-QMP SIGINT/SIGTERM checks pass in all three profiles. Serial output
continues draining under QMP backpressure. Saved drivers preserve PID/log ownership,
stream hashes, independently inspect historical coverage and reject tampered
results or inputs. The public host suite, shared source-tool regression and three
materialized native entry-point builds pass. The unchanged production sampler
cross-builds to static AArch64 ELF. Captured guest workloads/logs stay unchanged;
no Python, fresh kernel build or fresh QEMU interaction is used. See
[desktop-performance qualification](../tests/desktop-perf/native-tools.md).

The Dictionary stage retires two Python files and replaces two embedded Python
source-processing blocks with V. Eighteen cold builds, original data fixtures,
utility-source and cache invalidation suites pass on ARM, Rosetta x86 and
ASan/UBSan. Every real archive conversion matches the existing 147,306-headword
lexicon and license exactly. Native fetch fixtures cover failure/output bounds,
valid publication, interrupts and descendant retirement; atomic-write descriptors
stay flat. The public preparer passes. The broader utility workflow reports
421 passed / 21 failed / 442 total model tests; an independent reconstruction
of the frozen procedure produces the same source and reproduces the same failures.
Assertions remain unchanged, and later memory/IPC stages are not claimed.
Presenter option parsing is fixed in `e8eb94f3`. No Python or fresh kernel/QEMU
run is used. See [Dictionary qualification](../build-support/dictionary/native-tools.md).

The core VM stage retires seven Python files. Nine cold builds and full host
controller suites pass on ARM, Rosetta x86 and ARM ASan/UBSan; six public native
fronts and CLI failure checks pass. Independent frozen marker lists, all missing
and duplicate markers, environments, two-boot sequencing, real PTY controls,
large output, resistant timeouts, both interrupt signals and descendant cleanup
are checked. One hundred PTY launches per profile preserve descriptor counts.
Saved CPU models are exercised through actual recorded launch arguments. Closing
the terminated PTY master before the sole reap fixes a measured macOS teardown
stall while keeping the leader identity reserved through group retirement.
Captured evidence and guest code remain unchanged. No Python, fresh kernel build
or fresh QEMU boot is used. See [core VM qualification](../tests/qemu-core/native-vm-tools.md).

The cache/Office stage retires six Python files and the obsolete Office object
bridge. Thirty-nine cold builds pass across ARM, Rosetta x86 and ARM ASan/UBSan,
including final compiler-discovery checks. Native CLI/signal fixtures, tree and
build-key suites, both original fake-toolchain workflows, four public fronts,
public workflows and shared command regression pass. Compiler/linker recipes,
all-job completion and submission-order failure selection remain intact. Exact
SDK rename preserves failed destinations and removes temporary state files;
state writes preserve descriptor counts. Interrupting two active compiler groups
requires all descendants to disappear while prior binaries and state survive.
Content-key bytes remain unchanged; staging/desktop/Office state explicitly
upgrades to version 3 with native producer dependencies. No Python, fresh
kernel build, real Office cross-build or guest boot is used. See
[cache/Office qualification](../desktop/tools/native-cache-tools.md).

The Apple boot stage retires all nine Python files in that family and its
obsolete iBoot object bridge. Forty-eight cold builds pass on ARM, Rosetta x86
and ARM ASan/UBSan, followed by eight public cold fronts and nine syntax checks.
Frozen C/V boot goldens, ten binary converter cases, all 78 ABI fields, live
IORegistry (233 matched, four skipped, zero failures), independent memory
oracles and shared command regression pass. Eleven real Unix-socket QMP modes,
verbose inherited streams, signals, descendant retirement, output preservation
and flat descriptor counts pass. Explicit static fixture/reporter storage fixes
compiler-generated allocation imports while preserving every assertion. Real
reporter/ustar, assembly stub and private AArch64 loader builds pass. Historical
ADT/boot/scratch/firmware/AIC bytes match completely; the capped historical
image is compared only over its retained 1 MiB prefix. No Python, fresh kernel,
QEMU guest or hardware boot is used. See
[Apple host-tool qualification](../apple-boot/native-tools.md).

The memory-controller stage retires both remaining Python files in that family.
Twenty-one qualified cold builds pass on ARM, Rosetta x86 and ARM ASan/UBSan,
with two public cold fronts. Complete independent C/V memory outputs and all
22 large-I/O fault cases pass on every profile. Eight static target C/V
executables pass on AArch64 and x86-64. Compiler and guest SIGINT/SIGTERM
fixtures retire descendants; cache units and original guest-supervisor
regression pass. A uniquely named signal callback fixes a measured compiler
name collision when cache and guest modules are combined. Darwin disables the
unsupported LeakSanitizer option while preserving ASan/UBSan and allocator
import checks; Linux retains leak detection. No Python, fresh kernel, QEMU guest
or hardware boot is used. See
[memory controller qualification](../tests/memory/native-tools.md).

The generator stage retires ten Python files. Twelve qualified cold builds
pass on ARM, Rosetta x86 and ARM ASan/UBSan, followed by 23 public cold builds
and ten syntax checks. Both complete 196-byte native kmod descriptors, symbol
exports, alignment and callback relocations match the immutable C input.
Strict benchmark workloads, source/header manifests, serial object recipes,
compatibility aliases and the independent sampler ownership/failure assertions
pass. Malformed metadata/object guards, CLI failures, protected state, both
interrupts, separate compiler failure streams and temporary/descendant retirement
pass. Public workflows include all security cores, Wine fixture mode, XInput and
default compatibility architecture. No Python, new kernel, guest boot, Darwin
GCC campaign or kext execution is used. See
[native generator qualification](../tests/native-generators/README.md).

The allocation stage retires 22 Python files and their obsolete object bridges.
Thirty qualified cold V builds pass on ARM, Rosetta x86 and ARM ASan/UBSan;
twenty public help builds and ten complete public workflows also pass. Each
profile preserves the full 136-case immutable C/V benchmark comparison, both
sampler fixtures, 30 controlled VM/SSH/kext workflows and twelve compiler/VM/SSH/
kext signal cases. Real serial/QMP exchanges verify byte offsets, live log
visibility, persistent command cursors and final stop after either signal.
Saved drivers preserve cwd, literal paths, UTC timestamps and success/failure
logs and exit records. Log owners preserve ordered large output and retire
all private descendants with flat descriptors. Existing source-tool and guest
regressions pass; eight static C/V AArch64/x86 target executables have the
correct ELF machine and no interpreter. The excluded preboot runner preserves
its old artifact failure. Python is not run, and no fresh kernel, guest boot,
Darwin GCC timing campaign or kext execution is claimed. See
[native allocation qualification](../tests/native-allocation-tools/README.md).

The musl stage retires the current and saved Python stagers and their obsolete
object bridge. Twelve final cold V builds qualify ARM, Rosetta x86 and ARM
ASan/UBSan recipe, cache, ABI/export, atomic publication, malformed archive,
failed retry, signal and resource cases. Both public fronts compile fresh
and publish real caches on both targets. GNU GCC rebuilds the two pinned
releases; static target tests link the staged archive and have no ELF
interpreter. A private ARM build also preserves the Android accounting patch,
its required export, retention disabled and 64 KiB load segments. Userland,
desktop and Android callers invoke native V; their cache inputs include the
native producer. Python is not run. Full userland/desktop builds, new kernels
and guest allocator execution are not claimed. See
[native musl qualification](../build-support/muslnative/README.md).

The saved campaign stage retires 45 Python programs, preserving immutable
captures, historical input pins and private-tree prerequisites. Sixty-three
final cold builds qualify ARM, Rosetta x86 and ARM ASan/UBSan workflows,
resume protection, signal/resource owners, strict serial evidence, readiness
gates, packaging admission and saved desktop profiles. Every saved bootstrap
forwards its arguments to V, with three further real public cold builds.
Real GNU preparation covers x86 v3/v4/v6 and ARM v5/v6; both static core
executables have exact original/diagnostic flag identity and the completed
core ISO is independently extracted. The full object collector checks 24 real
libc objects; the audit validates all three immutable core modes. Python is
not executed. New kernels, fresh guest allocator execution and complete
production desktop/userland rebuilds are not claimed. See
[native saved campaign qualification](../tests/native-campaign-tools/README.md).

The Android host stage retires 19 unchanged Python command and fixture files.
Thirty-six final cold builds qualify ARM, x86 and ASan/UBSan, all 45 original
runtime/boot/musl cases on each profile, seven Androidhost regressions and native
archive, manifest, metadata and compressed APK path/link controls. Public checks
exercise 20 fronts, eight argument guards, the three complete fixture suites
and three real cold bootstraps. Real GNU builds verify ARM64/x86 runtime ELF
outputs and allocation import guards; real host ASan/UBSan fixtures compare V
with frozen original C. Inline Python in ART/Bionic/ATL builders is native too.
No new Android application, VM boot or full native Alpine source build is
claimed. Eight Android API/bridge/supervisor files remain unchanged while
their other consumers are translated, including the callable bootclasspath
API. They receive no retirement credit. See
[native Android host qualification](../tests/native-android-tools/README.md).

The Android app and Roblox stage retires eight unchanged Python files.
Thirty-six cold V builds pass on ARM, x86 and ASan/UBSan, including all 20
native interactive/Roblox cases and 45 existing runtime cases per profile.
Four complete mock VM sessions per profile use real PTYs and Unix QMP sockets;
preparation, malformed input, image pixels, archive/socket descriptor ownership
and shared command regressions pass. Sixteen public compiler bootstraps cover
eight fronts and native commands, fixtures and argument guards. Runtime APIs
and desktop build preflights use V. SDK spawn headers now use their system
prototypes with the updated V compiler. Existing legacy bridges remain for
other consumers, including OpenGothic input; no fresh Android application,
Vinix guest boot or full Alpine source build is claimed. See
[native app and Roblox qualification](../tests/native-android-run/README.md).

The OpenGothic stage retires six unchanged Python files, including the last
desktop input interpreter entry and bridge. Eighteen qualified cold program/profile
builds pass on ARM, x86 and ASan/UBSan. Full controlled build/rerun/failure recipes,
all six joined download workers, Git/curl/tar, native archive and input controls,
eight complete mock PTY/QMP cases per profile and real guest-agent transfers pass.
Interrupted transfers close their remote file handles; malformed replies, failed
constructors and archives keep descriptors flat. Ten final public bootstraps pass
after retirement. Actual native generators and GNU ARM64 builds produce the X11
bridge and execinfo archive. A five-second timeout fixture allows the V mock guest
to start under load; production deadlines stay unchanged. The build caller also
changes Linguist classification from Python to Shell, accounting for another
169 classified Python bytes beyond the six retired programs. No fresh upstream
engine build, real Vinix game boot or Venus performance run is claimed. See
[native OpenGothic qualification](../tests/native-game-tools/README.md).

The runtime-tools stage retires sixteen unchanged Python files. Twenty-four
fresh program/profile builds pass on ARM, x86 and ASan/UBSan, with all eighteen
original Vulkan staging cases and seventeen whole mock guest PTY cases per
profile. Native Debian index/dependency/download/archive controls, kernel
preparation and demo extraction, benchmark and capture checks, real newc and
gzip archive extraction, Mesa/QEMU build recipes, cache damage and failed-build
publication controls, LLVM queries and SDK cwd/descriptor checks pass. Twenty-two
public compiler bootstraps pass before retirement; eight more pass afterward,
including the whole staging suite and real native Debian command extraction.
Actual native generators produce the early-client and mmap32 x86 ELF libraries.
Darwin rejects invalid UTF-8 filenames, so filesystem surrogateescape and WTF-8
serialization are tested independently of the real package archives. Upstream
Mesa/Mako and QEMU configure tooling are external prerequisites; the first-party
frontends and LLVM helper are V and do not bootstrap an interpreter environment.
No Python or Meson is executed during qualification, and no fresh upstream
engine/driver build or real Vinix guest boot is claimed. See
[native runtime qualification](../tests/native-runtime-tools/README.md).

The validation-tools stage retires six unchanged Python files and replaces their
maintained host commands and guest image installations with V. Thirty-three
fresh program/profile builds pass on ARM, x86 and ASan/UBSan. Each profile passes
all nine original Roblox launcher cases, ten whole mock CLI HTTP cases, eight
SIGINT/SIGTERM cases covering both host and guest frontend programs, the complete
67-case GPU C/V comparison, DNS query/retry/Unicode/publication controls, ZIP/PBP
validation, full-versus-legacy SDK capture bounds and repeated Xlib/descriptor
ownership checks. Actual ARM and x86 static and dynamic musl ELF builds pass warm
cache, corrupt-cache rebuild and failed-publication preservation controls. The
long cache test pins its compiler executable because other sessions can rebuild
the shared compiler. Both architectures compile the software and EGL presenters
with the actual staged SDK qualification header. Twenty-two public help/guard
bootstraps pass before retirement and nine whole command invocations afterward.
All four V PSP fetchers pass real pinned archive extraction and reread controls,
including a fresh native curl cube download. Their four original Python files
remain while the concurrently staged iOS controller still invokes those paths;
those prepared replacements receive no retirement credit in this stage. No
Python, real model client or Vinix guest is executed during qualification. See
[native validation tools](../tests/native-validation-tools/README.md).

The LinuxKPI tooling stage retires thirteen unchanged Python files and translates
the embedded Python in the host and PCI shell workflows. Thirty cold program
profiles pass on ARM, x86 and ASan/UBSan, including thirteen real child-process
VM cases per profile, actual four-case audit-generation tests, frozen original
build recipe controls, literal golden comparisons, actual atomic exchange and
unchanged C/V PCI models under GNU99/GNU11 sanitizers. Public native bootstraps
and argument guards pass, as do the actual CPU-mask and SMP prerequisite callers.
The full Kbuild audit reports 5/269 units passing on the recorded checkout. A real
ARM musl host build stops at existing PrintRecord memdup generation; the controlled
recipe tests claim no native host ELF or workload pass. No kernel source, compiler
guard or fixture assertion was weakened. No Python or Vinix guest was executed.
The concurrently edited compile-v-fixture.py remains and receives no retirement
credit. See [native LinuxKPI tools](../tests/native-linuxkpi-tools/README.md).

The iOS build-tools stage retires three unchanged Python files, totaling 10,889
bytes and 213 lines. Six cold program/profile builds and native tests pass on
ARM, x86 and ASan/UBSan. The tests cover original symbol outputs, streaming
archive validation, ordered compiler diagnostics, checksum publication, four
workers, source/header-qualified warm and corrupt caches, joined failures and
old-library preservation. A real LLVM build produces 47 ARM64 objects and
passes independent original string, mbstate and ctype ABI assertions. Public
commands also pass real warm and corrupt-object repair controls, and stage all
40 libraries in the recorded Mesa closure with matching bytes and metadata.
The original symbol header and linker stub remain byte-identical except for
the generator provenance comment. No Python or Vinix guest was executed. See
[native iOS build tools](../build-support/ios/README.md).

The GPU and random-controller stage retires seven unchanged Python files,
totaling 23,037 bytes and 586 lines. Twelve cold host/unit builds plus six final
CLI/recipe builds pass on ARM, x86 and ASan/UBSan. Each profile matches all
71,944 saved original G17 policy results and passes 25 actual child-process
cases, including QMP, PTY, large output, descendants, timeout, escalation,
integer overflow, SIGINT/SIGTERM and exact PID/descriptor retirement. Four real
static G17 executables per profile pass input and native boot-delegation
checks using a controlled downstream endpoint. Public entrypoints and actual
ARM/x86 frozen C and unchanged V host oracles also pass. The random CLI retains
normal and signalled guest exit codes, exclusive state, isolation guards and
merged compiler logs. No Python or Vinix guest was executed. See
[native render test tools](../tests/native-render-tools/README.md).

The launcher-helper stage retires four unchanged Python implementations,
totaling 18,820 bytes and 419 lines, plus the Steam build script's embedded
package and relative-link code. Fifteen final cold builds pass on ARM, x86 and
ASan/UBSan, together with 34 exact frozen-C/V VNC traces and 13 Venus probe
outcomes per profile. Native procfs/archive fixtures cover compressed and
sparse files, normalized links, fractional timestamps and DEB directory
metadata. Actual decoder processes pass large-output, failure, descendant,
closed-stdio and SIGINT/SIGTERM checks with exact PID/descriptor retirement.
Six real static ARM/x86 helper/model ELFs, default and custom guest-cache
regressions, cold public entry points and GNU tar delegation also pass. No
Python or Vinix guest was executed. See
[native launcher tools](../tests/native-launcher-tools/README.md).

The browser/control/input stage retires four unchanged Python files, totaling
26,216 bytes and 524 lines. The maintained browser, office, Steam, Activity
Monitor and pointer-scroll entry points invoke V directly. ARM, Rosetta x86
and ASan/UBSan pass current cold builds, 1,280 marker combinations checked
against frozen original profile data, 27 real controlled process cases and
100 serial-EOF/QMP races per profile with exact PID/descriptor retirement.
Nine real static guest ELF builds and native initramfs byte/mode checks pass,
along with existing QMP and archive/decoder regressions and cold public fronts.
The pointer controller retains failure logs even when final cleanup reports an
error. No Python or Vinix guest was executed. See
[native VM tools](../tests/native-vm-tools/README.md).

The Roblox Windows stage retires two unchanged Python files, totaling 12,279
bytes and 278 lines. `tests/roblox-windows/run` invokes V for the entire host
workflow. Six cold ARM, Rosetta x86 and ASan/UBSan builds pass frozen original
package/XML data, Unicode/path/cache/duplicate ZIP and pixel checks, actual
streamed curl responses, twenty concurrent uploads and unfinished-request
retirement. Each profile passes twelve PTY/FIFO process cases and three complete
controlled CLI workflows, including prepared-root refresh and an empty timeout
with exact PID/descriptor retirement. Existing native archive regressions pass.
The deployment ZIP reader supports stored/deflated archives up to 2 GiB; other
methods fail explicitly. Curl uses connection/stall limits in place of urllib
socket-read timeouts. No Python, proprietary client or Vinix guest was executed.
See [native Roblox Windows runner](../tests/roblox-windows/README.md).

The stdio stage retires its unchanged 3,995-byte, 126-line Python test.
Native V preserves all 27 standard-descriptor combinations, nested calls,
error object identity and EOF, and checks 100 failed spawns, 500 repetitions,
four concurrent workers with 100 calls each, actual SIGINT and exact PID/FD
retirement on ARM, Rosetta x86 and ASan/UBSan. Raw JSON numeric tokens retain
unsigned device/inode identities and arbitrary widths; invalid callback error
indices are rejected. Cold test/query/value/reader builds, current stress
requalification, existing streamed archive/reader regressions and the public
automatic query bootstrap pass. No Python or Vinix guest was executed. See
[native stdio tests](../tests/native-host/README.md).

The Android closure stage retires two unused bindings whose maintained callers
already use native V contexts. Twenty-four cold ARM/x86/ASanUBSan builds and
five native suites pass, including actual PTY/QMP sessions, ten interactive
cases and ten dispatcher help paths per profile. Fixture socket paths are
short and canonical; retained cold builds are hash-verified before replay.
The generic boot transport remains for unported consumers. See
[native Android runner](../tests/native-android-run/README.md).

The wallpaper stage replaces the maintained image-builder command with V.
Nine cold ARM/x86/ASanUBSan builds pass. All ten independently captured
JPEG/VWP pairs match byte for byte: 5,898,330 output bytes per profile. Native
crop/resample controls, offline and partial caches, exact indexes and source
text, malformed-cache retention, decoder retirement, streamed download cleanup
and complete warm CLI/help/guard paths pass. A real x86 libjpeg-turbo 3.2.0
SDK build is retained. Inputs are the pinned JPEG set; other Pillow image
formats are outside this command. Curl connection/stall limits replace urllib
read timeouts. See [native wallpaper tool](../desktop/tools/wallpaperhost/README.md).

The ext2 host stage retires the unchanged 6,852-byte Python generator. Three
cold host profiles and twelve direct V suite builds/runs pass all 23 unchanged
production codec, persistence, copy and ACL test functions. Embedded V fixture
templates match the original bytes, and every generated source hash agrees
across profiles. Existing-directory and argument guards and the public cold
front pass. Direct suite compilation preserves argv and avoids rebuilding a
shared cached test driver. No kernel source or test assertion changes.
See [native ext2 host tests](../tests/ext2-xattr/README.md).

No Python or Vinix guest is executed during these three qualifications.

The font closure stage retires three unchanged Python files, totaling 21,749
bytes and 574 lines. Twenty-one cold ARM/x86/ASanUBSan builds pass all 20,672
original glyph masks and headers across 16 faces in normal, subset-regenerating
and native-driver workflows. The translated atlas tests retain catalog coverage,
real source/notdef/fallback identities, line boxes, scale and terminal advances
and distinct weights. Actual PNG previews pass; labels use baked small Roboto.
Native ownership, malformed-font/SFNT, Unicode/numeric policy and variable font
coverage/names/timestamps/weight/checksum controls pass. FreeType 2.13.3 and
HarfBuzz 14.5.0 static SDKs build on ARM and x86; the public frontend also passes
a real native cold SDK build, warm hash-qualified reuse and controlled CMake
failure with old libraries preserved. Regenerated font table packing can differ
while every captured glyph mask and header remains identical. SDK libraries are
external dependencies; sanitizers instrument V. No Python or Vinix guest is
executed. See [native font tools](../desktop/tools/fonthost/README.md).

The iOS UI stage retires three unchanged Python files, totaling 17,035 bytes
and 373 lines. Twelve cold ARM/x86/ASanUBSan builds pass the retained real
UIKit and upstream 2048 Mach-O workflows, including all 27 calculator cases,
resize, keyboard, 1,000 update cycles, swipes, merges and timers. Per-profile
checks cover every truncated element prefix, Unicode, bounded nesting, 16
duplex protocol/diagnostic/error/exit/signal cases, 100 EOF/spawn retirement
cycles and 11 controlled logged-pipe/Unix-QMP desktop exchanges. Actual static
AArch64 guest init builds and native USTAR byte/mode/link checks pass. Existing
QMP/archive/reader regressions and cold public commands pass. Private owners
retain leader identity through group cleanup and sole reap; desktop cleanup
escalates after ten seconds. No Python or Vinix guest is executed. The retained
host runner remains an external input; sanitizers instrument the V controller
and fixtures. See [native iOS UI tests](../tests/native-ios-ui/README.md).

A following native image-tool closure removes the two embedded Python blocks in
`scripts/build-vinix-guest-disk.sh` and `scripts/deploy-iso.sh`. The guest image
workflow is now V, including checked payload sizing, private sparse FAT32
construction, original boot members and atomic publication without overwrite.
Release sizes retain the original unit transitions and rounding. Nine cold
ARM/x86/ASanUBSan builds pass two real FAT32 images per profile, exact member
contents, umask, output races, missing inputs/tools, SDK errors, signal cleanup
and public commands. No Python, guest boot, release build or publication is
performed. These scripts were classified as Shell, so this closure receives
zero Python-file retirement credit and leaves the recorded twelve-file count
unchanged. See [native image tools](../build-support/imagehost/README.md).

The native ext2 guest controller replaces the maintained command with V while
preserving the concurrently edited Python source and its remaining legacy
imports. Fifteen cold ARM/x86/ASanUBSan builds pass original C/prebuilt workflow
controls, real static guest ELFs and V serial objects, native USTAR, ext2 ACL
seeding and exact four-byte corruption, independent e2fsck/debugfs checks and
13 controlled PTY/QMP process cases per profile. The unchanged default V fixture
hits the existing generated-C `memdup` build failure; no allocator shim, fixture
change or compiler guard relaxation is supplied. Resource checks found a real
socket leak in the SDK failed-connect path. QMP now owns a nonblocking socket
through connection and transfers it only on success; 100 missing/refused/cancel
cycles and existing QMP cases keep descriptors flat. Public CLI checks pass.
No Python, real Vinix guest or new kernel allocation result is claimed. This
caller-preparation stage receives zero Python-file retirement credit. See
[native ext2 controller](../tests/native-ext2-run/README.md).

The native main iOS VM controller now supplies the maintained `tests/ios/run`
command and all nine original switches. Fifteen cold ARM/x86/ASanUBSan builds
pass all 512 option combinations, every missing/duplicated marker, exact
universal/ARM64e/truncated image bytes, original build plans, native PSP fetches,
copy/link/directory metadata and hard-link fallback. Each profile compiles the
unchanged static ARM64 C init and checks eight controlled full workflows, eleven
failure/output/signal/descendant cases, 100 failed-exec boots, 1,000 fast PTY
exits and existing VM regressions. Cleanup stress exposed the Darwin gap between
process-group removal and waitid exit publication; the reserved owner now waits
within its setup deadline before accepting an exited child. Large serial output
uses bounded overlapping marker scans without repeated whole-log copies. No
Python or real Vinix guest is executed; native gzip headers and archive ordering
can differ while members retain their bytes/modes/links. The independently
staged Python bridge remains intact, so this controller receives zero
Python-file retirement credit. See [native iOS VM controller](../tests/native-ios-run/README.md).

The native CPython smoke closure retires one unchanged Python file, totaling
9,112 bytes and 270 lines. It retains the original filesystem/process/thread/
socket/event/positioned-I/O/resource checks, all eleven extension imports and
100-row SQLite transaction through the CPython C API, without evaluation
strings or first-party adapters. Nine cold ARM/x86/ASanUBSan host builds pass
owned/borrowed/stolen/error/retired references, signed C results, method layout,
Unicode/NUL and callback/creation-failure ownership. Six real ARM/x86 guest
ELFs link against existing shared musl SDKs and verify their interpreter and
source/compiler/runtime/executable receipts; all 36 required exports in both
actual CPython libraries are verified as ELF data. Compiler failures preserve
existing outputs and a cold public ARM build passes. No interpreter, SDK Python
module or Vinix guest is executed, so this establishes build/ABI/model contracts
and does not claim a new runtime pass. The original aarch64 uname check remains
even in amd64 staging. See [native CPython smoke](../tests/native-python-smoke/README.md).
