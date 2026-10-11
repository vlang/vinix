# Native emulator test preparation

The six `tests/{n64,ps1,ps2}/{run,desktop}` commands compile and invoke V
directly. `emulatorhost` owns their CLI, rootfs staging, strict guest compiler
commands, archive creation, native ARM launch and temporary directories.

Guest roots retain the original staging tree and its file/directory metadata,
literal symlink targets, optional game and BIOS locations. PS1 recursively
copies CUE/M3U dependencies with physical-path cycle/deduplication guards,
strict UTF-8 and directory containment. N64 retains the full halfword/word
swaps and original IPL instruction-budget mutation.

Desktop roots retain the original compositor, staged `usr` tree and
`tests/ios/desktop-init.c` recipe. The native ARM launch supplies a separate
init overlay, private 64 MiB ext2 home, EFI variables and 2048×1536 firmware
and Limine resolution. It owns QEMU directly; rootfs and package servers are
unnecessary for these isolated roots. No Python import adapter remains.

The earlier borrowed-object preparation policy is historical. Its Python
object lifetime/exception transport is retired with its callers. These native
commands accept CLI paths and values; they do not expose arbitrary Python
objects or callback rebinding. Runtime diagnostics can differ while parser
errors, unsuccessful runs and interrupts return 2, 1 and 130 respectively.

See [qualification and current limits](controllers.md).
