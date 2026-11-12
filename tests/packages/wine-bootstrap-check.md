# Offline Wine prefix bootstrap, 2026-11-12

Implementation checkpoint: `b2f1239ce` (source baseline `4cbebfb07`).

This continues the [signed x86 GUI checkpoint](wine-gui-check.md) and the
[ARM shared-page diagnostic](wine-shared-pages-check.md). The retained ARM
GUI attempt also contains a separate Wineboot pledge abort on an internet
datagram socket. Shared-page warnings alone did not establish the cause of
the missing Explorer window.

Wine 9.17's
[`create_computer_name_keys`](https://github.com/wine-mirror/wine/blob/wine-9.17/programs/wineboot/wineboot.c#L924)
optionally canonicalizes the host name through `getaddrinfo`, then uses the
literal `gethostname` result if lookup fails. Prefix initialization must be
usable by a package without network permission. The private runtime now
selects that existing fallback for bootstrap computer naming. Applications
with network permission also retain the literal bootstrap name: this is a
runtime identity policy, not a replacement DNS resolver. Winsock APIs and
application network permissions are unchanged.

`wineadapter.private_bootstrap_patch` admits only the exact original
`wineboot.exe` SHA-256
`b52d86ca9b5b6dc15954bc78dc63d02a75b4e1917c75b5d6eaa8296ccd7d23c3`.
One unique guarded instruction neighborhood binds the five-byte call at file
offset `0x6864` (PE VA `0x140006864`). Replacing it with `mov eax,1` selects
the existing nonzero-result branch, without changing file length, registry
initialization or another byte. Producer and independent layout admission
both derive these exact bytes from the original captured distribution input.
This remains a local binary adaptation; complete corresponding source,
redistribution permission and catalog qualification are not asserted.

Normal, production and ASan/UBSan host checks pass immutable-input and exact
output checks plus ten unpinned/reapplied/truncated/corrupted-input refusals.
The layout checker passes original/copied baselines and thirteen executable
and symlink refusals. The evidence controller now preserves Wineboot as an
ordinary file in its copied baselines and includes omitted-original and
fully resealed restored-DNS-call controls. Its first copies correctly refused
the previously unrecognized Wineboot symlink; those failed attempts remain
preserved.

Complete native evidence checks pass all **63 x86 and 72 ARM refusals**, with
original/copied baselines and independently verified four-shard coverage per
architecture. The fresh x86 GUI passes independent signature, source, pixel,
runtime and natural-retirement admission, plus all **eleven GUI refusals**.
The admitted actual parsed-source snapshots preserve 491 files per console
run and 168 per GUI run, including the failed ARM retry. Selected host tool
copies are supplementary; original dependency bundles remain required.

Coverage/receipt SHA-256 values:

- Native x86 coverage: `46891086dc611d775b4da8a9d663455cde4a76c69f043ed6bc0d5fbafc4fce45`.
- Native ARM coverage: `8ca84d9c74c9f8886697d4bde667ef46ebd6ceb10c8bef29297a1e3e6047cfff`.
- GUI controls: `4c0b48472d70e97af9dd30f960a5513b76c654154842322bfff6e767d94919e7`.
- Independent GUI baseline: `c18397880ceaece59f992b275645912436224386a9acca0bed30cb33e7c31281`.

Fresh signed console runs pass on both architectures with the unchanged
retained kernels and sandbox policy. Fresh x86 graphical execution also passes
authenticated paint, real pointer arithmetic to `42`, natural close and
retirement. The ARM GUI retry removes the Wineboot
socket abort but remains refused: its 4 KiB shared-user-data mapping fails,
services startup reports error `731`, and Explorer does not create a desktop
window. No ARM graphical acceptance is claimed. The changed runtime therefore
isolates one bootstrap failure; it does not repair shared-page semantics or
establish the cause of services error `731`.

The read-only ARM debugger replays preserve the exact boot image and kernel.
Extraction independently confirmed the embedded kernel hash. Hardware
breakpoints did not stop on this HVF setup, with either four or one virtual
CPU. Both attempts were explicitly terminated; they supply no denied-call
register capture. The first attempt also refuses its changed maintained
producer source, while preserving the original producer copy; the second
verifies its selected input identities. These remain failed diagnostics.

Raw evidence is retained at
`/Users/alex/.cache/vinix-wine-arm-gui-20261112`. Original namespaces and the
complete [pinned dependency bundle](wine-forksafe-retention-check.md) remain
required. Compiler/source/input receipts describe selected local qualification
inputs and do not establish a hermetic build. Earlier failed GUI runs and
their historical auditors remain unchanged.

The complete original workspace, including all failed attempts and control
copies, is sealed at
`/Users/alex/Library/Caches/vinix-codex/section14/wine-bootstrap-20261112-01.tar.gz`:

- Archive SHA-256: `0d3558242e7e1105c99e36c9bf717772ea472d5c1a8abf70acba14f427b26e5d`.
- Adjacent `.inventory.txt` SHA-256: `fff1447937a72e66688873d0c229eaa7927addbf31bcc55cda8f7595af5f0c3a`.

The producer at `bccedaa5f` records gzip level 1 explicitly; the logical sparse
decoder is `32460200e`. The adjacent `.audit` preserves both sources and
binaries and confirms complete logical archive/original byte and metadata
agreement, unchanged before/after original inventories, and unchanged selected
tool/archive hashes. The archived source snapshot is `b2f1239ce`; this final
checksum report follows compression to avoid recursively including its own
archive checksum. Originals remain retained. Integrity sealing adds no launch
qualification and authorizes no removal of expanded evidence.
