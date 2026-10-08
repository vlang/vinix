# Native macOS AGX inspection

This module collects selected GPU topology, range, firmware and driver identity
properties. `../inspect_macos` is the maintained CLI; it compiles the V source
through `build-support/run-v-tool.sh`. It accepts the original saved-plist
options, optional live registry nodes and compact-output flag. Live collection
uses literal read-only `ioreg` argument vectors and drains both output pipes.
Serial numbers, registry IDs and unselected configuration properties remain
excluded from the manifest.

`parse_plist` reads binary and XML property lists into typed `Property` values.
Binary integer payloads and XML integer text retain arbitrary precision. Strings
retain whitespace and embedded NULs; binary data is copied before returning.
XML syntax uses the unchanged system Expat library (`expat.h`, `-lexpat`), with
native V handlers for property conversion. The Expat parser is released on every
success/error path, and callback buffers are borrowed only during callbacks.
The host uses V's collector; this module changes no kernel allocation lifetime.
Dates and UIDs remain opaque typed properties because the selected manifest
fields do not consume them. Selecting such a value for JSON output reports the
original unsupported serialization category.

`testdata/contracts.json` contains frozen independent inputs and complete
results from the original inspection tests, with their original test names.
Native tests replay these contracts and check the patchbay table against the
maintained power recovery authority, plus wide integers, Unicode, JSON ordering,
binary layouts, malformed XML and copied-input lifetimes. Run:

```sh
. ../../build-support/find-v.sh
"$V" -cc cc test macinspect
```

Machine-local original/native controls and source-bound receipts are under
`~/.cache/vinix-python-to-v/mac-inspect-20261008/`. Frozen originals remain in Git.
No physical GPU execution is claimed by these host controls.

Sanitizer checks cover both collected and uncollected host binaries. Boehm
checks use the real stack; a separate `-gc none` sanitizer binary enables
ASan fake-stack checking. The unchanged V `math.big` library reproduces large
integer corruption when Boehm is combined with ASan fake-stack relocation,
so that incompatible configuration is recorded separately. All integer-width
assertions remain identical in the passing configurations.
