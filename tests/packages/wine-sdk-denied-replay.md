# Captured host replay with installed SDK reads denied

This additive macOS qualifier requires successful admission by the original
format-4 host checker, then replays its captured link archive in a fresh directory:

```
wine-sdk-denied-replay ORIGINAL_HOST_BUILDER HOST_BUILD FRESH_OUTPUT
wine-sdk-denied-controls REPLAY ORIGINAL_HOST_BUILDER HOST_BUILD FRESH_CONTROLS
```

Build both V tools with the selected compiler, `-backend c -prod -gc none
-manualfree -cflags -fno-lto`, and the repository module path
(`-path '@vlib|/absolute/source/root|@vmodules'`). The replay tool links macOS
`libsandbox`. Preserve its source at the compiled `@FILE` path: an embedded
source guard rejects later changes. Use a frozen source namespace for retained
qualifications. The original host bundle, checker and their complete selected
namespaces remain prerequisites.

Before executing the pinned LLD, a child calls `sandbox_init` with an allow-default
policy denying `file-read*` under `/Library/Developer/CommandLineTools/SDKs` and
its `/System/Volumes/Data` alias. Captured inputs reside outside those roots.
The child records the policy, command and closed re-exec environment. The parent
checks the observed file loads against captured archive members, ordinary loaded
image UUIDs/hashes against the original graph, and the output against the original
executable hash.

Each qualification also requires four controls. Direct SDK reads, a private
symlink and the Data-volume alias must read the expected source bytes outside
the restriction and fail with EPERM/EACCES inside it. A response using the
absolute installed SDK must reproduce identical bytes without restriction, then
fail under restriction with exactly one missing-library diagnostic for each of
`-lm`, `-lpthread` and `-lSystem`, exit 1 and no executable. Unrelated failures
cannot satisfy these controls. The separate admission runner rejects a wrong
checker, an incomplete original bundle and an old-format proof without receipts.

Before publishing `receipt.json`, the tool rechecks captured members, both
successful outputs, observed ordinary images, SDK source graph, original proof,
archive, checker and itself. Raw commands, environments, execution records and
logs stay alongside the receipt. Preserve the complete directory with a typed
inventory outside Git. Receipts record observations and are not authenticated
trust anchors.

The restriction covers installed CLT SDK path reads during LLD replay. Other
filesystem access and network access remain allowed. The helper starts before
applying the restriction; bootstrap and OS loader/shared-cache bytes remain
unqualified. The installed SDK is still needed for original admission, source
rechecks and unrestricted controls. This does not establish complete search/read
closure, ABI interpretation or hermetic toolchain admission, and does not change
the mandatory format-4 host receipt or guest/default behavior.

Current format-5 required host receipts integrate the same narrow restriction
through `winesdkdeny`, with all replay/control artifacts mandatory in the host
graph. The standalone tool above keeps its original format-4 admission contract
for historical bundles. See [required host receipts](wine-host-required-check.md).
