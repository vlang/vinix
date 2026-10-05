# Immutable kernel-loaded ELF text

`tests/elf-text/run-host.sh` executes the actual production dynamic-table scan
and final-mapping filter with host fixtures. It checks legacy DT_TEXTREL,
DT_FLAGS/DF_TEXTREL without the legacy tag, ordinary tables, early DT_NULL,
malformed/oversized tables, bounds, writable segment overlap, holes and full
range containment. Resource I/O and the range index/lock are test fixtures;
the scanner and freeze functions are extracted unchanged from kernel source.

`tests/elf-text/run.py --arch x86_64 --kernel-dir /path/to/kernel` boots the
actual loader. Its static guest writes three real ELF files with synthetic
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
