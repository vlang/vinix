# Captured host replay with exact metadata-read permissions

This additive macOS qualifier requires complete admission of an original
format-7 host build by its exact pinned checker, before and after replay:

```text
wine-metadata-closed-replay ORIGINAL_HOST_BUILDER FORMAT7_HOST_BUILD FRESH_OUTPUT
wine-metadata-closed-controls REPLAY ORIGINAL_HOST_BUILDER FORMAT7_HOST_BUILD FRESH_CONTROLS
```

Compile both V tools with the selected compiler, `-backend c -prod -gc none
-manualfree -cflags -fno-lto` and the repository module path. The replay links
`libsandbox`; preserve the frozen source namespace and imports. Its main file
and all three policy modules have embedded source guards, checked again before
publishing a receipt. Non-production replay builds refuse.

`winemetaclosure` preserves the exact file-data and ancestor-directory policy,
then denies `file-read-metadata` except for exact admitted file/ancestor paths
and the existing `/usr/lib`, `/System/Library` and device exceptions. The sorted
metadata list is recomputed from those inputs. Linker invocation and dyld use
symlinked Homebrew image paths. For each pinned ordinary image, the parent lists
its canonical directory's names (bounded at 4,096) and selects only names that
resolve to that image, including corresponding existing `/opt/homebrew/opt/`
aliases. At most 128 image alias paths and 128 symlink nodes are admitted;
discovery stops above sixteen generations of newly expanded paths.
Every resolved image must belong to the original host input map.
Exact paths and parents receive metadata permission
only; symlink targets and resolved images are recorded and recomputed after
replay. The extra metadata alias list is bounded at 128 paths. Aliases do not
acquire data-read permissions. Combined file/alias lists
retain the 8,192-path bound, safe literal validation and duplicate refusal;
ancestor expansion stops above 32,768 paths.

Captured linking and an unrestricted external-object link must both reproduce
the original executable. Observed archive loads, ordinary image hashes/UUIDs,
captured file reading, captured-directory enumeration, four denied data reads,
three denied directory enumerations and the exact external-object link refusal
remain required. The restricted external-object link must fail at its named
EPERM diagnostic, exit 1 and leave no executable.

Two new positive `stat` controls cover a captured object and its input directory.
Seven negative `stat` controls cover a separate file and directory through
direct, symlink and Data-volume paths, plus an installed SDK stub. Each must
have the expected ordinary-file/directory type unrestricted, then fail with
EPERM/EACCES, exit 81 and the exact metadata denial marker under restriction.
Each replay therefore requires four allowed controls and fifteen denials.
Raw commands, environments, exits, logs and actual LLD execution records retain
the policy used. Before publication, the parent rechecks selected bytes,
successful outputs, aliases and control marker, directory types, policy,
original proof/archive/checker/self hashes, source guards and full host admission.

The control runner requires twenty-six unsafe/list/bound/alias policy refusals,
deterministic exact metadata projection, and unchanged data permissions when
metadata aliases are added. Three CLI cases reject a wrong checker, incomplete
original bundle and old format before publishing replay receipts. Checks remain
active under `-prod`.

This qualifies the stated `file-read-metadata`/`stat` restriction during replay.
Other existence/search/metadata operations, ancestor entry names, OS-root/device
exceptions, writes/network, helper startup/inherited state and OS loader/shared-
cache bytes retain their previous scope. Receipts record local observations,
not authenticated trust anchors. Full SDK/ABI/library/search and hermetic
admission remain open. Preserve complete original prerequisites and the new
audit bundle with typed inventories outside Git. Required host receipts remain
format 7; mandatory integration, owned ARM/GUI and defaults are separate gates.
