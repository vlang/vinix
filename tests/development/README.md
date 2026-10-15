# Native development workflow checks

Stage the four development commands with the maintained V stager, then run
the guest controller against an already-built isolated production kernel:

```
v -gc none -cc cc run tools/development/stage.v aarch64 /tmp/development-arm
tests/development/run-guest aarch64 /path/to/kernel /tmp/development-arm /tmp/new-arm-state

v -gc none -cc cc run tools/development/stage.v x86_64 /tmp/development-x86
tests/development/run-guest x86_64 /path/to/kernel /tmp/development-x86 /tmp/new-x86-state
```

The V controller validates the completed staging manifest, each tool's SHA-256
and ELF architecture, copies the input kernel, compiles the V fixture and owns
QEMU without networking. AArch64 selects HVF on macOS by default; set `USE_TCG=1`
to use TCG. Each state directory must be new. No Python executes.

The fixture requires the Vinix kernel identity and runs the public CLIs as
UID/GID 1000. It checks all four help entry points, schedule/account binding,
a real scheduled job, selected credentials and environment, private plan/state
ownership and modes, interval coalescing, and refusal of public or symlinked
credential files. The payload deliberately writes the synthetic credential to
both stdout and stderr; the controller fails if it appears in the serial log.
Successful jobs produce a file, and rejected jobs must produce none.

The base gate also exports a scheduler service unit as UID/GID 1000. The CLI
validates it through the maintained native importer; the fixture checks its
exact literal watcher argv, restart policy, ten-second stop window, private
output file and unchanged schedule, with no credential embedded in the unit.
The serial log retains the exported text and `DEVELOPMENT SERVICE EXPORT PASS`.
This base gate checks native export and parser compatibility. Select the real
Services broker explicitly to add import/start/stop and broker-restart checks:

```
VINIX_DEVELOPMENT_SERVICE_BROKER=/path/to/native/vinix-desktop \
tests/development/run-guest aarch64 /path/to/kernel /path/to/staged-tools /path/to/new-state
```

Supply a static broker with embedded VML assets for the selected architecture. The
controller copies the exact ELF into the guest and records its SHA-256 beside
the four development commands. An unsuitable or missing broker cannot satisfy
the optional verdict or its four extra receipts.

The ordinary account exports and imports its schedule disabled. Import before
compositor attachment and Start from an ordinary child of the attached process
must be refused without changing configuration. The fixture then starts a real
watcher with a credential-bearing job and a forked descendant. Explicit Stop,
session-broker shutdown during the next active job, and Stop after enabled
configuration restoration must each retire the guardian, watcher and both job
processes within the exported ten-second stop window. Removing the stopped
service must survive another broker restart. No authorization rule is changed.

The host checks all three interrupted schedule receipts against the generated
plan hash, account, exact attempt/run counts and next-due interval. It also
requires distinct guardian/watcher identities, bounded stops and byte-exact
enabled/disabled/removed service registry records through the maintained
importer. Credential bytes must never reach the serial transcript or broker
log. Persistent-home cold boot and graphical interaction remain separate gates.

On 15 October 2026 this optional gate and the full base workflow passed on
ARM64 HVF and x86-64 TCG with 18 receipts each. Evidence remains under
`build/development-service-lifecycle-20261015/guest-arm-current` and
`guest-x86-current`. Their receipts pin the copied kernels, V fixtures, four
staged commands and native desktop brokers. Stops took 125/212/120 ms on ARM64
and 394/498/463 ms on x86-64, including retirement probes for every observed
guardian, watcher and job descendant. All seven scheduler/importer/supervisor/
receipt-validation host test files passed with V `be2eb40`.

The retained `broker-arm64` and `broker-amd64` build directories contain source
hash maps and the actual executables. Each uses this checkout's unchanged
`desktop/session_service.c.v` and complete `desktop/sessioncore` module with a
retained materialized UI source tree. The V build script, generated C and logs
are beside them; production V translation embeds assets, and Clang links the
matching musl and V signal-handler runtime statically. The audit checks those
runtime/module source hashes, kernel/fixture/broker pins and both native proofs.
The initial prepared brokers failed before opening their sockets because they
referenced host-path VML assets; the failed serial transcripts are retained as
`guest-arm-c`, `guest-arm-d` and `guest-x86-c`. The final runs reuse the isolated
production kernels and typed-null compiler adaptation recorded below.

The export gate passed on 15 October 2026 on ARM64 HVF and x86-64 TCG with
the maintained stager's updated CLIs. The 14-record receipts, native exported
unit text and passing verdict are retained in
`build/development-service-20261015/guest-arm` and `guest-x86`, with the two
complete tool stages beside them. These runs reuse the isolated kernels and
typed-null compiler adaptation recorded below. All six scheduler/importer/
supervisor host test files also passed, including real watcher start/stop and
literal paths with spaces, quotes and backslashes.

Every run also checks FIFO private-file paths without creating a writer. As
UID/GID 1000, the fixture replaces the credential with a mode-0600 FIFO and
requires the public scheduler to fail within three seconds, preserve the inode,
settle the reserved attempt and produce no job output. Rotation back to a
regular private credential must execute the second attempt after the normal
interval. FIFO stored plans and states must also refuse both `status` and
`run-due` within that bound. Their original files are restored afterwards.
The host independently checks two additional receipts against the exact plan
hash, account, attempt/run counters, failure/recovery statuses and intervals.
The base workflow now retains 14 records; historical 12-record runs below
predate these additional cases. Other reference modes also add two records.

On 15 October 2026 the extended base gate passed on ARM64 HVF and x86-64 TCG,
using V `be2eb40`, QEMU 11.1.1 and the maintained static tool stager. The passing
14-record receipts, serial logs, fixture/ISO and kernel/tool pins are retained
in `build/development-fifo-20261015/guest-arm` and `guest-x86`. The controlled
ARM64 `baseline-arm-b` stage removed only `O_NONBLOCK` from the scheduler's
private-file open; it reproduced the hang at the fixture's three-second deadline
after passing the existing account checks. No writer was connected to the FIFO.

Both kernels were built in an isolated worktree from `e42b3946c`. The unadapted
revision fails this V compiler's check of literal-zero pointer returns in
`kernel/fs/vfs.v`. The test worktree applies only the recorded typed-null
compatibility patch, SHA-256
`c8b114d931b2d6fba0d899c6e0e2340c181128d130ecdee042d7eac417c9f395`.
The baseline diagnostic, exact patch and build logs remain beside the receipts.
Native ARM fixture compilation selected the installed musl sysroot through
`VINIX_AARCH64_SYSROOT`; its retained V `clang-native` wrapper selects the
matching GCC runtime with Clang's `--gcc-toolchain` option. These checks qualify
private-file handling and the base runner workflow; compiler-project, complete
installed self-hosting and broader server/CI acceptance retain their own gates.

The same account also qualifies job lifecycle control with real child groups.
A one-second deadline must retire a job and its forked descendant. Both SIGINT
and SIGTERM must stop a watcher during a running job, retire that group and
persist the interruption. Concurrent execution and acknowledgement are refused
while the owner holds the schedule lock. A watcher then completes two interval
jobs across its re-execution ticks; both payloads must observe the same parent
PID. Finally, killing a runner with SIGKILL must leave an in-flight receipt and
block automatic retry. The fixture retires its freshly observed live group,
acknowledges the interruption and verifies one successful recovery run. PID 1
reaps orphaned descendants during these checks; all signals and schedule actions
originate from UID/GID 1000.

The controller independently validates all six lifecycle state records against
the exact generated plan hashes, account, run counts, in-flight flags, deadline
and signal failure details, completion statuses and next-due intervals. These
checks extend every guest run, including runs without a native compiler SDK.

On 13 October 2026 these lifecycle gates and the account/build regression passed
on AArch64 HVF and x86_64 TCG with the isolated production kernels and staged
commands described below. The independently validated 12-record receipts and
serial transcripts are retained in
`build/development17-20261013/guest-arm-job-control-d` and
`build/development17-20261013/guest-x86-job-control-d`.

Signal authorization also retains the exiting task's user-namespace identity
until reap. As UID 1000, the fixture refuses probes and SIGTERM to root's PID 1,
exits an owned child and uses `waitid(WNOWAIT)` to retain its zombie identity.
All 100 signal-zero probes and SIGTERM calls must remain authorized; after
`waitpid` reaps it, the same probe must return `ESRCH`. This regression reproduced
`EPERM` on both unchanged kernels in
`build/development17-20261013/guest-arm-signal-baseline-b` and
`build/development17-20261013/guest-x86-signal-baseline-b`.

On 13 October 2026 both production architectures built with the signal-identity
fix in isolated worktrees from `776b9f0d3` plus the `116ba2c78` metadata policy.
The native signal, account, job lifecycle and build-plan gates passed in
`build/development17-20261013/guest-arm-signal-fixed` and
`build/development17-20261013/guest-x86-signal-fixed`. Each passing receipt pins
the actual kernel, fixture and staged commands. Authorization uses the existing
saved namespace ID under the process-table lock; account, capability, session
and mandatory-security-domain checks retain their existing rules.

The same ordinary account then runs a pinned build plan in two new workspaces.
Its prebuilt V payload reads through a copied internal symlink, checks the fixed
build epoch and sanitized environment, and writes an artifact. The fixture
checks source/link preservation, account-owned private output/HOME/temporary directories and actual artifact
contents. The controller independently checks both native receipt hashes against
the expected bytes. Altering the pinned source must stop the next build before
execution. This tests runner behavior with a prebuilt payload; compiling all
Vinix layers inside an installed system remains open.

For additional reference workflows, prepare one native SDK prefix and select
its profiles explicitly:

```
VINIX_DEVELOPMENT_REFERENCE_SDK=/path/to/reference-prefix \
VINIX_DEVELOPMENT_REFERENCE_PROFILES=make,ninja,sqlite \
tests/development/run-guest aarch64 /path/to/kernel /path/to/staged-tools /path/to/new-state
```

This mode uses the four base arguments and a separate SDK, with commands under
`bin`, native musl and other runtime libraries under `lib`, and the complete
compiler/modules/data closure needed by the selected tools. `lib/libc.so` must
be an ordinary file. Internal relative tool aliases are preserved. Selected
executables must be native ELF64 without set-ID bits; escaped aliases, wrong
architectures, duplicate/unknown profiles and incomplete option pairs are
refused before creating state. The current reference catalog is:

| Profile | Required `bin` entries |
| --- | --- |
| `make` | `make`, `cc`, `sh` |
| `ninja` | `ninja`, `cc`, `sh` |
| `cmake` | `cmake`, `ninja`, `cc`, `sh` |
| `sqlite` | `sqlite3` |
| `node` | `node` |
| `go` | `go`, with its matching standard library and native compiler subprograms |
| `java` | `java`, `javac`, `jar`, with a complete matching JDK |
| `http` | `busybox`, with the HTTP applet, Basic authentication and CGI support |

The controller imports the prefix as `/opt/reference`, excludes Python helpers,
installs its runtime in `/lib` and pins both complete trees separately. It
normalizes the musl loader alias and supplies `/bin/sh` only from the selected
pinned shell. Prepare one coherent prefix; this mode cannot be mixed with the
positional GCC/V SDK arguments. No host tool is silently substituted.

UID/GID 1000 runs a generated build plan twice in fresh private workspaces.
Pinned version commands precede `vinix-qualify --require-vinix`; Java records
its versions as the first three qualifier commands. The project
commands retain the 600-second budget. The plan uses 1800-second step deadlines
and the guest receives 2 GiB of RAM. Both input trees are verified before and
after the build. The fixture checks account ownership and mode-0700 output
directories. Receipts include the plan, both build receipts and both native
qualification reports, for 19 records with the baseline account/job/build checks.

The host independently checks the exact plan hash, source/SDK/tool pins, epoch,
account, kernel, command order and complete executed argv. It also checks each
reference report's selected profiles, actual tool or produced executable hash,
successful exit status and command-log path. Compiled programs, readback files,
JavaScript sources and databases must match across workspaces. Readback files
must contain the expected `42`. Reports retain workspace paths and timestamps;
their contents are validated independently rather than required to hash equally.
Missing tools, failed projects and differing artifacts fail the gate. Failed
runs retain version/command diagnostics and the failed build receipt.

The [minimal server builder](../../tools/development/build-http.v) prepares
BusyBox 1.36.1 from a pinned archive with the required HTTP/Basic-auth/CGI
configuration; see [the source-build command](../../tools/development/README.md).
The [HTTP SDK stager](../../tools/development/stage-http.v) creates a small
reference prefix from already-prepared BusyBox and musl ELF inputs:

```
V_C_ERROR_BUG_REPORT_DISABLED=1 v -cc cc run tools/development/stage-http.v \
  aarch64 /path/to/native-busybox /path/to/native-musl /path/to/new-http-stage

V_C_ERROR_BUG_REPORT_DISABLED=1 \
VINIX_DEVELOPMENT_REFERENCE_SDK=/path/to/new-http-stage/sdk \
VINIX_DEVELOPMENT_REFERENCE_PROFILES=http \
tests/development/run-guest aarch64 /path/to/kernel /path/to/staged-tools /path/to/new-state
```

The `http` profile starts the pinned server on an unprivileged loopback port.
The V client verifies unauthenticated/wrong-password refusal, GET/HEAD, missing
and private-config paths, encoded traversal refusal, an authenticated V CGI
POST and 16 repeated requests. The exact qualifier binary is copied as the
CGI application and pinned as a produced artifact. A random credential stays
in an exclusively created, no-follow, mode-0600 file outside the document root;
the fixture verifies its account ownership/privacy without emitting it.
Unauthenticated requests must not create the CGI's private data artifact.

After protocol checks, the owner retires the server process group; its command
receipt must record SIGTERM (`-15`). The normal account/job/build checks still
run. Both native HTTP case records are emitted as well, for 21 records in
this reference mode. The host independently validates the actual server argv,
loopback/port restrictions, executable/CGI pins, empty JIT overrides, response
cases, owner, request count and retirement. Each native case record must match
its build artifact hash, and helper/content/case/data artifacts must match in
both fresh workspaces. Credential files, ephemeral ports and PIDs are excluded
from those reproducible public artifacts. This remains a local HTTP/CGI gate;
TLS, remote exposure, production load and SSH/CI have separate acceptance work.

On 13 October 2026 AArch64 HVF and x86_64 TCG passed the complete HTTP
workflow as UID/GID 1000 in two fresh native workspaces each. Final receipts
and serial logs remain in
`build/development17-20261013/guest-arm-reference-http-g` and
`build/development17-20261013/guest-x86-reference-http-g`. Both receipts
retain 19 independently validated records, including the ordinary account,
build and job regressions. The prepared BusyBox 1.36.1 servers were built
with musl GCC 14.2.0 from archive pin
`b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314`.
Two fresh host source builds per architecture produced identical configurations
and server binaries. The patched export pin is
`36c3c870168778dd9e7802544e3393a7db6c257203fe23617d1b2ae4c05f7c1c`,
with configuration pin
`e4c35f6fd082f7133c99c4fe331fafe2583ffa95554b1ff0be6ebc5aa7548667`.

| Native HTTP input | AArch64 | x86_64 |
| --- | --- | --- |
| Server | `5b6f58617cdefe71661cb81f5fb4bd755b562c034aa270f13056c131288d338c` | `77434ed738dc65ee794b73232ff71024eecffef6bce80a12a4128c7efb07afb2` |
| Reference prefix | `50b96f8a95efe51cfb3a789b1df577159b42a5dffeea861310e4054cbbc72581` | `f7284aff43571c97833e094cbbbd3ff3d1ee208d921c8f81c47ea940a8c73f48` |
| Imported runtime | `24ad3df555386b91a3d98feb75518aaa2ae62982ba6c8060ddc16729f632e313` | `585797fa6e5628bd118c5541a4573a301b447c88ee702cdff3a14cdeed032d75` |
| Qualifier / CGI | `9a5d7746a31fab9999f51ebbdd4026b738b05d9dbf932bd84812af6defbbe8f0` | `83b014a5f0f7cdc4e3105a9666eee0f3c92a89dc090ba7a9ea092399f8da54f0` |

Source-build evidence remains in
`build/development17-20261013/http-server-{arm,x86}-{d,e}`, with reference
stages in `reference-{arm,x86}-http-d`. The unadapted minimal server failed
HEAD by sending two body bytes; the recorded adaptation fixes that failure.
Earlier prepared binaries also failed: the x86 package lacked `httpd`, and
the older AArch64 binary terminated with SIGSEGV before serving. Those runs
remain failed receipts; qualification applies to the exact tuples above.
Server diagnostics remain in private logs, including on failure; the guest
emits bounded qualifier diagnostics and public case receipts.

For the scheduled native Go CI gate, set `VINIX_DEVELOPMENT_REFERENCE_CI=1`
with the prepared Go prefix and development tools that support reserved
attempts and nested command interruption:

```
V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=0 \
VINIX_DEVELOPMENT_REFERENCE_SDK=/path/to/native-go-stage/sdk \
VINIX_DEVELOPMENT_REFERENCE_PROFILES=go \
VINIX_DEVELOPMENT_REFERENCE_CI=1 \
tests/development/run-guest aarch64 /path/to/kernel /path/to/staged-tools /path/to/new-ci-state
```

CI mode replaces the two manual reference builds with a pinned `vinix-jobs`
schedule executing `vinix-build`. Its opt-in `{attempt}` argument produces
`/home/developer/ci-1` and `ci-2`. Both runs compile and execute the ordinary
Go goroutine/channel/file project. A pinned child verifies UID/GID 1000 and
that the schedule's private credential and unselected parent credentials
are absent from build commands. The credential is passed only to the selected
build runner; values stay outside schedule/build receipts and serial output.

The third attempt encounters a preexisting output containing a sentinel.
It must fail without changing that file or creating a build receipt, while
advancing its reserved and completed attempt counts to three. The host checks
the exact schedule executable/arguments, credential paths, empty job environment,
plan pin, completed and failed state, interval, both build/report contracts,
account-proof hashes, and matching Go program/data artifacts. There are 22
independently checked native records in this mode. Other profile selections
are refused before staging. This gate exercises a local native CI reference
pipeline; service/boot integration, remote CI, deployment and wider project
workflows retain separate acceptance work.

On 13 October 2026 AArch64 HVF passed this gate with Go 1.23.9 in
`build/development17-20261013/guest-arm-reference-ci-d`. Its receipt records
`reference_ci: true`, 22 native records and SDK/runtime pins
`41be47dff0e19457302ad26ea9b668c9065fc2ddcbfb833ee93a8aecc2f9ee00` /
`3dce764667a2ad550c540fcd81cfec45f06bd6839acb367446044d0e9a9fc996`.
Both program hashes are
`560d3fefeaebf7a545a1b18f7fc33d3b423f2a2b244d2a15fd3e6f9fe1e5371d`;
both account-proof hashes are
`a0e36539edcca62f49f8a10d46bf810efb38bda87593f7b28b9940a8b71d576b`.
The build/qualifier/scheduler pins are
`4f95aa31ce47966780d5b9b09d5de7ba5246ea2c5079546b69d0de610c501fd2`,
`c110decd42a2519be785824eef6d1ed10c8e9f0322013c6f44382bba47d61aeb`
and `5720b53503e7986e2958234a0226d5305b72c4885fa2c8f4f338c315808373d3`.
Their complete stages remain in `tools-arm-ci-b` and `tools-x86-ci-b` under
the same evidence root. The x86 HTTP/account/job/build regression passed with
these tools in `guest-x86-ci-cancellation-c` (19 records). Native x86 Go CI
has not been qualified by these results.

On 13 October 2026 AArch64 HVF passed GNU make 4.4.1, Samurai's Ninja-compatible
CLI reporting `1.9`, and SQLite 3.53.4 in
`build/development17-20261013/guest-arm-reference-buildtools-c`. GCC reported
11.2.1 (20211120); the prepared prefix combines its native compiler closure with
the recorded tool binaries, BusyBox 1.36.1 and the SQLite/musl runtime. Its SDK
pin is `6db053f3742cc0fa282c5297242ccc40ad27505f39248d391fe7e9c87893c590`
and runtime pin is
`08ba65716281d6d539cc2e65e27a9cdf0234bee5b0a42971eb4be59c4e310789`.
Both make and Ninja compiled and executed the real C thread/file project; their
matching program hash is
`7396f1241c2c26c5dd351f0bd10b3247bb21d4c3faabfa060c0f640304f7d655`.

x86_64 TCG passed SQLite 3.53.4 in
`build/development17-20261013/guest-x86-reference-sqlite-c`, with SDK pin
`213079cfa99e3e47d72300cec720e8e8496f51f98f1ee635b2a7d0b202ee3a9e`
and runtime pin
`f777d9cdc108c3981be80850d3bcdd0fb22cdd53a2f00d733b6c05761871a16a`.
Both architectures committed/rolled back transactions, reopened the database
and checked integrity as UID 1000. All fresh-workspace database artifacts had
hash `fd435e2532e289f73d37c4363ce05638e0bd33156e8e0345b72906c06b86e7d0`.
The prepared SQLite binaries/runtime come from the existing
[pinned upstream input build](../packages/sqlite-profile-check.md). These are
developer reference projects; the package suite separately qualifies WAL and
application lifecycle workflows. CMake, Node, native x86 build systems and
production server/SSH/CI workloads retain their own acceptance gates. The later
CMake acceptance below closes its tested AArch64 reference-project gate.

The maintained [CMake SDK stager](../../tools/development/stage-cmake.v) adds a
prepared native CMake executable, its module tree and recursively inspected
shared-library dependencies to a prepared compiler/Ninja/shell prefix:

```
V_C_ERROR_BUG_REPORT_DISABLED=1 v -cc cc run tools/development/stage-cmake.v \
  aarch64 /path/to/reference-prefix /path/to/developer-overlay /path/to/new-cmake-stage
```

The overlay uses `usr/bin/cmake`, `usr/share/cmake*`, `usr/lib` and `lib`.
The output prefix is `new-cmake-stage/sdk`; `reference-sdk.json` records the
readelf executable pin, imported base-tree pin, source file pins, module-tree
pin and final SDK pin. Only `complete: true` represents a finished stage. No
fetch or package installation runs. Python helpers/templates are excluded
before copying, escaped links and staging inside an input closure are refused,
and the selected tools and runtime architecture are checked.

The stager retains the supplied musl and `libgcc_s.so.1`. Blindly replacing the
compiler's `libgcc_s` with a newer package library made the old linker reject
`.relr.dyn` sections in the first native CMake run. The stager preserves that
compiler input and checks its pin. An incompatible CMake runtime still fails
native qualification; preparation does not establish arbitrary ABI compatibility.

On 13 October 2026 the maintained stage completed in
`build/development17-20261013/reference-arm-cmake-maintained`, and its exact
SDK passed CMake 3.31.1, Samurai/Ninja and SQLite 3.53.4 as UID/GID 1000 in
`build/development17-20261013/guest-arm-reference-cmake-maintained-c`.
Both fresh workspaces configured and built the CMake project, executed its exact
binary and produced the same program/data/database hashes as the earlier make
and Ninja gate. The 17-record receipt independently validated all three CMake
commands and their tool/artifact pins. The SDK pin is
`b6c922cb059dd9827dcebb614587002b22609962203989f00ff9205e7beea378`
and copied runtime pin is
`e0d2f13520308dadb5acc290783a19018f4b3deb3aea4fc2824b8644b9fb8c1f`.
The CMake module-tree pin is
`28e42bb5ce0f2ea9f62fa42d5c2bbe121638ec3e423c0dc29ac81d7f576fa5b2`.
This qualifies the tested C project and compiler/runtime tuple. Wider CMake
project and platform support, Node, native x86 build systems and the remaining
language/IDE/server gates stay open.

The maintained [Go SDK stager](../../tools/development/stage-go.v) imports an
existing overlay's `usr/lib/go` and ordinary `lib/ld-musl-ARCH.so.1` into a
new `sdk` prefix. Its contained `bin/go` alias resolves to `share/go/bin/go`,
so the native tool discovers its matching source/library/subprogram closure.
Source/imported tree, executable, runtime and SDK hashes are retained in
`reference-sdk.json`. Python helpers are excluded before copying, set-ID
inputs and escaped links are refused, and an output alias into the source is
rejected before creating state. See [the Go gate commands](../go/README.md).

On 13 October 2026 AArch64 HVF passed Go 1.23.9, reporting
`go version go1.23.9 linux/arm64`, in
`build/development17-20261013/guest-arm-reference-go-d`. Both fresh UID/GID
1000 workspaces built and executed the goroutine/channel/file project with
the exact pinned compiler. The private cache, `GOENV=off`, `GOTOOLCHAIN=local`,
offline resolution, `-trimpath` and `-buildvcs=false` keep external configuration,
downloads and workspace/VCS paths out of the reference build. All 17 native
records passed independent validation, along with the account/job/build gates.

The SDK pin is
`41be47dff0e19457302ad26ea9b668c9065fc2ddcbfb833ee93a8aecc2f9ee00`,
runtime pin is
`3dce764667a2ad550c540fcd81cfec45f06bd6839acb367446044d0e9a9fc996`
and Go executable pin is
`bff41476a04c26ce1db8ab0b69ed4ad52a9a76c4b1d51734ae57821c5d40e001`.
The matching compiled program hash is
`560d3fefeaebf7a545a1b18f7fc33d3b423f2a2b244d2a15fd3e6f9fe1e5371d`;
both readback files contain `42` and hash to
`73475cb40a568e8da8a045ced110137e159f890ac4da883b6b17dc651b3a8049`.
The completed stage is retained in
`build/development17-20261013/reference-arm-go-b`. This qualifies the tested
pure-Go project through Vinix's Linux ABI; native x86 Go, cgo, wider module,
network, debugger and production-server workflows remain separate gates.

Java uses the [native SDK stager](../../tools/development/stage-java.v) and
the explicit JIT gate shown in [tests/java](../java/README.md). The qualifier
records all six version/compile/pack/run commands, the actual JIT environment
overrides and the generated class/JAR/data pins. The host rejects missing
artifacts, changing archive timestamps, substituted version commands, changed
tool pins and unselected JIT requests.

On 13 October 2026 AArch64 HVF passed OpenJDK, `javac` and `jar` 25.0.4 from
the pinned Alpine SDK as UID/GID 1000 in
`build/development17-20261013/guest-arm-reference-java-jit-b`. Both private
workspaces compiled `Project.java`, created an executable JAR with fixed
entry timestamps, and ran its thread/file checks. All 17 native records
passed independent validation. The native fixture denied requests before
approval and outside the read-only JDK mount, refused the ordinary account's
remount/write attempts, and denied another launch after administrator
revocation. No sandbox-disable or authorization fallback was used.

The SDK pin is
`affee8307732e90b3964a25ade378f01084bb3ae5536d8ed8fbe0f3bad3bc5a1`,
runtime pin is
`d61c4ea878bc136699e5ad8d766a1097533107615359dd67518f15338ade8c45`
and imported JDK tree pin is
`3dea0bec80a14b66b5c7f7f520674a40a37a786cb768485e8e51fbdde55c295a`.
The matching class hash is
`d62742a5498c2bee7586977ca7d6edfa5b95726b826f4aaa50fcc34dec0be133`,
JAR hash is
`0f5525b507a9c1e251a1e24795b5bb2f84e2762229c13a8d1db5b49433ff36bb`
and readback files contain `42`. Stage manifests retain each source file/alias,
runtime and trust-store pin. The prepared SDKs and receipts remain in
`build/development17-20261013/reference-arm-java-a` and `reference-arm-java-b`.
This qualifies the tested thread/file/JAR workflow with explicit mount approval;
native x86 Java, wider JVM/IDE/debugger, module, TLS/network and server workloads
remain separate gates.

The existing Go gate also passed with the updated qualifier and JIT disabled
in `build/development17-20261013/guest-arm-reference-go-jit-regression-a`,
retaining its earlier matching program hash and empty child overrides. The
updated fixture's x86_64 TCG account/job/build regression passed in
`build/development17-20261013/guest-x86-java-fixture-regression-a`.

Host option/receipt refusal tests run with:

```
V_C_ERROR_BUG_REPORT_DISABLED=1 v -cc cc test tests/development/referencecore
```

To compile and execute the C/C++ reference projects in the guest, supply a
prepared native musl GCC SDK for the selected architecture:

```
tests/development/run-guest aarch64 /path/to/kernel /tmp/development-arm /tmp/new-sdk-state /path/to/aarch64-linux-musl-native
```

The controller copies the SDK to `/opt/native`, installs its runtime libraries
in the guest's `/lib`, and supplies `cc`/`c++` aliases to its native drivers.
It validates the drivers' ELF architecture and records a deterministic closure
hash over copied paths, permission bits, file bytes and links, including the
runtime copy. Relative links must stay inside the SDK; `/lib/libc.so` is the
only accepted absolute link target. Unused `.py`, `.pyc` and `.pyo` helpers are
excluded before copying. The SDK is prepared input, not downloaded or built by
this controller. Compiler workloads receive 2 GiB of guest RAM.
The musl loader link is normalized to its adjacent `libc.so`, so the copied
SDK and runtime are portable closures that `vinix-build` can pin.

As UID/GID 1000, the fixture invokes `vinix-qualify --require-vinix` for `c,cpp`.
Both projects must compile with symbols, create/join a thread, write/read a
file and execute their exact resulting binary. The controller independently
checks the native report's kernel, architecture, account, runner and compiler
hashes, both successful command statuses and the executed artifact paths.
Compiler versions remain in the serial transcript. A missing compiler or
failed project fails the run.

For the native V reference project, append a prepared V installation root
(containing `v`, its matching `vlib`, `thirdparty` and `cmd`) and a native
BusyBox executable with its shell applet. A static BusyBox avoids additional
loader dependencies:

```
tests/development/run-guest aarch64 /path/to/kernel /tmp/development-arm /tmp/new-v-state /path/to/aarch64-linux-musl-native /path/to/vlang /path/to/native-static-busybox
```

The maintained [V compiler stager](../../tools/development/stage-v.v) prepares
that matching installation from committed compiler/library sources:

```
v -cc cc run tools/development/stage-v.v aarch64 /path/to/v-checkout /path/to/new-native-v
```

This copies and hashes the V root with Python helpers excluded, installs the
compiler beside its matching library at `/usr/lib/vlang`, checks V/BusyBox ELF
architectures and records both executable hashes. The V project uses the
explicit Vinix/musl target, serial V3 workers and the native C compiler. It
must compile, write/read a file and execute its resulting binary. These runs
receive 3 GiB of RAM. Failed qualification retains bounded command-log excerpts
in the serial transcript as well as the native report.

V runs export this repository's committed `fetch`, `mount`, `chsh`, `lscpu`,
`init` and package-CLI sources from one full Git commit. Each immutable blob is
verified; dirty/untracked files and Python helpers are excluded, and selected
symlinks are refused. `SOURCE_REVISION` and the host receipt record that commit.
The controller generates a build plan pinning those sources, V, GCC, the shell and
the complete SDK/V/runtime trees. UID/GID 1000 builds them in two fresh
workspaces with private HOME/temporary directories, then executes each recorded artifact's
`--version` entry point. The fixture checks ownership, executable ELF headers
and expected utility output. `lscpu` also runs its CPU inspection path; the
fixture independently counts `/proc/cpuinfo` processor records and checks the
reported architecture. The controller independently checks both build
receipts, their input pins, step order, complete executed argv and matching
binary hashes. The native plan and both receipts are retained alongside the
compiler report. Version entry points provide execution smoke coverage;
filesystem mounting and account-changing workflows have their own gates.
The rebuilt `init` runs its version entry point before setting environment
variables, changing directory, setting the hostname or entering its login loop.
This checks native compilation and safe execution; booting it as PID 1 and
qualifying its login workflow remain separate acceptance work.
The ARM CPU backend reports the kernel's raw IDs and common feature names;
it does not infer a model or independently qualify the kernel's hardware IDs.

The same plan compiles the package CLI with the documented Linux/musl ABI target,
checks both V and package help entry points, packs the freshly compiled `lscpu`
as a native package and publishes a signed consumer repository. Both workspaces
must complete all 19 steps and produce identical executable, manifest, index,
signature and payload-copy hashes. A pinned BusyBox supplies the payload
directory/copy commands. The public synthetic signing seed lives outside the
source closure as an additional pinned input, owned by UID 1000 with mode 0600.

The source closure also includes a generated V assertion-failure project. Both
workspaces compile it to matching binaries; each must exit 1 and report its
relative source filename, line, expression and panic diagnostic. This verifies
that workspace-independent binaries retain working assertion failures. The
matching compiler stager normalizes project assertion paths when the build
runner sets `SOURCE_DATE_EPOCH`; it preserves explicit logical source names.

The fixture checks the exported object's ownership/mode, size and SHA-256
against the compiled executable and checks that `publisher.seed` and `.publisher`
are absent from the release. The controller separately verifies the
Ed25519 signature, repository identity, sequence, current expiry, package
architecture and exact executable payload metadata against both build receipts.
It retains the two signed indexes and signature/object proofs. This tests
native compilation, packing and publication under ordinary account permissions;
repository enrollment, package installation and sandboxed installed-app launch
remain separate qualification gates. No production signing key is used.
The full compiler/package gate uses 600-second command deadlines and a
2400-second guest deadline. The selected qualifier command budget is recorded
and independently checked in its report; other guest runs retain 900 seconds.

To rebuild V inside the guest before the project builds, set
`VINIX_DEVELOPMENT_SELFHOST_V=1` on the complete SDK/V/BusyBox invocation:

```
VINIX_DEVELOPMENT_SELFHOST_V=1 tests/development/run-guest aarch64 /path/to/kernel /path/to/staged-tools /path/to/new-state /path/to/aarch64-linux-musl-native /path/to/vlang /path/to/native-static-busybox
```

The prepared native V bootstrap translates its pinned `/usr/lib/vlang/cmd/v`
sources to C, exits, and then native GCC builds a static compiler with the
pinned runtime objects. The rebuild selects the C backend and omits unqualified
FastC, WebAssembly, native ARM code generation and interpreter backends through
the compiler's existing feature defines. Those backends retain separate gates.
Separate processes release the GC-free bootstrap's AST before GCC and the
assembler need memory. Each workspace copies the pinned installation and
replaces its compiler with the rebuilt executable beside its matching libraries
and help files. Each workspace gets its own rebuilt compiler;
the remaining V help, package, assertion and utility builds use that compiler.
Project builds select the pinned `/usr/lib/vlang` library root through
`VINIX_V_ROOT` and disable caches, so library-path constants and cached-object
filenames cannot introduce the workspace prefix into the resulting artifacts.
The runner checks its generated artifact pin before each execution. All 23
steps must pass, compiler versions must match the pinned `VERSION`, and the
generated C, rebuilt compiler and every other artifact must match across
workspaces. This mode gives the guest 8 GiB of RAM, build commands 1800 seconds
and the guest 7200 seconds; the reference-project qualifier retains its separately recorded
600-second budget.
The outer receipt records `selfhost_v`; invalid option values or a missing
complete SDK are refused before creating a state directory. Compiler sources,
runtime objects and libraries come from the pinned installation input, and
retain its recorded source adaptations. This checks a compiler rebuild and its
use to build projects; rebuilding every Vinix layer remains a separate gate.

On 13 October 2026 the self-host compiler gate passed as UID/GID 1000 on
AArch64 HVF. The 14-record receipt and transcript are retained in
`build/development17-20261013/guest-arm-selfhost-v-m`. Both fresh workspaces
completed all 23 steps. Their generated C, rebuilt compiler, project binaries,
payload, manifest and signed release matched exactly. The controller independently
verified the Ed25519 signatures and the 228648-byte executable payload. Selected
matching SHA-256s are:

| Artifact | SHA-256 |
| --- | --- |
| `selfhost-v.c` | `3a2cdc5fdd34b23a2e527db4c04f3f5d25ce7251196ab215ea4e24d0a4c4fc2b` |
| `compiler/v` | `4ef097b34415443a6e91bd19934a91ca6b4df9384e9b9c41b6dec6bcfc99dbac` |
| `package-bin` | `f72592db6d1a5cc97e897d0c02c75954a8016fed649f49d030ecf94c4bc7cf72` |
| `payload/bin/lscpu` | `8c2ba41f687c66f6b3602860f09bae79c19739ae81fc7453cdcd932c19b01f5f` |
| Package manifest | `0c6977d18ee94658c874999fc152c7756c41c039255793821709e9f50a987090` |
| `release/index.json` | `9eee3b494a6e92353520db3dd27f00a7fc06b3a1dbc8004ff10292bf91ba672b` |
| `release/index.sig` | `a6a852712b73b14757ba22be35293b535e79bf66d933b3962bf6f527b57e23c1` |

The run used V sources `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`,
GCC/G++ 11.2.1 (20211120), BusyBox 1.36.1 and the prepared installation from
`build/development17-20261013/native-v-arm-pinned`. The receipt records all
source, SDK, compiler and runtime pins; its committed Vinix source revision is
`116ba2c7850ca331a5bf9851470f1bae4a9136d3`. The isolated production kernel was
built from `776b9f0d3` plus the bounded metadata-budget policy in `116ba2c78`.
That policy preserves the previous limits through 4 GiB and allows the native
compiler on the 8 GiB development machine. Both production architectures built,
and native exact-budget exhaustion/recovery checks passed on both. The larger
existing C resource fixture still reaches its fixed mapping bound on both the
unchanged and updated kernels; see [the separate failing gate](../../docs/kernel-resources.md).

For prepared compiler startup/help coverage without a GCC SDK, set
`VINIX_DEVELOPMENT_V_SMOKE_ROOT` to the complete matching installation root:

```
VINIX_DEVELOPMENT_V_SMOKE_ROOT=/path/to/x86-vlang tests/development/run-guest x86_64 /path/to/kernel /tmp/development-x86 /tmp/new-v-smoke
```

The controller copies and pins the root and executable; UID 1000 executes help
and version and compares the reported revision with `VERSION`. The receipt
records `v_smoke_root_sha256` and `v-smoke`; the version output stays in the
transcript. This option is separate from the native V build gate and cannot be
combined with its V-root argument. Startup/help coverage does not qualify native
project compilation.

The x86_64 startup/help and account/job/build regression passed on 13 October
2026 in `build/development17-20261013/guest-x86-v-pinned` with the prepared root
in `build/development17-20261013/native-v-x86-pinned`. No native x86 GCC SDK was
supplied, so compiler rebuilding and project compilation on x86 remain open.

To run the CPU inspection check with a separately prepared `lscpu` ELF, set
`VINIX_DEVELOPMENT_CPU_BINARY` to its host path. The controller checks the
architecture, pins and copies the binary and records its hash as `lscpu-smoke`.
The same UID/GID 1000 procfs check runs without requiring a native compiler SDK:

```
VINIX_DEVELOPMENT_CPU_BINARY=/path/to/x86_64-lscpu VINIX_QEMU_CPU=Nehalem tests/development/run-guest x86_64 /path/to/kernel /tmp/development-x86 /tmp/new-cpu-state
```

`VINIX_QEMU_CPU` also selects the x86 QEMU model; the default remains `max`.
A prepared ELF check is execution coverage, separate from the native rebuild
gate above. The receipt records the actual QEMU argv and prepared binary hash.

`receipt.json` records the architecture, UID, kernel/fixture/tool hashes,
QEMU argv, passing verdict and 14 native plan/state/build receipts. SDK runs
also retain the SDK hash and native compiler report. `serial.log`,
the ISO and compiled fixture remain beside it. Credential values do not enter
the receipts. The credential in this fixture is public synthetic test data.
V runs additionally record `v_root_sha256`, `native_source_sha256`, the `v`/`sh`
executable pins, `native_source_revision`, the build plan, two native build
receipts and four signed-release proofs, for 22 native receipt records. The
compiler-rebuild run recorded above predates the six added lifecycle records
and two private-file records. Reference-SDK runs instead add five records for
a total of 19.
Once the initramfs archive is complete, its duplicate staging tree is removed
before ISO assembly. The standalone archive is removed once the ISO is complete.
The ISO, compiled fixture, receipts and transcripts remain; obsolete
images from earlier runs may be pruned independently of their retained evidence.

Command diagnostics retain the first and last 8191 bytes of long logs, checking
both blocks for the synthetic credential. A UID 1000 fixture puts distinct
sentinels at each end; both architectures must expose both markers. Failed
native builds also emit their receipt and bounded memory/limit/resource reports
before failing, preserving the executed command and artifact pins for diagnosis.

On 13 October 2026 these workflows passed on x86_64 and AArch64 using the
previously staged commands and isolated production kernels. Receipts are in
`/tmp/vinix-development-guest-x86-20261013-e` and
`/tmp/vinix-development-guest-arm-20261013-e`.
The extended build-plan runs passed in
`/tmp/vinix-development-build-x86-20261013-b` and
`/tmp/vinix-development-build-arm-20261013-b`; both architectures produced
artifact hash `8f62334d280332417efb4876a0690270b65488e01a24a4752f6e512653bb4cc9`.
The optional SDK run passed on AArch64 with GCC/G++ 11.2.1 (20211120) as
UID/GID 1000, including both reference project compile/run workflows. Its
receipt and compiler-version transcript are retained in
`/tmp/vinix-development-compilers-arm-20261013-c`.
Comparison with the fresh guest in `...-20261013-b` found matching SDK,
compiler and compiled-project hashes for the same project paths and build
epoch. The copied SDK hash is
`5286f56cfe9f709635fa20f38325376e541cc4283376887ed6abc67d3d3eb279`.
The extended controller's x86 job/build regression passed in
`/tmp/vinix-development-compilers-x86-base-20261013-a`.
No native x86 GCC SDK was supplied for a compiler-project run.

The C/C++/V run passed on AArch64 as UID/GID 1000 in
`/tmp/vinix-development-v-arm-20261013-a`, using the updated staged commands in
`/tmp/vinix-dev-aarch64-20261013-v-a`, GCC/G++ 11.2.1 and V 0.5.2. The prepared V
tree's `VERSION` identifies revision `9bfa1dc3f3455d5733d5c226662b6aaba8544f2c`;
its copied closure hash is
`f2a67e54f237e64cefba4f1935ca301f305a4186488677e68b926bf5ff1dc2ea`.
The receipt records the actual V executable and BusyBox hashes separately.
The x86 controller/fixture regression passed in
`/tmp/vinix-development-v-x86-base-20261013-a` without a compiler SDK.
This compiles a reference V project; rebuilding the V compiler itself and all
Vinix layers remains open.

The private build HOME/temporary-directory checks passed as UID/GID 1000 on
both architectures in `/tmp/vinix-development-home-arm-20261013-a` and
`/tmp/vinix-development-home-x86-20261013-a`, with the updated commands staged
in `/tmp/vinix-dev-aarch64-20261013-home-a` and
`/tmp/vinix-dev-x86_64-20261013-home-a`.

The utility rebuild run passed on AArch64 in
`/tmp/vinix-development-userland-arm-20261013-g`, with commands staged in
`/tmp/vinix-dev-aarch64-20261013-buffer-a`. Both fresh workspaces compiled and
executed `fetch`, `mount` and `chsh` as UID/GID 1000, retained complete receipts
and produced matching artifact hashes. This includes successful SDK/V/runtime
pin verification before and after each build. The extended x86 controller and
fixture regression passed without a compiler SDK in
`/tmp/vinix-development-userland-x86-base-20261013-a`.
The copied utility source hash is
`7640e3bca2b9b35861843fb5ee7ad453ac7d39ff1568379f3901e5060cc34b52`.
Both workspaces produced these artifact SHA-256s:

| Artifact | SHA-256 |
| --- | --- |
| `fetch-bin` | `516190cc02a02176ad45633c8cb3e30c8e98942015e3a5eea90525f2fd79cf7a` |
| `mount-bin` | `0808686c516603edbe08c1863727387b8e326c9d55d7ebb3a5298416093a2c2d` |
| `chsh-bin` | `45ca2c0c495d8d972ea094fceb9dfeb86197c7a00515bf7a449ccd447f63ff5d` |

Earlier diagnostics exposed Darwin/Vinix symlink-mode differences and retained
64 KiB stream buffers under `-gc none`. Canonical link modes and explicit
buffer release fix those runner failures; input pins are still verified.

The extended four-utility native rebuild passed on AArch64 in
`/tmp/vinix-development-lscpu-arm-20261013-a`, with the same staged commands
and SDK/V/runtime pins. Its source pin is
`1c2fead1fefb5b59f86f743202c719b4969865297feeb3ce400ef9a1e9e2c1c3`.
Both workspaces produced `lscpu-bin` hash
`82fbb5b623eabc581482befebc0dcb19f3b5b63ddd9a028e5f8c7b2d028fd9cf`
and retained the three other artifact hashes listed above. CPU inspection
matched the one online processor reported by this kernel's procfs; the boot
has no usable device tree and therefore does not enable ARM SMP. This source
snapshot precedes the separate `fetch` color and x86 CPU-count fixes.

Prepared ELF CPU checks passed as UID/GID 1000 on AArch64 in
`/tmp/vinix-development-lscpu-arm-smoke-20261013-a`, and on x86 with the AMD
`max` and Intel `Nehalem` QEMU models in
`/tmp/vinix-development-lscpu-x86-amd-20261013-a` and
`/tmp/vinix-development-lscpu-x86-intel-20261013-a`. The x86 checks each match
two online processor records and pin binary hash
`44d43664cdc98a20d7c57141e59ed00534e422d72eed2eab2d85042bb5b137a9`.
The old CPUID package-count implementation failed the same Intel CPU-count
gate in `/tmp/vinix-development-lscpu-intel-before-20261013-a`; using the OS
online CPU count fixes it. These x86 checks execute a cross-built ELF;
native x86 compiler qualification still needs a prepared native SDK.

The init-extended native rebuild passed in
`/tmp/vinix-development-init-arm-20261013-a`, using the same staged commands
and SDK/V/runtime pins. Both workspaces compiled and executed all four
utilities and `init`, completed all 11 steps and reverified every input pin.
The source pin is
`658a5fc75c5cd5fa7a07afa63a776cd5a6881927a9ca3ea2250fbb5ac7e4da0b`.
This includes the current `fetch` color and x86 CPU-count source changes.
Both workspaces produced `init-bin` hash
`f8b6c9a30c3cfcd5cc6e4eeda2facb00d77afb6fb15c935ee7601403ce02a05c`
and updated `fetch-bin` hash
`c4995938f7b4c73c9eb78540b760c944709fc1ad3e2cf84b509a7a5b51e87b46`;
the `mount`, `chsh` and ARM `lscpu` artifact hashes remained unchanged.
The x86 controller/fixture regression passed without a native compiler SDK in
`/tmp/vinix-development-init-x86-base-20261013-a`.
Both architectures also passed after moving duplicate staging-tree retirement
before ISO assembly, in `/tmp/vinix-development-prune-arm-20261013-a` and
`/tmp/vinix-development-prune-x86-20261013-a`.

The committed-source, native package and assertion-failure gates passed on
13 October 2026 with V source revision
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, staged with `VINIX_V_COPT=-O0`, and
the GCC/G++ 11.2.1 SDK. The AArch64 HVF run retained a passing 14-record receipt
and all 19 successful build steps per workspace in
`build/development17-20261013/guest-arm-package-assertions`. Its source revision
is `49070d4e39f4d4c64c7658a7f1e03492297b2ea0`, prepared-source pin is
`08e2fa118cb5eefd23ed5d13a096e55527d7f02d34c26dd88b155419da59f2d5`, copied
SDK pin is `ad1baf20e589e88e753cccbe863127d5e8e1cc9782d228dc956eaaff79ab8717`
and V installation pin is
`45468219a77a74bfb970078509adc707c46fc6df067483f828f0434c9cff55da`.
Both workspaces produced package-CLI hash
`481b5f11b1865ee462cb02cb9d5353bbc04ba8167606a8aac0b7ae9fede02a2d`, `lscpu`
payload hash `8c2ba41f687c66f6b3602860f09bae79c19739ae81fc7453cdcd932c19b01f5f`
and release-index hash
`9eee3b494a6e92353520db3dd27f00a7fc06b3a1dbc8004ff10292bf91ba672b`.
The real assertion project exits 1 with its relative source filename and
line 2 in both workspaces, and its binary hash also matches. The x86 TCG
prepared-compiler help/version and account/job/build regression passed in
`build/development17-20261013/guest-x86-v-assertions`. That run pins V compiler
`1ca3d612caf39e057b18ffe78be4d4c1f790e272aa82d8e9276ab37f9b340326` and
installation `4d83946b8ab4d99ac938c96da5d72668835abbaca7d18d8dc63f1b689e7d1853`;
it does not run native compiler projects without an x86 SDK.

This qualifies the tested per-account job workflows in Vinix guests, including
the native watcher, signal, deadline and interruption checks recorded above.
The optional native Services broker lifecycle is covered above. Graphical
service control, persistent-home cold boot, broader server/SSH/CI projects and
complete self-hosted builds remain open acceptance work.
