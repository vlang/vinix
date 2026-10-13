# Native development tools

The commands are `vinix-build`, [vinix-qualify](qualification.md),
[vinix-vm](virtual-machines.md) and [vinix-jobs](scheduled-jobs.md).
All implementations, staging and tests are V.
See the [workstream status](../../docs/development-containers-virtualization.md)
for the remaining section 17 implementation and guest acceptance work.

Create a static development-tools overlay for either supported architecture:

```
v -gc none -cc cc run tools/development/stage.v aarch64 /path/to/new-staging
v -gc none -cc cc run tools/development/stage.v x86_64 /path/to/another-new-staging
```

The default compiler is `ARCH-linux-musl-gcc`. A third argument can provide
a JSON compiler argv, for example `["/usr/bin/clang","--target=aarch64-linux-musl","--sysroot=/path/to/sysroot","-fuse-ld=lld"]`.
The stager builds the four commands under `usr/bin`, checks the ELF architecture,
and writes compiler pins, argv and binary hashes to `development-tools.json`.
Only a receipt with `complete: true` is a finished overlay. Failed builds retain
their generated sources and logs under `.build`. Stage into a new directory;
publish or install the overlay through the existing package workflow. The stager
does not modify the running system. Commands refuse mismatched real/effective
account IDs and are installed mode 0755, without set-ID bits.

Prepare a matching native V compiler and standard-library closure from an
existing V Git checkout:

```
v -cc cc run tools/development/stage-v.v aarch64 /path/to/v-checkout /path/to/new-v-arm
v -cc cc run tools/development/stage-v.v x86_64 /path/to/v-checkout /path/to/new-v-x86
```

This V stager exports production files from the checkout's full `HEAD` commit
using immutable Git blobs and verifies every blob ID and size. Dirty and
untracked files do not enter the closure. Selected symlinks and special files
are refused; Python sources/helpers, test fixtures and host TCC installations
are excluded before their blobs are read. The checkout needs Git objects for
the selected commit; no network fetch runs. `vlang/VERSION` records the commit.
Committed help-topic text files are retained for the native compiler's help CLI.

Before translation, two V source adaptations make the exported installation
portable: standard-library discovery prefers the running executable's resolved
installation root, and the compiler revision is stamped from the pinned commit
because the export has no `.git` directory. The receipt records each source
file's original/resulting SHA-256 and the complete patched-source tree hash.
An unfamiliar or ambiguous source layout is refused rather than partly patched.

The C backend also retains assertion diagnostics without embedding a changing
workspace prefix: when `SOURCE_DATE_EPOCH` is set, project source filenames in
assertion failures are relative to the compiler's working directory. Line
numbers, expressions, assertions, explicit `#line` filenames and paths outside
that directory retain their meaning. This adaptation is recorded with the
other source hashes. Build each project from its source root.

`VINIX_V_ROOT` can select an absolute, complete V library installation separately
from the executable's location. Invalid roots are refused. Pin that installation
as an SDK input in a build plan. This keeps `@VROOT`/`@VEXEROOT` library paths
stable when a newly rebuilt compiler runs from different private workspaces;
the running compiler's executable pin still identifies the tool actually used.

The host V compiler translates that committed compiler source, then the selected
musl C compiler builds a static native compiler and the adjacent runtime objects
needed by the reference projects. These include process capture, pthreads,
compiler profiling/file metadata and the Linux signal handler. The installed
compiler reports the source commit. `native-v.json` records the source-tree,
generated-C, helper-object, executable and complete-installation hashes, host
compiler pins and every translation/compile/link argv. The fourth argument can
override the C compiler with a JSON argv, using the same default as `stage.v`.
`VINIX_V_COPT` selects `-O0`, `-O1` (default) or `-O2` for the compiler object;
the chosen option is retained in its compile argv. Automatic V compiler bug
uploads are disabled in the staging command environment.
Only `complete: true` represents a completed installation. After source export,
the receipt remains at the staging root and command logs/generated files remain
under `.build`, including on failure. Compiler commands have deadlines;
also preserve the C compiler's subprogram, header and library closure, since an
executable pin alone does not identify a complete bootstrap SDK.

Supply the resulting `vlang` root to the
[native guest checks](../../tests/development/README.md). Pin the entire root
when using it in an installed-system build plan. This prepares a host bootstrap
compiler; rebuilding that compiler inside Vinix and qualifying every V external
tool, default garbage collector and package-manager workflow remain separate
acceptance work.

On 13 October 2026 both architecture stages completed using V source commit
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c` and musl GCC 14.2.0. They share
production-source pin
`93080ab17dbc7f21dbe8a89bb74ab511b02f6360d75e948f3026d11dd94463a8`.
Historical stage receipts and logs are retained in
`build/development17-20261013/native-v-arm-final` and
`build/development17-20261013/native-v-x86-final`. Native execution/compilation
acceptance is recorded separately by the guest controller.

The portable stages with all three source-file adaptations and `VINIX_V_COPT=-O0`
completed in `build/development17-20261013/native-v-arm-qualified` and
`build/development17-20261013/native-v-x86-qualified`. Their patched-source pin is
`918bec26b18f9205f63b3498d90c2df3d57fdd02e17b87caf92e3d63b62233f1`.
The x86 UID 1000 version/help gate passed in
`build/development17-20261013/guest-x86-v-smoke-b`, reporting
`V 0.5.2 f6358ec`; compiler-project acceptance still requires a native GCC SDK.

The stages including the assertion-path adaptation completed in
`build/development17-20261013/native-v-arm-repro` and
`build/development17-20261013/native-v-x86-repro`. Their patched-source pin is
`52fcbeedc7e63e13aaaac79bc870aa274ef17e1a87683541001a648fe8f21d46`.
The x86 UID 1000 startup/help gate passed in
`build/development17-20261013/guest-x86-v-repro`. The AArch64 native compiler,
userland and signed-package reproducibility gate passed in
`build/development17-20261013/guest-arm-package-repro`; it builds the same
package CLI and payload in two different workspace paths and independently
verifies their matching hashes and release signatures.

The stages with explicit library-root selection completed in
`build/development17-20261013/native-v-arm-pinned` and
`build/development17-20261013/native-v-x86-pinned`, with patched-source pin
`19ca2b8fb88459cc615a93ba8fceba54f7e4eb2109336c6d452617740b85a0b7`.
The AArch64 guest rebuilt the C-backend compiler in two fresh workspaces and
used those matching compilers to build identical userland and signed packages
in `build/development17-20261013/guest-arm-selfhost-v-m`. The x86 version/help
and bounded diagnostic-log regression passed in
`build/development17-20261013/guest-x86-v-pinned`.

Older generated-source scratch, test images and redundant bootstrap
installations may be pruned after retaining their receipts and transcripts.
The current `native-v-arm-pinned/vlang` and `native-v-x86-pinned/vlang`
installations remain available in the workstream state directory.

For additional native build-system qualification, [stage-cmake.v](stage-cmake.v)
assembles a reference SDK from a prepared compiler/Ninja/shell prefix and native
developer-package overlay. It imports CMake and its modules, follows the ELF
shared-library dependency graph, records source/output pins and preserves the
compiler's musl and shared libgcc inputs. The [guest reference gate](../../tests/development/README.md)
qualified its resulting CMake 3.31.1 SDK on AArch64 in two private workspaces as
UID/GID 1000. This is developer test staging; public package distribution and
wider toolchain/platform qualification retain their own workflows.

`vinix-build` is a V build runner for installed Vinix systems and build hosts.
It runs a pinned build plan in a new private workspace, preserves source links
and permissions, sets `SOURCE_DATE_EPOCH`, and records command results and output
SHA-256s. It stops on the first failure and retains logs and a failed receipt.
Each build gets new mode-0700 `home` and `tmp` directories inside its private
output, selected as `HOME` and `TMPDIR` for compiler caches and temporary files.
A plan can explicitly override those environment values when a shared cache
is intended. Other inherited environment credentials remain omitted.
Commands receive argument arrays, never an implicit shell. Each command has a
deadline; the command owner retires its process group before reaping it.

Build the runner with the installed V compiler:

```
v -gc none -cc gcc -o vinix-build tools/development/build.v
./vinix-build hash /path/to/prepared-source
./vinix-build hash /usr/lib/vlang/v
./vinix-build build plan.json /path/to/new-result
```

The source must be a prepared closure, including dependencies. Export a committed
revision with Git's archive command and materialize the pinned dependencies from
`kernel/get-deps` inside it before hashing. Include the matching ui2 sources for
the desktop. Internal relative symlinks are preserved; links escaping the closure
and special files are rejected. Directory and regular-file permissions are part
of each tree pin; symlink modes use canonical 0777 because Darwin's
umask-dependent modes differ from Vinix's
reported modes. Link targets remain pinned and escaping links remain errors.
Recompute tree pins made by older tools on Darwin if they include symlinks.
The build runs on a copy and rechecks the source, tools and additional SDK inputs
after completion. It performs no downloads or installation. Run it as the
developer's account with the permissions that account
already has. A build plan is executable code supplied by that developer.
File hashing releases each stream buffer after use, including in `-gc none`
builds, so scanning large SDKs does not retain a buffer per file.

A plan has this shape (replace paths and hashes with actual values):

```json
{
  "schema": 1,
  "source": {"path": "/home/developer/source", "sha256": "SOURCE_HASH"},
  "inputs": [{"path": "/usr/lib/vlang/vlib", "sha256": "VLIB_HASH"}],
  "tools": {
    "v": {"path": "/usr/lib/vlang/v", "sha256": "V_HASH"},
    "make": {"path": "/usr/bin/make", "sha256": "MAKE_HASH"},
    "cc": {"path": "/usr/bin/gcc", "sha256": "GCC_HASH"},
    "ar": {"path": "/usr/bin/ar", "sha256": "AR_HASH"}
  },
  "epoch": 1700000000,
  "timeout_seconds": 3600,
  "environment": {"V": "{v}", "CC": "{cc}", "VJOBS": "1"},
  "steps": [
    {
      "name": "kernel",
      "directory": "kernel",
      "argv": ["{make}", "ARCH=x86_64", "V={v}", "CC={cc}", "AR={ar}", "KERNEL_LINK_RANDOMIZE=0"],
      "artifacts": ["kernel/bin/vinix"]
    },
    {
      "name": "userland",
      "directory": "util-vinix",
      "argv": ["{make}", "V={v}", "CC={cc}", "VFLAGS=-gc none -os vinix"],
      "artifacts": ["util-vinix/chsh/chsh", "util-vinix/fetch/fetch", "util-vinix/mount/mount", "util-vinix/lscpu/lscpu"]
    },
    {
      "name": "init",
      "argv": ["{v}", "-os", "vinix", "-gc", "none", "-cc", "{cc}", "-o", "{work}/vinix-init", "{work}/init"],
      "artifacts": ["vinix-init"]
    },
    {
      "name": "package-cli",
      "argv": ["{v}", "-new-compiler", "-nocache", "-no-retry-compilation", "-no-parallel", "-no-memory-limit", "-os", "linux", "-musl", "-gc", "none", "-cc", "{cc}", "-path", "@vlib|{work}", "-o", "{work}/vinix-package", "{work}/tools/packages/main.v"],
      "artifacts": ["vinix-package"]
    }
  ]
}
```

Use `ARCH=aarch64` and a pinned `LD_AARCH64` for the ARM kernel. Include C
compiler subprograms, headers, libraries and linkers as additional pinned inputs;
pinning a compiler executable alone is not a full toolchain closure. Plans can
add native generators, desktop translation/link commands and package archive
commands as further steps. `{work}`, `{output}`, and pinned tool names are the
only substitutions. Artifacts are paths relative to the copied source root.
JSON uses strict type conversion. Unknown substitutions, escaped paths and
unpinned top-level executables are errors. A later step can execute `{work}/ARTIFACT` produced by
an earlier step; its recorded hash is checked before execution. This supports
building generators, running them and testing the exact resulting binaries.
Output directories must be new.

For reproducibility, use two fresh output directories and compare the artifact
hashes in their receipts. This runner records inputs and outcomes; it does not
claim bit-for-bit reproducibility of an unqualified compiler. The current native
desktop needs the same staged ui2, generated GPU/execinfo modules and runtime
sources as the architecture desktop builders. A full installed-system rebuild
of the kernel, desktop and all Alpine packages remains unqualified.

Host integration tests run with `v -cc cc test tools/development/devcore`.
They build and execute a real V project, reject changed pins and escaped links,
preserve modes, retain failure receipts and enforce command deadlines. These
checks also compile a `-gc none` hash probe and bound peak-memory growth across
1,000 full-buffer hashes. The stream-buffer regression measured approximately
79 MiB of growth before the fix and 1 MiB after it on the Darwin ARM host.
These host checks do not establish Vinix guest qualification.
