# Publisher key creation and recovery

`keygen` preserves its public key/seed format while creating the seed in a
captured, owned parent with no group/other write access. It uses a private
exclusive no-follow temporary, retries short/interrupted writes and interrupted
file/directory flushes, checks file metadata and parent identity, and publishes
only with an exclusive atomic rename. A raced destination is never overwritten.
Normal failures remove only a still-matching unpublished temporary. Once the
name has been published, failures retain it and explicitly report **signing seed
saved**. No public key is returned as a successful result before the directory
flush and final identity checks.

`key-public SEED_FILE` derives the existing public key using the publisher's
captured, private, bounded seed reader. It changes no seed, configuration, trust
or installed state. Existing ownership, permissions, no-follow, single-link,
length and encoding checks apply. The CLI rejects missing operands. Public-key
recovery does not authenticate a publisher or enroll a key.

The [public probe](keygen-check.v) bounds each call with a three-second alarm.
Its baseline reproduces four unsafe creations: NUL-suffixed paths, aliased
parents with/without redundant separators and a shared-writable parent. Six
existing-leaf forms already refuse: ordinary files, aliases, dangling links,
FIFOs, directories and hard links. The new implementation refuses all ten,
preserves existing outside data/mode, leaves no new seed/temporary on refusal,
and permits an ordinary private retry. The maintained distribution driver and
both Linux runtime guests require this probe.

The [core runner](../../tools/packages/pkgcore/keygen_test.v) injects partial and
interrupted writes, interrupted/error flushes, checkpoint errors, temporary
replacement/type/size/mode changes, parent substitution, and a raced destination.
It checks cleanup, preserved replacement names, saved-seed recovery, unchanged
private key format and repeated success/refusal under a 32-descriptor limit.
The CLI lifecycle checks existing-seed refusal, unchanged public-key recovery,
public-file refusal/restoration and actual signed publishing/install workflows.
Fault hooks are private module functions, with no CLI/environment production
switch. Test-only environment values select injected actions.

The [ext2 controller](persistence-check.md) has a separate `--keygen` scenario.
It kills QEMU after the real CLI returns its public key, before any extra guest
sync, then boots the same disk. Recovery checks the private seed and preserved
bytes, refuses an existing-seed overwrite and derives the same public key. The
host compares both serial keys before writing its six-artifact receipt. This
qualifies the completed seed-publication boundary, with no host repair; it does
not cut within an individual write, rename or flush.

Host controls exercise the controller's actual comparison code against matching
CRLF/plain logs, different keys, missing markers and non-hex text. They also
check that its default list retains the three transaction checkpoints while
`--keygen` selects only the publisher scenario.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/keygen-core tools/packages/pkgcore/keygen_test.v
/tmp/keygen-core
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/keygen-probe tests/packages/keygen-check.v
/tmp/keygen-probe /tmp/new-keygen-work
```

Callers must control ancestors and concurrent writers. This does not freeze
arbitrary same-user in-place edits, guarantee cleanup after storage failure or
abrupt termination, or qualify physical-device write-cache loss. An unpublished
private temporary may remain after an abrupt stop; it is never silently promoted
on retry. A parent-directory flush failure requires inspection of the saved seed
before recovery/retry. Wider crash windows, public publisher enrollment, catalog
migration and graphical/runtime release qualification remain separate gates.

## Recorded results, 2026-10-14

All 47 package core runners passed in four independent shards. Key generation,
release, signing seed admission and durability passed clang ASan/UBSan (leak
detection disabled, undefined behavior fatal). The signed CLI lifecycle, private
seed/durability probes and maintained real TLS/Range suite passed. The host
ledger records 114 successful compile/run results. The baseline reproduces four
unsafe creations; the final probe refuses all ten cases and permits a private
ordinary retry. CLI public-key recovery preserves the exact existing seed.

Both fresh Linux runtime guests passed the full signed workflows and clean
shutdown: AArch64 reported 293.4 seconds; x86_64 reported 430.9 seconds. AArch64 used a
300-second deadline; x86_64 used a 600-second diagnostic deadline. Each receipt pins sixteen artifacts/logs, including the
key-creation probe.
Initial Linux runs refused older fixtures that created their seeds directly in
shared /tmp. Those and related guest fixtures now use an owned private parent.
The initial ext2 builds were interrupted for that fixture migration; failed and
interrupted controller logs remain pinned. Final guest builds use the migrated
sources. Two subsequent x86_64 runs exhausted the 300-second budget during
shared-host qualification. The same fifteen boot artifacts completed with a
600-second diagnostic deadline. The original 300-second x86_64 budget remains
unqualified; failed logs and unchanged artifact hashes are retained and audited.

Both dedicated ext2 SIGKILL/reboot scenarios passed within their unchanged
240-second deadlines. After successful CLI keygen, the guest performs no extra
sync or metadata write before the cut. The controller compares the first
public key with the recovered key from the same disk, without host repair.
Each receipt pins six artifacts/logs; the exact initial images are retained
privately and rehashed during audit. QMP records two boots and a final guest
shutdown per architecture. Cuts during individual writes/renames/flushes and
physical write-cache loss remain outside this qualification.

Evidence:

- [before](results/2026-10-14/keygen-before.txt)
- [after](results/2026-10-14/keygen-after.txt)
- [host](results/2026-10-14/keygen-host.txt)
- [host results](results/2026-10-14/keygen-host.json)
- [CLI](results/2026-10-14/keygen-cli.txt)
- [TLS](results/2026-10-14/keygen-https.txt)
- [sanitizers](results/2026-10-14/keygen-asan.txt)
- [Linux AArch64 receipt](results/2026-10-14/keygen-linux-aarch64.json)
- [Linux AArch64 serial](results/2026-10-14/keygen-linux-aarch64.serial.txt)
- [Linux AArch64 QMP](results/2026-10-14/keygen-linux-aarch64.qmp.txt)
- [Linux x86_64 receipt](results/2026-10-14/keygen-linux-x86_64.json)
- [Linux x86_64 serial](results/2026-10-14/keygen-linux-x86_64.serial.txt)
- [Linux x86_64 QMP](results/2026-10-14/keygen-linux-x86_64.qmp.txt)
- [ext2 AArch64 receipt](results/2026-10-14/keygen-persistence-aarch64.json)
- [ext2 AArch64 serial](results/2026-10-14/keygen-persistence-aarch64.serial.txt)
- [ext2 AArch64 QMP](results/2026-10-14/keygen-persistence-aarch64.qmp.txt)
- [ext2 x86_64 receipt](results/2026-10-14/keygen-persistence-x86_64.json)
- [ext2 x86_64 serial](results/2026-10-14/keygen-persistence-x86_64.serial.txt)
- [ext2 x86_64 QMP](results/2026-10-14/keygen-persistence-x86_64.qmp.txt)
- [controller comparison/selection controls](results/2026-10-14/keygen-persistence-control.txt)
- [compiler/source/artifact ledger](results/2026-10-14/keygen-toolchain.json)
