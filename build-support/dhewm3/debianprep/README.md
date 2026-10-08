# Debian comparison preparation

The native controller owns the cloud-kernel and minimal-userland preparation
workflow. The Python entry keeps argparse and imported library bindings. The V
policy preserves the package-index cache branches, actual module registration
before execution, last-name-wins lookup, first kernel dependency, original
download/extract calls, userland argv and metadata/output policy.

Package, Namespace, Path, module, loader and dependency iterator objects remain
owned in the synchronous shared host resource table. No new file or context
owner is introduced; existing controller retirement remains bounded.

The 2,639-byte source was frozen at
`31fda527fadbcea2e1b6152463e3948ad0696a36`. This whole workflow removes a net
1,566 Python bytes / 31 lines with no new bridge primitives. The migrated policy
is 2,096 bytes / 39 lines after argparse. Frozen/native qualification
passes 25 workflow/cache/error controls, three exact CLI controls and 100
error-identity/FD requests on ARM64, actual x86-64 and ARM64 ASan/UBSan. Cold
installation produces both actual host ABIs. Real LZMA bytes and host files are
used; external download, extraction and userland commands are fixture callbacks.
This does not claim a full Debian guest boot.

Evidence: `~/.cache/vinix-python-to-v/dhewm-debian-prepare-20261009/`.
