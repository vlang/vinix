# Native guest image and size tools

`scripts/build-vinix-guest-disk.sh [OUTPUT [INITRAMFS]]` builds a raw FAT32
AArch64 UEFI image. V checks the input files and mtools, computes the original
payload-plus-128-MiB ceiling, creates a sparse private output and installs the
unchanged firmware, Limine configuration, kernel and initramfs. Publication
uses a same-filesystem hardlink, refusing an output created by another owner
during the build. The caller's umask is restored before any SDK tool starts;
the resulting image retains the ordinary shell-created file mode. Temporary
configuration and partial images retire on errors and signals.

`build-support/human-size BYTES` formats release sizes using bytes/KiB/MiB/GiB
and the original binary unit transitions and decimal precision. SDK `snprintf`
preserves ties-to-even formatting. This CLI accepts finite nonnegative sizes.
`scripts/deploy-iso.sh` invokes it without requiring a host Python interpreter.

These ports remove two embedded Python blocks. They receive no Python-file
retirement credit because the original files are classified as Shell.

Qualification builds the disk tool, formatter and independent process/image
fixture cold on ARM, x86 and ASan/UBSan. Each profile formats two real FAT32
images, reads every boot member through mtools and checks exact input bytes,
image size, restrictive umask, existing/missing inputs, publication races,
SDK failures, interrupts, descriptor and private-process retirement. Boundary
and decimal-rounding fixtures retain the original recipe constants. Shell
frontends receive syntax and public command checks. No Python, guest boot,
release build or publication is performed. Mtools remains an external SDK.

```sh
v -cc clang -o /tmp/qualify-image-tools tests/native-image-tools/qualify.v
/tmp/qualify-image-tools /path/to/v /new/evidence/arm arm
/tmp/qualify-image-tools /path/to/v /new/evidence/x86 x86
/tmp/qualify-image-tools /path/to/v /new/evidence/san san
```
