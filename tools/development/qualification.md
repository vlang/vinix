# Developer workload qualification

`vinix-qualify` builds and executes small real projects using installed tools.
It records OS/architecture, UID, the runner hash and each invoked executable's
hash, argv, exit status and log. The output distinguishes `passed`, `failed` and
`unsupported`; any selected profile that does not pass makes the command exit 1.
It never reports a startup/version check as a completed project.

```
v -gc none -cc gcc -o vinix-qualify tools/development/qualify.v
./vinix-qualify --require-vinix /home/developer/new-results
./vinix-qualify --require-vinix /home/developer/cpp-results c,cpp,v,make,cmake,ninja
```

Each output directory must be new. The runner gives each project a private
HOME, temporary directory and package-manager cache, with a fixed build epoch.
Cargo and npm use offline operation, and Go disables proxy, checksum-service
and automatic toolchain downloads. It ignores external Go environment files,
trims workspace paths and omits VCS stamping from the project build. No system
package is installed. Compiler invocations and test
executables use bounded owned child processes. Logs remain private under the
result directory; inherited environment credentials are omitted.

Each command has a 120-second default deadline. Set
`VINIX_QUALIFY_TIMEOUT_SECONDS` to an integer from 1 through 86400 for larger
projects or emulated guests. Invalid values are rejected before output creation;
`report.json` records the selected command budget. Expiry retires the owned
process group and retains a failing command receipt. Automatic V compiler bug
uploads are disabled in project command environments.

| Profile | Workflow |
| --- | --- |
| C / C++ | Compile with symbols, create/join a thread, use collections (C++), write and read back a file, execute the resulting binary. |
| V | Compile the project with the installed native C compiler, use an array, write/read a file and execute the exact binary. |
| Rust / Cargo | Compile or build offline, run a thread, use a vector, write/read a file and execute the exact binary. |
| Go | Build, communicate with a goroutine through a channel, write/read a file and execute the exact binary. |
| Java | Record JDK/JAR versions, compile, create an executable JAR with fixed entry timestamps, run it, join a thread and write/read a file. |
| JavaScript / TypeScript | Run Node file/crypto checks; compile strict typed code with tsc and execute its JavaScript. |
| GNU make / CMake / Ninja | Build and execute the same C thread/file project through each build system. |
| npm | Pack a local dependency, install its archive offline with scripts disabled, and resolve it from the real Node project. |
| GDB | Compile a child with symbols, break at main, run, obtain a source-level backtrace and continue to the success marker. No attach to another user's process or permission override. |
| SQLite | Commit and roll back transactions, reopen the database, check integrity and validate the retained row. |

`--require-vinix` rejects a host OS before creating output. Without it, host
checks are labelled `host-only`. An unsupported tool remains an open gate; a
failing native debugger does too. This suite adds repeatable compiler/project
coverage, not complete IDE, package ecosystem, profiler or production-server
qualification. Existing [Go](../../tests/go/README.md), [Java](../../tests/java/README.md),
[developer-tool](../../tests/developer-tools/README.md) and
[Linux application](../../docs/linux-posix-qualification.md) suites provide
additional coverage at their recorded revisions.

Inside Vinix, the V profile explicitly selects the Vinix/musl target and the
native architecture, uses V3 with serial workers, and disables compilation
retry. These match the installed compiler's defaults even when `v` resolves
directly to the compiler rather than its shell wrapper. The profile still
invokes the selected native C compiler and executes the resulting binary;
compiler startup alone cannot pass it. Host V invocations retain their host
target settings.

The [V guest controller](../../tests/development/README.md) can stage a prepared
native musl GCC SDK and run the C/C++ projects as UID/GID 1000. Supplying a
prepared native V root and BusyBox adds the V compile/run project. It preserves
SDK/V closure hashes, compiler versions and the native report, and independently
checks the runner/compiler hashes and the successful compile/run receipts.
Other profiles retain their own acceptance gates; supplying this SDK does not
qualify the complete catalog or IDE workflows.

The guest controller also accepts a separate prepared reference prefix through
`VINIX_DEVELOPMENT_REFERENCE_SDK`, with an explicit comma-separated
`VINIX_DEVELOPMENT_REFERENCE_PROFILES` selection from `make,cmake,ninja,sqlite,node,go,java`.
Its [reference-mode instructions](../../tests/development/README.md) describe the
flat prefix, required tool entries and native runtime closure. Each selected
workflow runs twice as UID/GID 1000 through a pinned build plan. The controller
checks the exact plan, SDK/runtime and executable hashes, executed project argv,
native reports and matching project artifacts. Startup/version checks cannot
replace a project. AArch64 has passed GNU make, CMake, Samurai/Ninja and SQLite;
x86_64 has passed SQLite. AArch64 has also passed Go 1.23.9 native compilation
and execution with identical artifacts in both fresh workspaces. The remaining
reference-mode profiles are supported test gates awaiting native qualification,
alongside the wider catalog.

[stage-cmake.v](stage-cmake.v) prepares the CMake reference prefix from existing
compiler/Ninja/shell and developer-package inputs. It records the base closure,
modules, recursively inspected libraries and final SDK pins, excludes Python
helpers, and preserves the compiler's musl/libgcc inputs. CMake 3.31.1 passed its
native AArch64 configure/build/execute workflow in two fresh workspaces using
the exact maintained stage. The retained receipt covers this project and
compiler/runtime tuple; other CMake platform/project workflows remain separate.

[stage-go.v](stage-go.v) imports the matching Go installation and musl runtime
from an existing overlay without running its package builder. The relative
compiler alias lets Go discover its pinned standard library in the reference
prefix. Its native AArch64 gate validates the version, full SDK/runtime pins,
actual trimmed compile argv and exact executed artifact hash. This covers the
pure-Go reference project; x86 Go, cgo, wider modules and network/server projects
remain open.

[stage-java.v](stage-java.v) imports an existing native OpenJDK installation,
its ELF runtime dependencies and the supplied overlay's standard Java trust
store into a contained reference prefix. It preserves source-file/alias pins,
the imported JDK tree and full SDK hash. No package builder, network fetch or
Python helper runs. Java's [JAR entry date option](https://docs.oracle.com/en/java/javase/25/docs/specs/man/jar.html)
pins archive timestamps to the reference epoch; the gate requires matching
class, JAR and readback hashes across fresh workspaces, plus all six exact
version/compile/pack/run commands. The JAR tool must support the `--date` option;
native qualification here used OpenJDK 25.0.4.

`VINIX_QUALIFY_JIT=1` explicitly requests the existing Vinix W^X compatibility
mode for the Java-only profile. The standalone qualifier requires an already
[administrator-approved runtime mount](../../docs/mount-execution-policy.md);
it never grants approval itself. Invalid values, host contexts and other
profile selections are rejected before creating output. Reports retain
`jit_requested` and each actual `VINIX_ALLOW_WX` child-environment override.
Without this option, inherited W^X requests are omitted.

The disposable guest controller's separate
`VINIX_DEVELOPMENT_REFERENCE_JIT=1` option prepares the pinned JDK's
`/opt/reference/share/jdk` as a read-only `nosuid,nodev,wxallowed` self-bind
before dropping credentials. It proves UID 1000 requests fail before approval
and outside that mount, refuses ordinary-user remount/writes, and revokes
approval before checking another denied launch. This option requires only the
prepared Java profile. Approval applies to that test guest and does not install
or change production administrator policy.

Python and Python-based build tooling, including Meson, are not executed by this
runner because the repository requires V tooling and forbids running Python.
Their roadmap qualification remains open. Native ptrace/core dumping, kernel
stack sampling, rootless user/network namespace semantics and hardware-backed
Vinix VM hosting also remain open; this runner never changes authorization or
uses a sandbox-disable flag to turn one of those into a pass.

Run host integration checks with `v -cc cc test tools/development/qualcore`.
The host receipt is separate from a guest receipt and cannot satisfy an installed
Vinix acceptance gate.
