# Signed release routing for legacy Neovim acquisition

An explicit `org.neovim.editor` root in the target architecture's format-2
`/usr/share/vinix-packages/applications.json` replaces legacy `neovim`
acquisition with Software's existing read-only release review. The service
still validates the exact signed closure and repository policy; deployment
still requires the existing confirmation and administrator approval.

This guard covers `vinix-desktop --install-setup-app neovim` and pending legacy
setup requests claimed by Terminal. Neovim always passes through the explicit
installer again at execution, so publishing or replacing a declaration after
claiming a request cannot restore its old `pkg install` path. The broker action
has no caller-controlled declaration, package, confirmation or apply argument,
and the compositor rechecks the fixed declaration before showing review.

The reader captures each directory and the final regular file with descriptor
relative no-follow opens. Every component must have the expected owner and
must not be group or world writable. It bounds the read to 8 MiB, checks file
identity and timestamps around the read, and uses the shared deployment
document decoder. Only an explicit root with its locked package selects this
route. An installed executable or a dependency alone does not select it.

Missing declarations preserve legacy behavior. A present invalid or untrusted
declaration, or unavailable review delivery, refuses mapped Neovim acquisition
without installing a fallback. Other legacy choices retain their behavior.
No publisher is enrolled by this feature.

Run the host checks from the repository root with the selected V compiler:

```
V=/absolute/path/to/v /absolute/path/to/v -backend c -path '@vlib|@vmodules|.|desktop/tools' run desktop/tools/test-app-selection.v
```

The runner binds child builds to that compiler's adjacent vlib, disables
fallback and automatic compiler reports, and uses the C backend for the real
session broker. `VINIX_SETUP_KEEP=1` retains the stage, broker C/executable and
migration-test C/executable. The default run covers seven suites and 52 test
functions. The four migration tests use an actual recording `pkg` executable
and the actual session broker, including same-account kernel PID provenance
and refusal of a public application's compositor-only queue access.

The migration tests cover installed and absent Neovim, missing declarations,
dependency-only declarations, invalid documents, wrong architecture, duplicate
roots, missing pins, unsafe owners/modes, symlinks, failed delivery, duplicate
stale requests, and request/configuration replacement between claim and
execution. They also verify unrelated `mpv` acquisition still executes.

The unchanged translation fixture previously reported Firefox as installed
without providing an executable. Its private executable now satisfies the
existing presence check while Chromium still fails, retaining the complete
translated-result assertions. The unchanged HEAD reproduction and compiler
root diagnosis remain identified in the retained receipt.

The [receipt](results/2026-10-23/signed-legacy-routing.json) binds the checked
sources, full host log, compiler, build driver, frozen build manifests,
generated C and both target compositor ELFs. These are host behavioral checks
and aarch64/x86_64 cross-builds. They do not claim a new native GUI run or a
fully hermetic toolchain build; prior native release-review qualification
remains separate.
