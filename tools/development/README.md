# Native development tools

`vinix-build` is a V build runner for installed Vinix systems and build hosts.
It runs a pinned build plan in a new private workspace, preserves source links
and permissions, sets `SOURCE_DATE_EPOCH`, and records command results and output
SHA-256s. It stops on the first failure and retains logs and a failed receipt.
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
and special files are rejected. The build runs on a copy and rechecks the source,
tools and additional SDK inputs after completion. It performs no downloads or
installation. Run it as the developer's account with the permissions that account
already has. A build plan is executable code supplied by that developer.

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
      "argv": ["{v}", "-os", "linux", "-gc", "none", "-cc", "{cc}", "-path", "@vlib|{work}|{work}/tools/accounts", "-o", "{work}/vinix-package", "{work}/tools/packages/main.v"],
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
Unknown JSON fields and substitutions, escaped paths and unpinned top-level
executables are errors. A later step can execute `{work}/ARTIFACT` produced by
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
host checks do not establish Vinix guest qualification.
