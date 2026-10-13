# Upstream generator SDK prerequisites

`build-support/generator-sdk qemu|virgl EXECUTABLE` uses V to inspect an already
provisioned generator SDK. It prints the selected absolute executable path,
preserving its environment prefix even when the executable is a symlink.
It never runs an interpreter, imports a module, creates an environment or invokes
a package installer.

Provision these external SDKs before requesting a fresh build:

| Builder | Default SDK entry point | Override | Required distributions |
| --- | --- | --- | --- |
| `scripts/build-qemu-input.sh` | `build/qemu-horizontal/python/bin/python3` | `VINIX_QEMU_BUILD_PYTHON` | tomli 2.2.1 |
| `build-support/virglrenderer/build-host.sh` | `build/virglrenderer-tools/bin/meson` | `VINIX_VIRGLRENDERER_MESON` | Meson and PyYAML |

Use an isolated Unix SDK layout with `bin/` and one
`lib/python3.<minor>/site-packages` directory; `lib64/` is accepted too.
Distribution `METADATA` must declare the correct Name and Version, and the
corresponding module entry files must exist. Duplicate distributions or distinct
site-packages directories are rejected. QEMU retains the previous tomli version
pin. VirGL's previous unpinned Meson/PyYAML requirements remain unpinned.
Existing SDK environments can be reused by selecting their entry points.
The callers report a missing prerequisite rather than installing packages.

The upstream QEMU configure script and VirGL Meson executable continue to use
their external generator runtimes during an actual build. Metadata checks
establish declared prerequisites; they do not prove runtime importability.
The source patch/download pins and upstream build flags stay in the callers.
Already stamped build outputs retain their existing cache behavior.

Qualify the V checker and developer-tools module probe:

```sh
build-support/run-v-tool.sh build-support/qualify-generator-sdk.v \
  /path/to/qualified/v /fresh/evidence arm # also x86 or san
```

The qualifier cold-builds the checker, its inert SDK model and the CPython smoke
qualifier. The latter cold-builds the smoke CLI, ownership/lifecycle model and
guest producer, then builds both real musl guest ELFs and checks staged runtime
exports as data. The SDK fixtures cover spaces/Unicode paths, symlinked
executables, distribution/version mismatches, invalid UTF-8, duplicate metadata,
missing modules, aliased lib directories and ambiguous layouts. No interpreter,
upstream generator, target ELF or Vinix guest executes during qualification.
