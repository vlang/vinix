# Native Apple boot tools

The image builder and packer, IORegistry exporter, converter and structure ABI
checks, QEMU iBoot runner and host fixture checks are maintained in `boottools`.
Their shell entry points compile V through the repository's compiler discovery
and native tool launcher. All nine former Python files and the iBoot CPython
object bridge are retired. Original Git blobs and SHA-256 hashes are recorded
in [the translation receipt](native-translation.json).

The packer preserves the 80-byte `VNXAPPL1` header, little-endian fields,
16 KiB alignment, zero padding, UTF-8 command line and trailing NUL. IORegistry
property order, filtering, padding, nested memory windows and the two QEMU
property substitutions are preserved. Register comparisons retain XNU's
address-prefix checks, unsupported-node skips and Apple translation stopping
at a bus without ranges. The typed binary readers add malformed-input bounds;
packed images are limited to the host array's 2 GiB range and ADT depth to 256.
This is a native CLI and typed API replacement, not an arbitrary Python-object
API. Empty path options retain their current-directory meaning.

Compiler flags, loader/reporter/stub recipes, ustar layout, emulator arguments,
memory addresses and dump checks are retained. The QEMU marker timeout defaults
to 300 seconds, with one-second polling and short interrupt checkpoints. QMP
operations have the original 60-second bound, and quit waits up to 30 seconds.
The runner inherits emulator output streams so verbose output cannot block
behind undrained capture pipes. Each child group stays owned until descendants
are retired and its leader is reaped once. QMP closes before group retirement;
interrupts return 130 or 143. Standalone IORegistry export uses the same owner
and cancellation path. Retained work merges into an existing directory, reports
copy failures and rejects destinations inside the temporary source.

Three large boot-fixture records and the reporter's escaped SDK record now
have explicit static storage. The fixture initializes its records once in its
one-shot process; every original assertion is retained. The reporter owns its
record throughout PID 1's lifetime. This removes compiler-generated `memdup`
imports without changing checks or reporter output.

Qualification completed 48 cold builds across native ARM, Rosetta x86 and ARM
ASan/UBSan, followed by eight cold public entry-point builds and nine shell
syntax checks. All profiles pass binary/tree/PNG units, frozen C/V boot goldens
and ten converter cases with byte-identical FDTs, all 78 structure ABI fields,
helpers, allocator-import guards and live IORegistry comparisons (233 matched
nodes, four skipped, zero failures). The independent memory oracle checks
410,739 cases on ARM's 16 KiB pages and 226,419 on x86's 4 KiB pages. Shared
command regression also passes on all three profiles.

Real Unix-socket fixtures cover eleven QEMU success/failure modes, fragmented
and event replies, malformed greetings, EOF, missing dumps, early exit, timeout
and verbose inherited streams. SIGINT and SIGTERM retire emulator and blocked
IORegistry descendants; interrupted export preserves an existing output file.
One hundred explicit-executable launches keep descriptor counts flat. CLI
qualification covers required/invalid options, attached `-o`, full image bytes,
failed-input output preservation and path/retention behavior.

Saved historical artifacts match the complete ADT, boot arguments, scratch,
firmware segment and AIC bytes. The historical image had been capped at 1 MiB;
only that retained prefix is compared. Unknown kernel suffix bytes are filled
with zero to reconstruct layout, and no complete historical-image match is
claimed. A fresh private AArch64 loader cross-build produced 228,416 bytes with
`loader_end` 229,376. A real static AArch64 musl reporter and ustar initramfs
build and unchanged 48-byte iBoot assembly stub also pass. This stage executes
no Python and claims no fresh kernel build, emulator guest boot or hardware
boot.
