# x86 desktop perf staging

`run-x86.v` stages the existing desktop perf workload for an x86-64 QEMU
guest. It reuses the unchanged `perfrunner.parse`/`drive`, `measure.c`,
`perf-init.sh`, result validator and QMP pointer driver. Its small V init
mounts `/dev/sd0` as ext2 at `/root` and executes the existing script. The
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
