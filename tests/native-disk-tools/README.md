# Native disk controllers

The disk no-sync, mapped writeback, journal, mounted-disk policy and reboot
commands use `diskhost` and the shared native `guesthost` process owner. The
shell entrypoints only launch V. No command loads a Python controller or query.

```sh
V=/path/to/v tests/disk-no-sync/run.sh --kernel-dir /path/to/arm/kernel
V=/path/to/v tests/mapped-writeback/run --arch aarch64
V=/path/to/v tests/fs-journal/run --arch amd64 --production --cases full
V=/path/to/v tests/mounted-disk-policy/run --arch amd64
V=/path/to/v tests/reboot-persistence/run.sh --arch x86_64
```

Build the requested kernel first. Every command validates its architecture and
copies its bytes into a private snapshot; these controllers never rebuild the
kernel. `--kernel-dir` overrides `VINIX_KERNEL_DIR` on ARM or
`VINIX_AMD64_KERNEL` on AMD. `VINIX_VM_RUNNER_ROOT` selects boot assets.
`VINIX_AARCH64_SYSROOT`, `CC` and `CC_AMD64` select the native musl tools.
QEMU, firmware, Limine, xorriso, tar and e2fsprogs must already be available.

`--state-dir` retains inputs, disks, serial captures and launch receipts.
Mounted-disk policy requires a fresh state directory. Without it, the fixture
commands use disposable directories. The supplied-init no-sync and reboot
interfaces still require a state directory; their `run.sh` commands use V to
build the maintained guest fixtures. `--build-only` prepares inputs without booting.
`VINIX_QEMU_TIMEOUT` keeps the original 240-second no-sync/reboot and
300-second other defaults; `--timeout` overrides no-sync and reboot.

The no-sync steps retain their order and one physical volume. Mapped ARM
steps retain their seeded volume; AMD steps independently seed a bootable
root with the exact archive identity. The original memory bounds, 1,200
seed files, payload sizes, byte patterns and optional pressure step remain.
Mounted policy uses a 64 MiB root, 16 MiB spare and the original partition
geometry, 2 GiB ARM/1 GiB AMD memory and complete writeback check. Its ARM boot
ISO uses a SCSI CD transport so `/dev/vda` and `/dev/vdb` retain their fixture
roles. AMD uses the last AHCI port. The missing old `mapped.amd64_boot` call
is replaced by the directly owned native power-cut supervisor.

No-sync, mapped, journal and mounted tests stop QEMU with SIGKILL before
inspection. A completion number must include its entire newline. Journal
cuts accept the numbered stage marker; recovery requires `ino=0`. Serial
printing follows each original runner's streaming policy. Scoped process
groups, PTYs, descriptors and signal handlers retire on success and failure.
Reboot instead keeps one QEMU process through the guest reset, requires both
START/SYNCING brackets, and retains its monitor/TERM/KILL cleanup sequence.

`diskhost.journal_fixture` serializes only new disposable images with the
original CRC32C configuration and VJFS signature. `diskhost.export_clean`
reads a recovered volume and creates a separate sparse EXT2 inspection copy.
It rejects a live commit marker and path, symlink or hard-link aliases of the
source. Signature restoration touches only that copy, including sparse-super
backups. The live image is never converted for inspection.

Qualification on 2026-10-11 passed ARM, Rosetta x86 and ASan/UBSan host checks,
18 cold command/checker builds, 33 strict guest SDK preparations and all seven
cold public fronts from `/tmp`. The mounted transport correction additionally
passed three cold builds and six guest SDK preparations. Host checks cover
the configuration layout and independent table CRC, actual e2fsprogs fixtures,
read-only and alias guards, a sparse 4 GiB export, final-byte payload corruption,
fragmented large inode numbers, descendant retirement and SIGINT. An explicitly
selected host model checks all 17 journal epochs, five rename stages and
recovery inspections; it does not boot a kernel.

Real QEMU checks passed reboot and mounted policy on both architectures,
including clean EXT2 checks and complete mounted payloads. Production journal
full/restart/inspection and blank 4 GiB formatter scenarios passed on both
architectures. Mapped sync, syncfs and background checks passed on both;
private and pageout passed on ARM. No-sync passed its first six steps but
rejected the still-allocated exit inode. Mapped churn rejected the original
retention bounds on both architectures, and the additional AMD private run
failed its unchanged guest assertion. These failures were retained. Frozen
kernels without `journalcut` reject qualification ioctls, so actual injected
journal cuts were not requalified in this controller stage.

Receipts, original source hashes, SDK ELFs and captures are under
`~/.cache/vinix-python-zero-process-20261011/disk-*`; retained guest state is
under `/tmp/vx-disk-*`. The ordinary ARM kernel SHA256 is
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`.
Final AMD storage checks use the copied prebuilt kernel
`f408720b8918d7de51295d6b101e5b070cfa4257bc85b833b80ef4e0dcfe8268`;
the older `38fb88ad76e81bb26f9d84267678cf98cd0ccc0aae10573b9b83ddd5ca0b3f0a`
failure controls remain recorded. Reproducible private SDK ISO/kernel copies
were retired after hashing; source, archives, ELFs, disks and logs remain.
Sanitizers cover the host only, with leak sanitizer disabled. No Python was
run, kernel rebuilt or guest assertion/deadline weakened.
