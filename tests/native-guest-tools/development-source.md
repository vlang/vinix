# Native package source export qualification

The development fixture now exports the real package CLI's complete repository
module closure from verified committed Git blobs. This includes the package
administration/launch and SDK modules, output PCM portal, X11 authentication,
account transport, plist reader and internal signing implementation. The native
package build searches both the exported root and its `tools/accounts` directory.
The existing source filter still excludes tests, Python and nonregular blobs.

`check-development-source.v` passed six explicit checks on 2026-10-26 against
committed package sources at `0bf315dc8`. AArch64 and x86-64 each generated the
actual `tools/packages/main.v` production C from the export. Each architecture
also rejected a withheld `audiopcm` module and a missing account-module search
path, with the expected import diagnostic. The compiler ran from an external
working directory with an empty module cache and an explicit search path.
The fixture and checker share the export and module-path implementation.

Evidence is retained at
`/Users/alex/Library/Caches/vinix-codex/section14/native-source-export-20261026`.
It includes the committed source export, exact checker/fixture/helper snapshots,
literal compiler arguments, logs, generated C and before/after input hashes.
The selected V executable and its sources reuse the retained
`package-audio-portal-20261026/host-02/toolchain` bundle; that complete bundle is
a required input, rather than a newly duplicated compiler snapshot.

- V SHA-256: `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`
- `inputs.json`: `bffe96f8004417ed86fe69388c57b24f3ef6e03eb1c3a0ffecd2cb31750797a9`
- `qualification.json`: `36b4fc36b3905a248db9b5b3eefbe201639734527186a2809dcc7aa65e8ad0e9`

These checks qualify the source selection and translation for both targets.
They do not build or boot a guest image, link a target binary, or qualify the
separate native compiler's execution in a guest.
