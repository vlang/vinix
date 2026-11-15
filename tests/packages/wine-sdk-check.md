# Captured SDK library declaration audit

The historical additive, read-only CLI runs the retained original format-3 host builder
against a host build before auditing its captured SDK stubs:

```
wine-sdk-check ORIGINAL_HOST_BUILDER HOST_BUILD FRESH_OUTPUT
wine-sdk-controls HOST_BUILD FRESH_CONTROLS [SDK_CHECK ORIGINAL_HOST_BUILDER]
```

Build these V tools with the selected compiler, `-prod -gc none -manualfree`,
`-cflags -fno-lto` and the repository module path. The supplied host checker must
be the exact executable pinned as the host build's builder. Original host
admission must pass; the new audit cannot waive its source, executable, input,
environment, image or link checks. Outputs are created only after success.

The narrow macOS 27.2 profile checks every captured SDK TBD's current resolved
ordinary source target and bytes against the archive. Direct libm, libpthread
and libSystem aliases must resolve to libSystem.B.tbd and declare its expected
install name. It projects TAPI v4 install names and top-level
`reexported-libraries` across **all declared targets**, including inline
documents. Every reexport requires a captured separate stub whose first
document has the declared install name. Inline documents alone cannot satisfy
that file requirement. Conflicting projected declarations refuse admission.
Source targets/bytes, the host proof, archive and original checker are rechecked
before the receipt is published.

The receipt binds original checker/proof/archive hashes and records each stub's
resolved source, hash, documents and reexport edges. Preserve it with its full
original host bundle and selected SDK namespace. It is an audit observation,
not an authenticated trust anchor.

The parser accepts a bounded subset of the retained SDK's v4 syntax. Unknown
top-level fields, duplicate identities/fields, malformed declaration lists and
unsafe library paths refuse. Symbol exports and symbol reexports remain opaque;
this is not a full YAML/TAPI validator or target-specific ABI check. It does not
establish full SDK/search closure, absence of unreported reads, sandboxed replay,
OS shared-cache bytes or hermetic toolchain admission.

Current format-4 host receipts directly require this same graph projection as
`sdk-graph.json`. They recompute and compare it during admission, retain alias
and resolved source hashes/bytes, and bind the SDK implementation source through
the host builder's embedded guard. The producer, controller and full retainer
carry these rows through their mandatory host graphs. The standalone CLI keeps
its original format-3 contract for historical bundles and their original checker.

Production parser tests cover inline documents and twelve malformed/ambiguous
cases. Four graph controls cover reexport omission, alias omission, source pin
change and a foreign SDK namespace. The reexport omission fails independently
of any file-load trace, even when the inline document remains available.
The optional executable arguments add wrong-checker and incomplete-host refusals
through the real audit CLI, before any SDK receipt output is created.
