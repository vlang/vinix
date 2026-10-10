# Read-only ANS reference comparison

`verify-reads` compiles and invokes V directly. It records SHA-256 samples from
a user-trusted reference and compares the same ranges with repeated reads.
The source is opened once, read-only and close-on-exec; the opened descriptor
must identify a regular image or block device. Manifest publication exclusively
creates a new regular file with mode 0600 and syncs it. Existing files, symlinks
(including dangling links), directories and devices cannot be overwritten.

```sh
tools/apple-ans/verify-reads record image reference.json \
    --label 'Trusted reference' --range 0:8192 --range 12345:8001
tools/apple-ans/verify-reads check image reference.json --passes 2
tools/apple-ans/test-verify-reads
```

The native suite builds the command and tests all seven original scenarios,
independent `shasum -a 256` comparisons, exact JSON integers above 2^53, signed
offset bounds, Boolean/float rejection, range order and adjacency, source
replacement after opening, Unicode integer grammar and labels, bounded manifest
loads, UTF-8/16/32 decoding, CLI statuses and repeated descriptor retirement.
It uses private synthetic regular files and `/dev/null` for type and
exclusive-create rejection. It does not access an ANS device. The tests require
V and `shasum`.

For a prebuilt command, `VINIX_ANS_READS_TOOL=/absolute/path/verify-reads v test
tools/apple-ans/ansreads` also includes subprocess tests; without that variable,
the module suite tests the API only. Use `-nocache -cc cc` for fresh host builds.
Qualification runs use ARM, Rosetta x86 and ARM ASan/UBSan, with independent
builds of the command and tests for each profile.

The manifest schema, hashes, range order, three chunk patterns, pass counts and
report fields are retained. Manifest input is limited to 1 MiB. Numeric JSON
tokens remain exact, including ignored large metadata values. UTF-8, UTF-16 and
UTF-32 manifests with JSON encoding autodetection are accepted. Invalid input
encodings are rejected. Usage text and OS/JSON error wording are native; informational
`reference_system` and `system` use `uname`'s system, release and machine rather
than the former interpreter's platform formatting. PASS means matching bytes
against the supplied reference. It does not establish physical hardware identity
or power-loss persistence. Native executables for a guest must be built for
that guest's architecture and bootstrap userland; host qualification does not
establish a guest or hardware run.
