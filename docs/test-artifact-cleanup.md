# Unpublished test artifact cleanup

On 2026-10-24, generated execution evidence was removed from 363 unpublished commits. Test programs, fixtures, runners, checkers, handwritten source snapshots and short reports were retained. Every rewritten commit tree was compared with its original: all changes were deletions from the artifact inventory; all other paths and bytes were identical. Existing working edits were preserved.

- Published base (unchanged): `ffb1fc5b87660104de4c268804cf1fb2d8afe4bc`.
- Original local tip: `bf48da1b9f10d3cfb749fefd4371a9a5a16af033`.
- Filtered local tip: `e65761034cf3c915be9a28d45ed8879998a2ddc6`.
- Artifact paths removed across unpublished history: 13594.
- Outgoing objects before: 3891446916 bytes; after: 124542147 bytes (uncompressed).
- Source-only Git bundle: 2885192 bytes; actual push packing may differ.

The complete original unpublished history is preserved locally outside Git at:

```text
/Users/alex/code/vinix-artifacts/source-cleanup-20261024-bf48da1b9f10/original.bundle
SHA-256: fc46ec33a5ebb98a32fc6bdfcf3aed9bf8fe0cf36a1cff4bf296a943797c8674
```

The backup directory also contains the commit mapping, removed-path inventory, original base and tip, and snapshots of working edits. The bundle requires the published base above. The local backup ref is recorded in `backup-ref.txt`; do not push backup refs. See [test artifact storage](test-artifacts.md) for restoration and auditing. Historical result links require the complete original evidence bundle.
