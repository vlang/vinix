`recover_g17_abi` and `recover_t6050_power` compile and invoke the complete native
V recovery stack. They retain the original path defaults, long-option
abbreviations, duplicate-option handling, read order and report schemas.
G17 reads all six inputs before its first proof. T6050 discovers exactly one
regular Preboot DeviceTree at the original fixed depth and completes every
topology/controller proof before creating the output directory or file.
Structural reader errors exit 1; validation, source-file and argument errors
exit 2. Native diagnostics replace interpreter tracebacks. Report-write errors
exit 1, and a successful T6050 command prints exactly the bytes it writes.

Both commands consume local images synchronously. Parsed DeviceTree properties
and returned proof metadata own their buffers; readers do not escape into a
report. Host V uses Boehm GC. These tools do not change kernel or firmware
behavior, and qualification establishes no new physical GPU capability.

`recovery_test.v` checks CLI defaults and exact/prefix options, fixed-depth
source discovery and symlinks, DER type/exact-consumption errors, input
ownership, missing-file priority and absence of report publication on failure.
Set `VINIX_RECOVER_G17_TOOL` and `VINIX_RECOVER_T6050_TOOL` to prebuilt commands
to include subprocess checks. The existing native module fixtures retain the
independent recovery tests and complete frozen expected outputs.

The complete command port passed all 28 affected native test files on ARM64,
Rosetta x86-64 and ASan/UBSan. Both full reports matched the saved independent
real-image reports in each profile. Fresh native commands also passed help,
generator and temporary-directory checks; the trace workflow passed its four
frozen-C JSON comparisons, allocation rollback and Mach/dyld sanitizer probe.
No Python was run for these checks and no Apple image was added to Git.
