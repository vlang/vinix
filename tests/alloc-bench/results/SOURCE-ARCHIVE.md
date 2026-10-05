The historical allocation benchmark sources are recorded in
[source-archive.json](source-archive.json). Each entry gives the original
commit, path, Git blob ID, SHA256, byte count, file mode and evidence kind.
The independent C fixtures and compiler output remain exact historical
evidence in Git; this archival change receives **zero translation credit**.
The patched upstream musl snapshots remain in the checkout, with the same
provenance and byte checks.

Verify every source object and retained musl snapshot:

```sh
python3 tests/alloc-bench/materialize-evidence.py verify
```

Recover original C fixtures and compiler output outside the checkout:

```sh
python3 tests/alloc-bench/materialize-evidence.py materialize \
  --output /tmp/vinix-allocation-evidence
```

Add `--path <manifest-path>` to recover selected files. To replay frozen
drivers against their original relative source files, recover a complete
campaign, including its original scripts and logs:

```sh
python3 tests/alloc-bench/materialize-evidence.py materialize \
  --output /tmp/vinix-allocation-evidence \
  --snapshot 2026-10-03-userspace-v6
```

Complete snapshots preserve the original scripts rather than modifying their
captured behavior. Machine-specific dependencies and VM images mentioned by
old drivers must still be supplied; recovering sources does not recreate
missing binaries or make old runs fresh validation. Current recomputation
scripts recover the original benchmark bytes directly and retain the strict
source hashes, capture checks and timing assertions.

The `recover` argument array in any manifest entry also reproduces that
source directly with `git show <commit>:<path>`. The helper verifies the blob,
size and SHA256 before writing and refuses to overwrite changed evidence.
