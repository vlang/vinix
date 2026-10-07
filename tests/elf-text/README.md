# Immutable kernel-loaded ELF text

`tests/elf-text/run-host.sh` executes the actual production dynamic-table scan
and final-mapping filter with host fixtures. It checks legacy DT_TEXTREL,
DT_FLAGS/DF_TEXTREL without the legacy tag, ordinary tables, early DT_NULL,
malformed/oversized tables, bounds, writable segment overlap, holes and full
range containment. Resource I/O and the range index/lock are test fixtures;
the scanner and freeze functions are extracted unchanged from kernel source.

`tests/elf-text/run.py --arch x86_64 --kernel-dir /path/to/kernel` boots the
actual loader. Its static V guest writes three real ELF files with synthetic
PT_DYNAMIC records and executes them. Ordinary text rejects mprotect even
when the requested protection is unchanged; both textrel encodings allow it.
A real dynamically linked musl PIE verifies that both its own executable
text and the kernel-loaded interpreter's executable text are immutable.

Run the same command with `--arch aarch64` for ARM. Use
`VINIX_VM_RUNNER_ROOT` for the checkout containing installed VM dependencies,
`VINIX_AARCH64_SYSROOT` for the ARM build sysroot, and
`VINIX_AARCH64_LOADER` for its matching dynamic musl loader if they are outside
the default userland build directories. Set `USE_TCG=1` for ARM emulation.
The runner builds a private initramfs and disk, and uses strict SMAP/PAN.

The maintained fixture is `textfixture/core.v`, compiled with no GC through
the shared native-fixture builder. The declaration header checks native ELF,
process and transfer widths and supplies the original 16 KiB target alignment.
Both the function call and protection check use the actual exported wrapper.
The four volatile dynamic-table words remain initialized, file-backed storage;
copy buffers and ELF records remain synchronous stack values. Children are
reaped with the original `waitpid` and status checks. All 26 original guards,
errno checks, workloads, verdicts and the 240-second deadline are retained.

The 2026-10-07 port passed strict original-C/V static and real dynamic PIE
links with ARM LLVM and genuine x86 musl GCC, then both unchanged guest verdicts
for C and V on each architecture. The guest binaries, generated V objects and
serial objects matched their SDK artifacts byte for byte. The production
dynamic-table and immutable-range host tests also passed. The generated V
fixture objects import no implicit allocators. This fixture-only stage reused
the separately qualified ARM and x86 default kernels with unchanged kernel
source; it makes no fresh kernel build or sanitizer claim.

The original 116-line fixture is retained in Git at
`c411ab6a2ef22933e613924d76f1b4693c8b2006:tests/elf-text/guest.c`
(SHA256 `d00050b540a81f46611e4e9ad951a16b7fb49f5cb115a3fa37056dd861cfe3f6`).
Use `--source /path/to/frozen/guest.c` for an explicit original-C control;
the default builds V. Local source, ABI, disassembly, SDK and native receipts
are under
`~/.cache/vinix-c-to-v/firstparty-only-20261006-011023/elf-text-fixture/`,
including `final-validation.json` and the four guest logs. The x86 ISO's
extracted kernel and archive contents were verified, including the normal
builder-added image identity. ARM's launcher removed its private boot disks;
the selected kernel hashes and copy/boot logs are retained, with no claim of
post-run extraction from those disks.
