# Fixed publisher profile ELF admission

Native, SQLite and FFmpeg catalog profiles inspect the captured ELF bytes before
import and inspect the copied, content-addressed objects again before publishing
a lock. Admission now requires the supported ELF64 header/program entry sizes,
bounded program tables and nonempty segment file ranges within the file.
Load segments must have memory sizes at least as large as their file contents,
no address overflow, and valid power-of-two alignment with congruent file and
virtual addresses. Zero/one alignment and memory-only zero-fill segments remain
legal. Each image needs a file-backed load segment; static/PIE entry points must
be nonzero and lie in file-backed executable load segments. Shared objects may
have no entry point.

PIE images need exactly one interpreter: an absolute path, with one terminating
NUL and no embedded NUL, occupying 2–4096 bytes including the terminator.
Static images and shared libraries cannot declare an interpreter. Unsupported
profile architectures and image kinds fail explicitly. These checks establish
structural consistency; publishers still authenticate their source, inspect
dynamic dependencies and qualify instructions, library ABI and application
behavior before signing. The generic package format and importer are unchanged.

Previously only target/type, table bounds and the presence of a `PT_INTERP`
marker were checked. Files without loadable code, truncated load contents,
entries outside executable segments, invalid load alignment and empty or invalid
interpreter paths could enter a fixed profile's lock. The CLI reproduction uses
synthetic structural fixtures that are never executed. Its normal mode requires
refusal with an ELF diagnostic, no published lock or leftover staging directory,
and byte-identical canonical locks after restoring the source and retrying at
each refused destination. `--before` is for reproducing the earlier admission
behavior with a retained old CLI.

Run with a reviewed V compiler and CLI:

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/elf-core tools/packages/pkgcore/elf_profile_test.v
/tmp/elf-core
v -nocache -gc none -manualfree -path '@vlib|@vmodules|.' \
  -o /tmp/elf-cli tests/packages/elf-profile-check.v
/tmp/elf-cli /path/to/vinix-package /tmp/new-elf-qualification
```

The maintained distribution driver discovers the ELF assertion runner and runs
the CLI reproduction. The core assertions cover both architectures and all
three image kinds, malformed/overflowing headers and segments, entry boundaries,
memory-only segments, alignment and interpreter bounds. Native/SQLite/FFmpeg
profile tests replace valid sources after preflight and require the copied-object
checks to refuse them and clean staging. Native and SQLite also restore exact
input bytes and require the original lock on retry. FFmpeg's synthetic source
archive remains deliberately unpinned, so its damaged executable must fail before
source-archive admission; real FFmpeg source pins are checked separately.

## Recorded results, 2026-10-14

All nine focused core runners passed: ELF, native, SQLite, FFmpeg, inventory,
catalog, composition, import and release. The ELF and three profile runners also
passed clang ASan/UBSan with leak detection disabled and undefined behavior fatal.
The signed CLI lifecycle and updated distribution driver compilation passed.

The maintained CLI reproduction admits all 20 malformed cases with the retained
before-change CLI. The final CLI refuses all 20 across both architectures and
reproduces the baseline lock after every restored retry. Both valid structural
profile fixtures remain accepted. Real Native, SQLite and FFmpeg profile locks
match the previously recorded catalog bytes exactly, covering six native apps,
SQLite's separate runtime and FFmpeg/FFprobe's pinned-source runtime.

Production staging cross-compiled the package CLI, account session and Linux
runner for AArch64 and x86_64; all six binary headers match their target. The
receipts retain hashes for every staged artifact. This publisher admission change
does not rerun guest application behavior; earlier
[native](native-catalog-check.md) and [composed Linux](profile-inventory-check.md)
guest qualifications remain separate evidence. Public publisher enrollment,
broader catalog migration and graphical/runtime acceptance remain open.

Evidence: [before](results/2026-10-14/elf-profile-before.txt),
[after and restored retries](results/2026-10-14/elf-profile-after.txt),
[host checks](results/2026-10-14/elf-profile-host.txt),
[individual results](results/2026-10-14/elf-profile-results.json),
[signed CLI lifecycle](results/2026-10-14/elf-profile-cli.txt),
[sanitizers](results/2026-10-14/elf-profile-asan.txt),
[target artifact receipts](results/2026-10-14/elf-profile-cross.json) and
[source/toolchain ledger](results/2026-10-14/elf-profile-toolchain.json).
