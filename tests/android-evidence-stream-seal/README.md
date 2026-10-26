# Streaming external evidence seal

This macOS host tool uses CommonCrypto for bounded native SHA-256 reads.
Build with Boehm GC and run the mutation tests before sealing:

```
v -new-compiler -prod -gc boehm -o /external/seal tests/android-evidence-stream-seal/main.v
/external/seal --self-test
/external/seal seal --out /external/fresh-output --roots /external/canonical-roots.txt
/external/seal check --out /external/output --pin MANIFEST_SHA256
```

The root-list file contains one canonical absolute path per line (at most 1 MiB).
The small pinned manifest binds one sorted, typed NDJSON inventory per root and
the exact output contents. Checks regenerate each inventory in temporary storage
and compare its count and native streaming SHA-256. File reads use a 1 MiB buffer;
only one directory's sorted names are retained at each traversal level. Limits
are 1,024 roots, 100,000 names per directory, 128 directory levels and a 16 MiB
manifest. Files, modes, literal symlinks and empty directories are bound. Special
objects, overlapping roots and evidence changes during reads are rejected.

Quiesce every writer before sealing. This is a trusted-host integrity inventory,
not a hostile-concurrency guarantee, archive, VM-ownership check, application
result or qualification to delete evidence. It does not resolve symlink targets.
The original complete bundles and their historical auditors remain required.
