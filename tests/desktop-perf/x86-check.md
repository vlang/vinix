# x86 desktop perf staging

`run-x86.v` stages the existing desktop perf workload for an x86-64 QEMU
guest. It reuses the unchanged `perfrunner.parse`/`drive`, `measure.c`,
`perf-init.sh`, result validator and QMP pointer driver. Its small V init
routes stdout/stderr to `/dev/com1`, mounts `/dev/sd0` as ext2 at `/root`
and executes the existing script. The
isolated UEFI ISO uses plain USTAR and 2048×1536 graphics, matching the
shared pointer coordinates; QEMU uses q35, TCG and USB input.

`check` admits actual x86 ELF programs, their DT_NEEDED closure, the
kernel, selected tools and source inputs without copying a root or booting.
Guest links are resolved one component at a time inside the supplied root.
`prepare` requires fresh external state, inventories the complete base
before copying, verifies the copy, retains generated init C/ELF and the
unchanged measurement C's ELF, and pins the staged root, ISO, disk, sources,
tools, desktop and kernel. Deferred QEMU/firmware commands use canonical
admitted paths. The receipt binds literal links and regular referents in
the complete root inventories. `run` requires the printed prepared.json
SHA-256, verifies inputs before and after, records the workload disk's
post-run digest, and permits only that disk to change. All scenario parsing
and result acceptance remain in the shared runner.

Build from the repository root:

```sh
v -keepc -cc clang -cflags '-Wno-error=incompatible-pointer-types' \
  -path '@vlib|tests/desktop-perf|tests/hardware-platform' \
  -o /external/run-x86 tests/desktop-perf/run-x86.v
/external/run-x86 selfcheck /external/fresh-selfcheck
```

Select `V`, `CC_AMD64`, `VINIX_PERF_READELF`, `VINIX_PERF_MKFS` and, when
needed, `VINIX_PLAIN_ISO_LIMINE` for the installed host tools. Preparation
and execution, once sufficient storage and a VM slot are available:

```sh
/external/run-x86 check REPO FULL_X86_ROOT KERNEL /external/fresh-state \
  new=DESKTOP --scenarios=ops,churn,cache,idle,apps,drag \
  --settle=3 --seconds=5 --rounds=1 --mem=3072 --timeout=2400
# Repeat the admitted command with prepare, then use its printed digest:
/external/run-x86 run /external/fresh-state PREPARED_JSON_SHA256
```

The complete runtime must include busybox, zsh, real curl and the x86 musl
loader/libraries. A minimal package fixture root is insufficient. Preparation
installs the same fixed busybox applet links as the existing ARM adapter.
The ops workload requires a timeout of at least 1800 seconds.

## Compile-only qualification, 2026-10-26

Source base `3ab8df41de7e7280944b83c60be86e8fd173c45c` plus the three
maintained paths in this change. V `0.5.2 b5bcdbb`, host Clang and the
installed x86 musl GCC compiled the controller, V init and unchanged C
measurement program. The init and measurement programs statically linked.
The maintained selfcheck passed **24 checks including 15 refusals**:
final/intermediate guest symlinks, escapes and cycles; input, referent,
literal link and staged-tree mutations; restoration, streaming digest,
geometry, invalid option controls and host-tool symlink retargeting.
Independent review covered init lifetime, canonical deferred tool paths
and the component-wise guest resolver. No blocking finding remained.

Actual cached inputs passed ELF/dependency closure admission:

- Full base: `/Users/alex/code/vinix/build-release/work/amd64-desktop/initramfs-root`.
- Kernel: `audio-peer-login-20261026/kernel-evidence/kernel-x86_64/bin/vinix`,
  SHA-256 `8ec2d8c93bb1e1f44e71d66314de9408c7b4965f58baf56e1465e385fda1a325`.
  Its preserved `kernel-evidence/kernel-seal.json` has SHA-256
  `839ad75dd1ec376a8cae4e75dc1cfbddc913406dc3e136e8d4f4a412657f9b73`.
- Desktop: `package-release-routing-native-20261026/desktop-x86_64/vinix-desktop`,
  SHA-256 `259613b8f95ddde359a70f338baeca27bd96f0ae2b56391f6d6c3cc35de67a83`.
  This is the retained six-source compositor before hosted Launch options;
  it does not qualify subsequent production changes.

Relative artifact paths above are under
`/Users/alex/Library/Caches/vinix-codex/section14/`. The compile-only bundle
retains source copies, generated controller/init C, executables, literal
commands, final checks and earlier failed attempts:
`package-perf-x86-20261026-compile-only.tar.gz`, SHA-256
`582acd2457efa7531fa2e4181c70e4346d3e9b026f036c137aba12a292829da2`.
Its complete inventory is `package-perf-x86-20261026/compile-only/bundle.sha256`,
SHA-256 `2bcff4ffc51f1e3e2e95dcd509bf964dd5820adee118f7f5cc9654c0c83a62b2`.
Source links in this capture are materialized; compiler/runtime/firmware
installations remain external, admitted by their observed identities.

Large preparation and guest execution were held for storage coordination.
All six native scenarios remain pending. This report makes no native
kernel memory or current-main compositor qualification claim.

## Routing input retention, 2026-10-26

`retain-routing-inputs.v`, based on `d542212d8e0d4d2ab3b9d098e02c554ddf5b98a5`,
preserves the desktop and bundle executable as ordinary byte-identical files.
It requires the pinned complete original inventory and its unique selected-file
rows, checks source/copy hashes and modes before and after, retains the complete
inventory and producer source/executable, and records provenance. Existing output
is refused. Build and invocation:

```sh
v -prod -keepc -cc clang -o /external/retain-routing-inputs \
  tests/desktop-perf/retain-routing-inputs.v
/external/retain-routing-inputs ORIGINAL_ROUTING_ROOT /external/fresh-retained-inputs
```

The production build, copy, existing-output refusal and actual retained-desktop
ELF/dependency admission passed. Preserved inputs are under
`integration-20261026/routing-retained-inputs/`, relative to the section14 state
directory above. Future preparation selects
`new=/Users/alex/Library/Caches/vinix-codex/section14/integration-20261026/routing-retained-inputs/desktop-x86_64/vinix-desktop`.
The desktop retains SHA-256 `259613b8f95ddde359a70f338baeca27bd96f0ae2b56391f6d6c3cc35de67a83`;
`tools/software-release-routing-bundle` retains
`0bf024564aba9cedfac1fd8f92b3f117e5735511cafb1dfb409f449ca00ca94b`.

The retained bundle contains generated producer C, literal commands, build logs,
refusal/admission results and `provenance.json`, SHA-256
`c05e4397ba47102f9cb90ea3315c08e7644a67559c142235455b8dceeb3eef33`.
Archive `integration-20261026/routing-retained-inputs.tar.gz` has SHA-256
`21451fafaf5edd56ac5bb3574bfb0b6b49d4acfb4dfaecebdc69afdd0cfb61c5`;
its complete `bundle.sha256` inventory has SHA-256
`37fd94d6e4a2b96dc126784c47d8fe3ce60bf4d88fdfbd0d43f3db2f7a678878`.
The copy helper verifies selected expanded bytes; archive-stream verification is
separate. Historical native auditors still require the original complete bundle.
The original expanded bundle was untouched. No staging or guest run occurred.

## Interrupted first native attempt and serial correction

Based on `fe1e6fd495d2b3c998f1be2069c37a1ea1f6474b`, the first native
preparation passed full base/copy/source/tool checks and produced receipt
`69ccf163367ce9f2c690a76358e2bbddbf347726a898a690872ca86927022e6f`.
The guest reached initramfs unpack completion but emitted no PERF result or
completion marker. The controller was interrupted and exited 1; this attempt
does not qualify any scenario. The original init inherited x86 framebuffer
console descriptors. The correction opens `/dev/com1`, checks both `dup2`
calls and closes the extra descriptor before mounting and executing the
unchanged supervisor. No unobserved workload execution is assumed.

Independent review found no descriptor lifetime issue. V generated the
corrected init C and musl GCC linked it successfully; ELF inspection confirmed
static x86-64 execution with no interpreter or dynamic dependencies. Generated
C and ELF are retained in `package-perf-x86-20261026/tools/x86-init-serial{.c,}`
with SHA-256 `1563b4aaa20a28de3035abf797a1d13359acdf36cbf7fcfb26222a4aea93def2`
and `c21fe77339d2605b20f090f0f373966c527c5865eb238a3d210fabed6bb4d639`.

The maintained `archive-x86-failure.v` is deliberately limited to this exact
interrupted attempt, receipt and reviewed sealer/independent reader bytes.
It preserves the canceled logs, actual controller and tool/source copies,
then seals the complete tree. It checks the expanded inventory before and
after independent streamed archive verification. A separate reviewed reclaim
requires the exact eligibility digest, repeats all three checks, rehashes
external pins and confirms the canonical directory device/inode before
removing only the expanded failed attempt. V's remover does not recurse
through symlinks. This assumes a trusted, quiescent host tree.

Production helper compilation and the wrong-eligibility refusal passed.
The archive reader checked **3,168 entries: 2,622 regular payloads and 546
literal symlinks**, plus gzip integrity. Both preservation and reclaim passed;
archive, original manifest, tools and receipts remain outside the removed tree:

- `package-perf-x86-20261026/attempt01.tar.gz`, SHA-256
  `994aefc99ea00d56317bbd309c0d500db8a6bba71790428f48336ee5616b438f`.
- `attempt01-preservation/original-manifest.sha256`, SHA-256
  `ef4ed6f2ef8a0d9d47794dc9e2abb6f235e5042747da9622ae2286a76d76f7a9`.
- `attempt01-preservation/eligible.json`, SHA-256
  `e90e7af8d428e64c383533fb334bcdcb329ebcbb870d3ad85fb4a5e1e59dd9e4`.
- `attempt01-preservation/completed.json`, SHA-256
  `eb85b3e8193fb319eab09a12372a26335a433bbcebfb749544f927138a715e6a`.

Paths after the first bullet are relative to `package-perf-x86-20261026/`.
Command argv, outputs and exact exits are retained beside the receipts.
The one external executable symlink referent remains pinned outside the
removed tree and has an ordinary copy inside the archive. The other host
absolute link targets an empty directory inside the archived tree; actual
bootloader bytes are regular archived files. Guest-root links retain their
complete runtime payload. Directory metadata is outside the historical
manifest's authentication scope. Corrected native execution remains pending
storage coordination; the shared validator and workloads are unchanged.

## Optional APFS staging

On macOS, `VINIX_PERF_X86_APFS_CLONE=1` selects exclusive `clonefile`
staging for runtime files, the selected desktop and ISO inputs. Each ordinary
file has its own inode; writes in either direction remain private. Guest links
are copied literally and permission modes are preserved. An existing target,
unsupported entry, unsupported filesystem or failed system call refuses
preparation without a copy fallback. Other hosts and the default mode retain
the existing copy behavior. The prepared receipt records the selected mode;
the full source, runtime, staged-file and execution input checks are unchanged.

The separate `run-x86 clonecheck FRESH_STATE` command checks independent
inodes, private writes in both directions, complete inventory equality,
literal absolute/relative/dangling/intermediate guest links, exclusive targets
and failure propagation. Source containment is checked before creating output,
including destination parents reached through a host symlink and missing
intermediate directories. Native qualification remains pending; the first
interrupted attempt is preserved above.

On source base `7d684ac914b7e3f76ce9c7218dc65daa7e632876`, the normal host
build, original 24 checks (15 refusals), and all 18 clone controls passed.
Independent source review found the parent-alias containment issue; the final
controls require its exact refusal and unchanged source inventory/output.
Generated controller C, executable, source, literal command/exit receipts,
compiler versions and logs are retained in `package-perf-x86-20261026/apfs-host-02/`.
Before each build/control invocation, actual available storage exceeded
500 MiB. Both host attempts, archives and sidecars use less than 10 MiB.

Complete archive `package-perf-x86-20261026/apfs-host-02-final.tar.gz` has
SHA-256 `a6dad6d45f25b1f2d6de274f414fde8fbbda41454fcd77a83541d5c05c10448c`.
Its original complete inventory has SHA-256
`467e6ef5edd32bf7c3e000613a49ff514c08682288478eca8b80561aa509b8a1`.
The original sealer checks passed; the independent strict reader checked
41 sealed entries (24 regular payloads, 17 literal links) and gzip integrity.
The earlier host01 source/controls, host02 fixture syntax refusal and archives
refused for macOS metadata headers are preserved. The final archive uses
`COPYFILE_DISABLE=1`; the original inventory remained byte-identical. This
host qualification observes the installed compiler versions and generated
output, without claiming toolchain reproducibility or a native scenario pass.

The first attempt's uncompressed initramfs and ISO occupy 211,771,392 and
247,715,840 bytes. Together they require about 438.2 MiB of new storage even
with cloning. The runtime and ISO staging copies can share extents while
remaining complete ordinary files. The ext2 disk has a 256 MiB logical upper
bound; the unchanged cache workload writes 32 MiB. A conservative proposed
retry allowance is 736 MiB, including the full ext2 bound and about 42 MiB for
generated source, executables, logs and filesystem metadata. This is a planning
allowance, not measured clone-mode usage. Shared storage admission uses actual
`df -k` readings and the coordinator's reserve; `os.disk_usage` is unsuitable
on this host. No original input is hardlinked or modified.
