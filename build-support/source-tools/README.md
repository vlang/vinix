Native V prepares the clock, EXT2 mapping and private-page host test sources
and the minimal ELF64/ARM64 M1 deployment fixture:

```sh
build-support/source-tools/run clock kernel/time/time.v OUTPUT.v
build-support/source-tools/run ext2-mmap kernel/fs/ext2/ext2.v OUTPUT.v
build-support/source-tools/run private-fixture tests/private-pages/source_test.v DIRECTORY
build-support/source-tools/run private-install kernel/memory/mmap/mmap.v OUTPUT.v
build-support/source-tools/run m1-kernel OUTPUT
build-support/source-tools/run test-directory COMPILER DIRECTORY [compiler flags...]
```

Source reads retain strict UTF-8 and universal newline conversion. Selection
keeps the original markers, public function prefixes, body bytes, import order
and `VINIX_FILE_PAGES_HOST`/`VINIX_PAGING_HOST` variants. Missing markers fail
before writing the selected output. The M1 fixture keeps its exact 64-byte
header and 32-byte Limine MP request. No kernel implementation is changed.

The desktop test scripts reuse `native-utility-source.v materialize DIRECTORY`
to replace each regular-file symlink with its bytes. Dangling links and links
to directories stay links. `merge-activity` and `merge-parity` retain the
original file order, exclusions, unique sorted imports and Python-compatible
line splitting. The existing `merge` profile is unchanged.

The flat-directory test driver invokes every staged `_test.v` file directly,
with the caller's compiler flags and module environment. It retains failures,
continues with the remaining files and rejects an empty selection. It also
rejects assertion/panic/sanitizer diagnostics if a compiler returns zero.
Its existing command owner retires children on failures and interruption.
This avoids the shared SDK `vtest` executable's architecture/cache issues.
Both source modules include the native stat header so Darwin selects the
correct inode ABI under Rosetta.

The security-policy host fixture records the current audit hook and checks
one typed event per allowed/denied decision. The mapped-writeback fixture
now models the current non-journaled transaction calls; it rejects attempts
to simulate an unsupported journal. Its existing mapping tests remain.

`qualify.v COMPILER NEW_EVIDENCE arm|x86|san` cold-builds the source command,
desktop source command, behavior checks, existing utility tests and frozen V
reference. It verifies source/Unicode/ordering/link/ELF cases, compares the
existing merge output byte-for-byte with that reference, checks failure
continuation and empty selections, and runs the actual clock/security-policy,
EXT2 mapping, four private/file/paging combinations and disposable M1
deployment workflows. All eight translated shell callers receive syntax
checks. Full desktop UI suites and Vinix guests are outside this qualification;
no Python, GUI application, live ESP or Vinix kernel executes.

The host helpers replace nine embedded Python blocks in five more callers:

```sh
build-support/source-tools/run darwin-signals cxx|assertions|safety|process EXECUTABLE
build-support/source-tools/run game-bundle UPSTREAM_APP_DIRECTORY BUNDLE_DIRECTORY
build-support/source-tools/run ipa BUILD_DIRECTORY Calculator|NumberTileGame
build-support/source-tools/run cpython-headers EXECUTABLE [INCLUDE_DIRECTORY]
build-support/source-tools/run cpython-version EXECUTABLE [INCLUDE_DIRECTORY]
```

Darwin signal checks retain all thirteen original modes, negative signal exit
values, exact stderr markers and success labels. The existing command owner
drains both streams and retires its private child group before the sole reap.
The complete reference script still contains Security/Keychain and credential
fixtures; focused qualification runs only its four signal fixtures and the
non-credential normal modes.

The 2048 helper uses the native XML/binary plist reader, preserves every
unmodified property, replaces the original five bundle properties, and merges
the upstream resources. IPA writing preserves sorted regular-file selection,
file-symlink bytes, directory-symlink exclusion, raw zlib compression, CRCs,
Unicode names, Unix modes, local DOS timestamps and the Payload layout.
Its classic ZIP bounds reject members above 2 GiB, more than 65,535 entries,
archives above 4 GiB and timestamps outside 1980–2107. These example bundles
are small; ZIP64 is outside this helper's scope. Plist whitespace and compression
bytes need not match old output while parsed properties and archive contents do.

CPython SDK discovery reads `Python.h` and `patchlevel.h`; it never launches an
interpreter. `VINIX_CPYTHON_INCLUDE` selects an explicit include directory.
Otherwise the selected executable's symlink target, base prefix, `pyvenv.cfg`,
versioned includes and framework Headers select a unique SDK. Apple's system
launcher uses the active developer SDK, queried by native `xcode-select`.
Missing or ambiguous SDKs fail with the explicit include override documented.
The optional C-API library and Blender still depend on the foreign CPython SDK.

`qualify-host.v COMPILER NEW_EVIDENCE arm|x86|san` cold-builds the command,
host/source behavior checks, four C/C++ references, public command and actual
header library. It checks all signal modes, diagnostic failure, SDK/venv/errors,
the pinned upstream plist/resources, ZIP CRC/content/order/mode/timestamp/link
policies, empty archives and old timestamps. ARM also builds and verifies the
real signed Calculator/2048 Mach-O bundles and both IPA archives. The Rosetta
V controller checks native ARM reference children: the separate x86 Darwin
overflow fixture raises SIGILL, which fails the original required SIGTRAP
verdict. That verdict stays unchanged. No Python, interpreter initialization,
Security/Keychain/credential fixture, Blender build, UI app or Vinix guest runs.

The ISO boot tester sends complete QMP JSON objects with the native command:

```sh
build-support/source-tools/run qmp SOCKET '{"execute":"query-status"}'
build-support/source-tools/run install-qmp OUTPUT
build-support/source-tools/stage-trimmer OUTPUT
```

`test-iso.sh` installs its QMP executable once before starting any VM or input
deadline. Subsequent exchanges execute that binary directly. Installation uses
private scratch and adjacent staging, preserves the previous output on compiler
failure and atomically replaces the executable after a successful build.

The ISO policy consumes one strict UTF-8 text greeting, accepts a capabilities
error, skips asynchronous events and accepts the first terminal reply without
adding or correlating IDs. Full request objects retain arbitrary-sized integer
tokens, escaped strings, arrays, booleans, nulls and last-value duplicate keys.
Valid standard JSON objects are required. QMP error descriptions retain the
default/empty/Unicode diagnostic and text/null/boolean/integer exit policies;
other description types fail validation. Cancellation uses the existing owned
socket and private command group, with exit statuses 130/143. Existing checked,
typed-request and performance QMP policies remain unchanged.

The standalone CMake trimmer retains strict UTF-8, universal newlines and the
prefix before the first `# Vinix execinfo compatibility` marker. A missing
marker retains the complete text; invalid UTF-8 fails before writing. The guest
producer links static AArch64/Linux with the existing musl SDK, checks its ELF
headers, interpreter absence and 16 KiB segment congruence, records source and
compiler hashes and preserves the output on compile failure. KekVM receives it
through its read-only share; see [guest preparation](../../tests/opengothic/kekvm.md).

`qualify-qmp.v COMPILER NEW_EVIDENCE arm|x86|san` cold-builds eight native tools
and existing test programs, installs the QMP frontend, runs actual Unix-socket
and CLI/error/event/EOF/UTF-8/deadline/signal/descriptor cases, and reruns the
original QMP, source and host regressions. Every profile cross-links the static
guest ELF and verifies failure preserves both output kinds. Syntax and ISO help
checks cover the callers. No Python, interpreter initialization, target ELF,
Vinix guest, ISO boot or GUI application executes during this qualification.
