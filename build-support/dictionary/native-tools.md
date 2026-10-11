# Native Dictionary preparation

`prepare.v` calls `dictionarycore` directly. Two Python files, totalling 8,204
original bytes and 176 lines, are retired; their blobs and hashes are recorded in
[the receipt](native-translation.json). No Python executes during qualification.
The utility workflow's two Python source-processing blocks are also replaced
with `utilitysource` V. Both desktop image builders invoke the native preparer,
and the desktop image key includes the preparer and command-owner sources.

The native encoder preserves sorted UTF-8 headwords, little-endian records,
contiguous offsets, text bounds and control-character rejection. WordNet parsing
preserves sense order, deduplication, adjective markers and license bytes. Native
download ownership bounds output and deadlines, verifies the pinned SHA-256 before
publishing the archive, and retires its process group on interrupts. Output
writes preserve atomic replacement, read-only mode and failure cleanup.

Eighteen cold builds and the native fixture, utility-source and cache suites pass
on ARM64, Rosetta x86_64 and ARM ASan/UBSan with V `4eb8f2b`. In each profile the
real pinned archive produces exactly the existing 147,306-headword, 30,349,544-byte
lexicon and unchanged license. The lexicon SHA-256 is
`69a8a9e9ce5cbfce4b6942ac2038dca24ff2545de62d06330035c33a931c32ee`.
Native curl fixtures cover failed, wrong, oversized and valid downloads,
SIGINT/SIGTERM, descendant retirement and preservation of prior outputs. One
hundred atomic writes keep descriptors exactly flat in each profile. Sanitizers
check invalid accesses and undefined behavior with leak detection disabled.

The public utility workflow successfully stages the software presenter and runs
all 442 model tests: 421 pass and 21 fail. An independent V reconstruction of the
frozen source-processing procedure produces exactly the native merged source
and reproduces the same 21 failures. They include existing application-catalog,
document-path and localization expectations. No assertion is removed or relaxed.
The workflow stops at those failures, so this stage does not claim completion of
its later memory and IPC checks. A SDK read-count cast permits the maintained
terminal reply assertion to compile. Presenter option parsing is fixed separately
in `e8eb94f3`, with rejection tests and real presenter staging.

These are host tooling checks; no fresh desktop image, kernel build or QEMU boot
is claimed. Originals, output digests and qualification records are retained
under `~/.cache/vinix-dictionary-native-20261012/`; temporary builds are under
`/Volumes/VinixPythonDeviceScratch/dictionary-20261012/`.
