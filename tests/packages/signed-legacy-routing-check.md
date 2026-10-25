# Protected signed release-review routing

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
migration-test C/executable. The 2026-10-23 run covered seven suites and 52 test
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

## Generic compositor admission (2026-10-26)

The compositor's fixed `software.release-review` action now admits the complete
nonempty advertised set without requiring Neovim or another legacy picker
mapping. Every explicit root must have its locked entry in the same captured
format-2 declaration. The protected reader, target architecture and root-owner
checks remain shared with named legacy routing. Empty declarations do not
advertise an acquisition route; ordinary empty removal deployments remain
available through Software. The action still accepts exactly one fixed token
and opens only the existing read-only Software review. Signature, trust,
closure, separate confirmation and administrator approval remain service
responsibilities. No catalogue entry or publisher authority was added.

Source revision: `d76cf2bfe2ed3a0b6964c23488d1fbec29f434a0`.
The dedicated five-test `app_selection_release_routing` suite passes normally,
with V `-prod` (including an optimized `clang -O2` link/run), and with
AddressSanitizer plus UndefinedBehaviorSanitizer
(`ASAN_OPTIONS=detect_leaks=0`; this is not a leak qualification). Its explicit
`if`/panic checks and their calls remain in production-generated C. Both target
architectures are exercised as declaration inputs on the host. The suite checks
four selected root IDs, mixed roots, missing declarations and pins, invalid and
wrong-architecture documents, unsafe owners/modes, file/directory symlinks,
caller operands, failed review delivery and unchanged declarations. Its actual
recording `pkg` control executes when no declaration exists, while failed
delivery never invokes a fallback.

Run the focused suite with the command above plus
`app_selection_release_routing`. Add `VINIX_SETUP_PRODUCTION=1` for production
checks, or `VINIX_SETUP_SANITIZE=1 ASAN_OPTIONS=detect_leaks=0` for sanitizers.
Production mode refuses other suite selections because historical assertions
and their side effects are removed by V `-prod`. The runner freezes the changed
package reader and test source before compiling, and retains focused generated
C/executables with `VINIX_SETUP_KEEP=1`. The normal default now selects eight
suites and 57 test functions.

The initial complete historical migration attempt failed at actual broker
readiness; its failure and sanitized broker reproduction are preserved. The
host compiler follow-up below qualifies that path separately. This focused
bundle does not claim a full default-suite pass or a native GUI run. Combined
target compositor build qualification is reported [separately](section14-target-build.md).

The external audit bundle contains the checked source archive, source digests,
frozen normal/production/sanitizer stages, generated C/executables, full logs and
the failed historical attempt. It also preserves the compiler binary, tracked
vlib source archive and tracked working patch. The complete archive was listed
successfully and its recorded constituent digests were verified.

Archive: `/Users/alex/Library/Caches/vinix-codex/section14/package-release-routing-20261026.tar.gz`

SHA-256: `cc12ff0e4f7ec222543815e0338f737dd6beded980a9ba966580835157cb2b03`

## Host fixture compiler follow-up (2026-10-26)

Source revision: `e4f8ac38f355c7c5ccfd076bc13c9cb2c3c89f20`.
The runner now explicitly selects Clang for its host recording `pkg` and actual
session broker, matching the setup test links. It records direct build and test
commands as JSON argument arrays in the retained stage's `commands.jsonl`.
The production broker source is unchanged.

A standalone V fixture, importing no desktop app, reproduces startup failure
with the original broker and a fresh broker from the selected V compiler's
default C compiler. Both exit with status 139 before readiness; their generated
C has identical SHA-256
`df4e2ce68d875a230258675a1700f16e267e046c8a3f1367801d354b1ff24c6c`.
V's recorded native compiler command selects TinyCC. Clang linking that exact
original generated C succeeds, and a fresh V build with `-cc clang` succeeds.
The final diagnostic checks ping, attach, child termination and reaping before
reporting success. This isolates and avoids the host fixture compiler failure;
it does not diagnose or fix TinyCC.

With the explicit Clang selection, the historical four-test migration suite
passes using the actual broker. The complete default run passes all eight
suites and 57 test functions, including the five-test generic routing suite.
This host run retains separate broker isolation evidence and does not claim
native compositor or guest GUI execution.

The supplementary complete bundle preserves the checked source archive,
selected compiler binary and tracked vlib source/patch, full default log,
direct command log, frozen default and migration stages, original broker,
standalone controls and generated C/executables. As in the existing runner,
generated C/executables are retained for migration, routing and the final suite;
earlier default suites share an output path. All recorded regular-file digests
and symlink targets were verified before archiving, and the complete archive
was listed successfully. The original focused bundle remains unchanged.

Archive: `/Users/alex/Library/Caches/vinix-codex/section14/package-release-routing-20261026-host-clang.tar.gz`

SHA-256: `cd3c0b81a75b8239a0e456b9cf72fead4adfe4c635b44e96fec57030da68789c`
