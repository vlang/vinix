The historical allocation benchmark sources are recorded in
[source-archive.json](source-archive.json). Each entry gives the original
commit, path, Git blob ID, SHA256, byte count, file mode and evidence kind.
The independent C fixtures and compiler output remain exact historical
evidence in Git; this archival change receives **zero translation credit**.
The patched upstream musl snapshots remain in the checkout, with the same
provenance and byte checks.

Verify every source object and retained musl snapshot:

```sh
tests/alloc-bench/materialize-evidence verify
```

Recover original C fixtures and compiler output outside the checkout:

```sh
tests/alloc-bench/materialize-evidence materialize \
  --output /tmp/vinix-allocation-evidence
```

Add `--path <manifest-path>` to recover selected files. To inspect a complete
historical campaign, recover its original relative source files, scripts and logs:

```sh
tests/alloc-bench/materialize-evidence materialize \
  --output /tmp/vinix-allocation-evidence \
  --snapshot 2026-10-03-userspace-v6
```

Complete snapshots preserve the original scripts rather than modifying their
captured behavior. Machine-specific dependencies and VM images mentioned by
old drivers must still be supplied; recovering sources does not recreate
missing binaries or make old runs fresh validation. Current V recomputation
tools recover the original benchmark and comparator bytes directly from Git
for provenance checks. Archived scripts are evidence
and are never imported or executed by the maintained tools. The native ports
retain the strict source hashes, capture checks and timing assertions; see
[native qualification](../native-reports.md).

The `recover` argument array in any manifest entry also reproduces that
source directly with `git show <commit>:<path>`. The helper verifies the blob,
size and SHA256 before writing and refuses to overwrite changed evidence.
