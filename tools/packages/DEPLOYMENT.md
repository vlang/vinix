# Deployment document wire API

`tools.packages.pkgprotocol.DeploymentDocument.encode() !string` writes either
supported deployment schema without inventing or upgrading a format:

- Format 1 emits exactly `format`, `architecture`, and `packages`. Supplying
  any pins in `locked` is an error; an empty `locked` member is omitted.
- Format 2 emits those fields plus `locked`, including an empty array. Every
  pin includes all seven fields, and `minimum_sequence` retains the full `u64`
  range.

Use this method instead of a general struct JSON encoder: encoding the public
struct directly would add `locked` to format 1, which its strict decoder refuses.
The returned UTF-8 JSON has no trailing newline. Root and pin order is retained;
the encoder does not sort or deduplicate a caller's arrays.

```v
import tools.packages.pkgprotocol

mut roots := ['org.example.editor']
document := pkgprotocol.DeploymentDocument{
    format: 1
    architecture: 'aarch64'
    packages: roots
}
text := document.encode()!
defer {
    unsafe { text.free(); (&array(&roots)).free() }
}
// Write text to an ordinary file, then request deployment-review FILE.
```

`encode` borrows every field and array. The caller retains its input ownership
after success or failure and owns the returned string. Do not call `close()` on
a caller-assembled document with borrowed fields. A document returned by
`decode_deployment_document(text)` independently owns its strings and arrays;
call its repeatable `close()` when finished. The decoder continues to accept
reordered object keys and requires the exact schema for the declared version.

Encoding checks supported format, valid UTF-8, at most 4096 roots and 4096 pins,
and the decoder's byte limits: architecture 16; root/pin ID and repository 128;
pin version 29; public key and metadata digest 64. The fully escaped result must
fit 8 MiB. The same checks run in production builds. Unknown future formats and
incompatible fields fail explicitly. As with decoding, wire encoding checks
shape and bounds, rather than package identity or authority: empty or duplicate
IDs, arbitrary bounded versions/digests and zero sequences may encode, then be
refused by the service.

The package service still validates architecture, canonical identities and
versions, uniqueness, complete pinned dependency closure, authenticated catalog
provenance, policy, and the separately confirmed review fingerprint. Encoding
does not enroll a publisher, grant permission, or install a package. Interface
discovery through `capabilities` can establish exact supported deployment format
membership before preparing a document.

The V-only qualification driver is
[`tests/packages/deployment-writer-build.v`](../../tests/packages/deployment-writer-build.v).
From the repository root, using a working V executable:

```sh
V=/absolute/path/to/v
"$V" -backend c -keepc -gc none -manualfree -prod \
  -o build/deployment-writer-build tests/packages/deployment-writer-build.v
V="$V" build/deployment-writer-build "$PWD" "$PWD" \
  "$PWD/build/deployment-writer-proof"
```

The output directory must be new. The driver uses explicit C compilation and
retains generated C, literal command arrays, logs, copied-source hashes, and
artifact hashes. It runs the writer tests normally and with `-prod`, both modes
with V heap tracking, ASan/UBSan, the existing strict decoder tests, and a real
normal/production package CLI consumer. That consumer accepts empty format-1/2
reviews and refuses encoded documents with semantic or catalog errors, comparing
the configuration, package tree, and input bytes before and after. Both target
musl SDK consumer ELFs are linked and their architecture checked; no target
guest is booted by this wire/API check.

The executable V, helper headers and cross clang are hashed; the imported V
libraries, transitive host tools and musl sysroots are not fully inventoried.
This records the executed builds, without a hermetic or reproducible-build
claim. LeakSanitizer is disabled on this host; separate V tracking measures
retained allocations through successful and refused encoder/decoder paths.
