# Desktop performance and startup smoke tests

`run.py` compares static AArch64 desktop builds in one QEMU boot. It measures each
scenario for every build and alternates build order between rounds. The default
scenarios are `idle,apps,pointer,drag`; use `--scenarios` to select a subset.

```sh
python3 tests/desktop-perf/run.py new=/path/to/vinix-desktop \
  --scenarios=idle,apps,drag --rounds=1 --settle=3 --seconds=5 \
  --shots=/tmp/vinix-perf-shots --json=/tmp/vinix-perf-results.json
```

`--initramfs=PATH` selects a cached desktop image. `VINIX_KERNEL_DIR` selects an
existing kernel build. The harness stages the requested desktop binaries through
the guest overlay and keeps its serial log, JSON, and requested screenshots. It
removes temporary VM disks and overlay files after a run, including failures.
A missing measurement, malformed metric, missing completion marker, timeout,
guest error, or panic fails the run while preserving partial results.

The optional native scenarios are:

| Scenario | Requested clients | Minimum measured processes |
| --- | --- | --- |
| `utilities` | Preview, Console, System Information | 4 |
| `storage` | Archive Utility, Disk Utility, Backup | 4 |
| `productivity` | Notes, Reminders, Grapher | 4 |
| `tools` | Color Meter, Calculator, Notes | 4 |
| `workflows` | Dictionary, Text Editor, Calendar, Files | 5 |

Counts include the compositor. These scenarios install the native executable
aliases in the guest so older cached images can launch the current clients.
They open the applications and leave them idle for startup, rendering, CPU and
memory checks. Review `--shots` output alongside the measurements. Application
operation and persistence checks also run in `desktop/tools/test-new-utilities.sh`.

`workflows` requires `--dictionary-data=DIR`, pointing to already-prepared local
`dictionary.vnd` and `LICENSE.WordNet`. The harness checks regular files, the
portable format header, payload length and size bounds, then copies both files
unchanged into `/usr/share/vinix/dictionary` through the VM overlay. This supplies
the offline lexicon even when a cached initramfs predates Dictionary. The harness
never prepares or downloads dictionary data.

```sh
python3 tests/desktop-perf/run.py new=/path/to/vinix-desktop \
  --scenarios=idle,apps,workflows,drag --rounds=1 --settle=3 --seconds=5 \
  --dictionary-data=build/dictionary/staged \
  --initramfs=/path/to/cached-desktop-initramfs.tar \
  --shots=/tmp/vinix-workflow-shots --json=/tmp/vinix-workflow-results.json
```

The desktop image builders prepare these assets. To prepare them separately
without a download, supply an existing verified WordNet archive explicitly:

```sh
python3 build-support/dictionary/prepare.py \
  --archive=/path/to/WordNet-3.0.tar.gz --destination=build/dictionary/staged
```

See [Dictionary data preparation](../../build-support/dictionary/README.md) for
the pinned archive and preserved license. Captured-transcript parsing, coverage,
metric validation, partial JSON and
summary policy run in `perfreport` V. The remaining Python controller uses a
small import bridge that compiles one private executable with `find-v.sh` and
owns each request process through completion. `VINIX_PERF_REPORT_QUERY` can
select an already-compiled native executable. Both native verdict fixtures and
the remaining controller contracts run with
`tests/desktop-perf/run-host-tests.sh`; `sh -n tests/desktop-perf/perf-init.sh`
checks the guest script without booting QEMU.
