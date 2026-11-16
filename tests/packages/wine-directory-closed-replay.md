# Captured host replay with exact directory-read permissions

This additive macOS qualifier requires full admission of an original format-6
host build by its exact pinned checker, then replays its captured link archive:

```
wine-directory-closed-replay ORIGINAL_HOST_BUILDER FORMAT6_HOST_BUILD FRESH_OUTPUT
wine-directory-closed-controls REPLAY ORIGINAL_HOST_BUILDER FORMAT6_HOST_BUILD FRESH_CONTROLS
```

Build both V tools with the selected compiler, `-backend c -prod -gc none
-manualfree -cflags -fno-lto`, and the repository module path. The replay links
`libsandbox`. Preserve the frozen compiled source namespace and imports: the
main file and both policy modules have embedded source guards.

The policy keeps the [ordinary file-data capability restriction](wine-read-closed-replay.md),
then replaces its global directory-type permission with exact ancestor literals.
Every admitted file contributes its parents up to `/`; ancestors are deduplicated
and sorted. Directory permission requires both directory type and one of these
exact paths. No ancestor prefix grants enumeration of all descendants. An
expansion above 32,768 distinct directories refuses during construction. The
underlying file projection still rejects unsafe/repeated literals and oversized
lists. Its expected broad-directory rule must occur exactly once before it can
be replaced; an unsupported projection refuses.

A child applies this policy before LLD exec under the existing closed environment.
Captured replay must reproduce the original executable, with observed loads in
the archive and ordinary image hashes/UUIDs matching the original host graph.
The existing captured-file read, four denied file reads and identical external-
object link controls remain required. The restricted external-object link must
reach its exact named EPERM diagnostic, exit 1 and leave no executable.

A captured-directory read must succeed and return `response.txt`. A separate
directory containing a known marker is outside the derived set. Its direct,
symlink and Data-volume paths must enumerate that marker unrestricted and fail
with EPERM/EACCES under restriction, exit 79 and the exact denial marker. This
gives two allowed controls and eight denials per replay. Raw command/environment/
exit logs and actual LLD execution records retain the policy used.

Before publishing `receipt.json`, the parent rechecks capability bytes, successful
outputs, hidden object/aliases, directory types and control marker, policy and
original proof/archive/checker/self hashes. Full original host admission runs
again after all controls, and all three source guards are checked again. The
receipt includes the exact directory list and file hash map. Preserve the whole
new output and original complete bundle with typed inventories outside Git.
These receipts are local observations, not authenticated trust anchors.

Global metadata lookups remain allowed, including name-based searches. Ancestor
directories can still expose their entry names. `/usr/lib` and `/System/Library`
remain broad data-read exceptions; the three device literals, writes/network,
helper startup/inherited state and OS loader/shared-cache bytes keep their
previous scope. This does not establish complete metadata/search, ABI, compiler
or hermetic admission. This standalone tool keeps its original format-6
admission contract. Current format-7 [required host receipts](wine-host-required-check.md)
integrate the directory policy into `winereadhost` inner receipt format 2,
requiring the directory list, policy and complete control graph at admission.
No guest or default behavior changes.

The production control runner requires twenty policy refusals, including bounded
ancestor expansion, deterministic exact-parent projection, no global directory
rule and no captured-directory prefix permission. Three CLI cases reject a wrong
checker, incomplete original bundle and old-format proof without replay receipts.
