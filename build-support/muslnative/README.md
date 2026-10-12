# Native musl staging

`build-support/musl/stage` compiles `stage.v` and runs this V implementation.
The saved `production-packaging-v3/stage` command invokes `legacy.v`, retaining
that script's original support directory and cache-root defaults. Both accept
`--support-dir` to select an explicit immutable recipe. The current command
also supports private patches, ELF page alignment and required runtime exports.

The plan verifies ELF architecture, the original nonoverlapping version scan,
compiler identity and every Alpine patch. Canonical ASCII JSON preserves the
original cache keys. The owner locks the cache, checks the pinned source release,
validates archive names and links, snapshots patches, builds with the original
GNU recipe, and checks cache hashes and existing exports before publication.
Files and links use SDK rename so destination links are replaced atomically.
Cancelled compiler and build children are retired through private process groups.

Qualification passed twelve final cold V builds on ARM, Rosetta x86 and ARM
ASan/UBSan, including exact original cache keys, actual compiler probe children,
cache corruption, ABI/export rejection, malformed archives, failed-build retries,
atomic publication, protected links, SIGINT/SIGTERM during lock waits and probes,
and twenty repeated publications with a flat descriptor count per profile.
Both public commands passed fresh compilation and real cache publication on
both targets. Real GNU GCC rebuilt musl 1.2.5 for x86 and 1.2.6 for ARM, then
reused each cache; independently linked static allocator tests name the staged
archive in their link maps and have no ELF interpreter. A further ARM build
passed retention disabled, the private Android accounting patch, its required
export and 64 KiB load segments, followed by cache reuse.

Original Git objects, source and qualification logs are retained at
`~/.cache/vinix-campaign-tools-native-20261012`. The committed translation receipt
is [native-translation.json](../musl/native-translation.json). No Python ran.
These checks establish host staging and linking; they do not establish a new
kernel, guest allocator execution, complete desktop build or Android boot.
