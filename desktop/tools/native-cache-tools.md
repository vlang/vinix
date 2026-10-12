# Native cache commands and VOffice builder

`build-support/content-key`, `staging-cache`, `desktop-build-key` and
`desktop/tools/build_voffice` compile maintained V entry points through
`find-v.sh` and `run-v-tool.sh`. Their options and callers use no Python
interpreter or object bridge. `cachecli` owns argument parsing, interruption and
atomic state publication; `officenative` owns compiler discovery, staging,
parallel TLS compilation, app compilation and selective cache reuse.

The content-key format is unchanged. It keeps byte-sorted names, modes,
payloads, symlink text and missing paths, while metadata mode records filesystem
generation. The staging and desktop pre-build keys explicitly upgrade to
`v3-native`, and VOffice state changes from version 2 to 3. Existing keys miss
once. Native producer sources and their dependencies replace the retired bridge
inputs. Desktop keys omit interpreter and Pillow version dimensions; the
desktop source tree, including baked assets and asset producers, remains an
input. Shell-style compiler overrides are split into literal argv without shell
execution. Compiler version probing keeps its ten-second timeout and combined
stdout/stderr convention.

VOffice preserves the original app selection, module closure, compiler flags,
TLS object ordering and cache behavior. Compiler/test sources remain excluded
where the original production-source policy excludes them. All submitted TLS
jobs finish before a failure returns; the reported failure is the earliest
failed submission. Quiet command failures write the combined output to stderr.
State and binaries replace the exact destination through the SDK rename call;
an existing destination directory causes an error. Temporary state files are
removed on failures. Protected input directories and nested work/output
directories are rejected before any reset.

Each command has a private child process group. `sourcecommand` reserves its
leader identity until group retirement and the sole reap. The new combined
capture mode duplicates both child output streams onto one pipe, preserving
write order and one output limit. Signals cancel every running compiler group;
the builder joins TLS workers before returning status 130 or 143. Previous
published applications and state survive interruption before publication.

Qualification freezes the six Python originals at the source commit in
`native-cache-translation.json`, recording their blobs, hashes, bytes and lines.
Python is read only as frozen source data and is never executed. The retained
local evidence is under `~/.cache/vinix-cache-office-native-20261012`.

Qualification makes 39 cold builds across ARM, Rosetta x86 and ARM
ASan/UBSan. Each profile runs the cache, builder, content-tree, build-key and
desktop-key unit suites; the native CLI/signal fixture; both existing staging
and VOffice fake-toolchain workflows; and the shared source-command regression
suite. Checks cover independent original content framing, CLI failures/help,
literal compiler words, malformed quoting, combined stream order, atomic state
failure cleanup, descriptor equality, corrupt/old state, exact compiler/linker
recipes, parallel failure ordering and all submitted jobs. The signal fixture
interrupts an actual builder with two active TLS compiler groups and their
descendants, requiring all four processes to disappear and prior state and
binaries to stay intact. A final compiler-discovery correction uses precisely
the original compiler argv and PATH; six fresh desktop-command and fixture
builds repeat the CLI/signal checks on all three profiles.

The original VOffice workflow checks full builds, cache hits after removing
work, test/compiler-source exclusions, app-only edits, missing binaries and
shared module edits. Its assertions are unchanged; only the invoked entry point
changes. Public fronts are also compiled and exercised independently. These are
host tooling and independent fake-toolchain checks, with no new kernel build,
real VOffice cross-build or guest boot claim.

To rerun the CLI/signal fixture against separately compiled native binaries:

```sh
desktop/tools/test-cache-tools WORK REPOSITORY CONTENT STAGING DESKTOP OFFICE
```
